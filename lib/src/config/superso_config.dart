/// Connection configuration shared by every module in the SDK.
///
/// Dart port of `supersosdk/src/config/SupersoConfig.ts`.
library;

import '../errors/superso_error.dart';

/// Signature for the logger the SDK writes diagnostics through.
///
/// The SDK never calls `print` directly (the `avoid_print` lint forbids it and
/// a published package must not write to a consumer's console uninvited).
/// Supply a logger to see request/response diagnostics:
///
/// ```dart
/// Superso(
///   baseUrl: '...',
///   logger: (level, message, [error]) => debugPrint('[$level] $message'),
/// );
/// ```
typedef SupersoLogger = void Function(
  SupersoLogLevel level,
  String message, [
  Object? error,
]);

/// Severity levels passed to a [SupersoLogger].
enum SupersoLogLevel {
  /// Verbose tracing — request URLs, retry attempts, socket state changes.
  debug,

  /// Notable but expected events.
  info,

  /// Recoverable problems, e.g. a retry being scheduled.
  warning,

  /// Failures surfaced to the caller.
  error,
}

/// Inspects and optionally rewrites a request before it is sent.
///
/// Interceptors run in registration order. Each receives the outgoing request
/// and returns the request to actually send — return the input unchanged to
/// observe without modifying.
typedef RequestInterceptor = Future<InterceptedRequest> Function(
  InterceptedRequest request,
);

/// Inspects a response before it is decoded and returned to the caller.
typedef ResponseInterceptor = Future<InterceptedResponse> Function(
  InterceptedResponse response,
);

/// A mutable snapshot of an outgoing request, handed to a [RequestInterceptor].
class InterceptedRequest {
  /// Creates an intercepted request.
  InterceptedRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });

  /// The HTTP verb, e.g. `POST`.
  String method;

  /// The fully-resolved request URL, including any query string.
  String url;

  /// Headers that will be sent. Mutate freely.
  Map<String, String> headers;

  /// The request body prior to encoding, or `null` for bodyless requests.
  Object? body;
}

/// A snapshot of a response, handed to a [ResponseInterceptor].
class InterceptedResponse {
  /// Creates an intercepted response.
  InterceptedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.url,
  });

  /// The HTTP status code.
  final int statusCode;

  /// Response headers.
  final Map<String, String> headers;

  /// The raw response body text.
  String body;

  /// The URL that produced this response.
  final String url;
}

/// Controls automatic retry of failed requests.
///
/// The TypeScript SDK has no retry layer — `fetch` is called once and any
/// failure surfaces immediately. Mobile clients need more than that, because a
/// request issued as the device switches between Wi-Fi and cellular fails for
/// reasons that resolve on their own within a second. Retries are therefore
/// enabled by default here, but restricted to cases where a retry is provably
/// safe: transport failures and 5xx/429 responses on idempotent verbs only.
/// A `POST` that reached the server is never retried, since the server may
/// have already applied it.
class RetryPolicy {
  /// Creates a retry policy.
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(milliseconds: 300),
    this.backoffMultiplier = 2.0,
    this.maxBackoff = const Duration(seconds: 5),
    this.retryOnStatus = const <int>{408, 429, 500, 502, 503, 504},
    this.retryableMethods = const <String>{'GET', 'HEAD', 'PUT', 'DELETE'},
  })  : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
        assert(backoffMultiplier >= 1, 'backoffMultiplier must be >= 1');

  /// A policy that disables retries entirely, matching the JS SDK's behaviour.
  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);

  /// Total attempts including the first. `1` disables retrying.
  final int maxAttempts;

  /// Delay before the second attempt.
  final Duration initialBackoff;

  /// Factor applied to the delay after each failed attempt.
  final double backoffMultiplier;

  /// Upper bound on any single backoff delay.
  final Duration maxBackoff;

  /// HTTP statuses that should be retried.
  final Set<int> retryOnStatus;

  /// Verbs safe to retry. `POST` and `PATCH` are excluded by default because
  /// they are not idempotent.
  final Set<String> retryableMethods;

  /// Computes the delay before attempt number [attempt] (1-based).
  Duration backoffFor(int attempt) {
    if (attempt <= 1) return Duration.zero;
    final micros = initialBackoff.inMicroseconds *
        _pow(backoffMultiplier, attempt - 2);
    final capped = micros.clamp(0, maxBackoff.inMicroseconds.toDouble());
    return Duration(microseconds: capped.toInt());
  }

  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}

/// The single source of truth for connection settings shared by every service
/// module (auth, database, storage, realtime, media, notification, payment,
/// ai).
///
/// No module keeps its own copy of [baseUrl], [apiKey], headers, or the access
/// token — everything is read from this instance through the shared HTTP
/// client.
class SupersoConfig {
  /// Creates a configuration.
  ///
  /// Throws a [ValidationError] if [baseUrl] is empty.
  SupersoConfig({
    required String baseUrl,
    String? apiKey,
    String? accessToken,
    String? refreshToken,
    Map<String, String>? defaultHeaders,
    Duration timeout = const Duration(seconds: 30),
    this.retryPolicy = const RetryPolicy(),
    this.logger,
  })  : _apiKey = apiKey,
        _accessToken = accessToken,
        _refreshToken = refreshToken,
        _defaultHeaders = Map<String, String>.of(
          defaultHeaders ?? const <String, String>{},
        ),
        timeout = timeout {
    if (baseUrl.isEmpty) {
      throw const ValidationError(
        'Superso: `baseUrl` is required to initialize the SDK.',
      );
    }
    _baseUrl = _stripTrailingSlash(baseUrl);
  }

  late String _baseUrl;
  String? _apiKey;
  String? _accessToken;
  String? _refreshToken;
  final Map<String, String> _defaultHeaders;

  /// Per-request timeout. Defaults to 30 seconds, matching the JS SDK.
  final Duration timeout;

  /// How failed requests are retried. See [RetryPolicy].
  final RetryPolicy retryPolicy;

  /// Optional sink for SDK diagnostics. `null` disables logging entirely.
  final SupersoLogger? logger;

  final List<RequestInterceptor> _requestInterceptors = <RequestInterceptor>[];
  final List<ResponseInterceptor> _responseInterceptors =
      <ResponseInterceptor>[];

  /// Base URL of the Superso API, e.g. `https://api.superso.io/v1`.
  String get baseUrl => _baseUrl;

  /// Project/application API key, sent as `x-api-key` on every request.
  String? get apiKey => _apiKey;

  /// A copy of the headers merged into every request.
  Map<String, String> get defaultHeaders =>
      Map<String, String>.unmodifiable(_defaultHeaders);

  /// Registered request interceptors, in execution order.
  List<RequestInterceptor> get requestInterceptors =>
      List<RequestInterceptor>.unmodifiable(_requestInterceptors);

  /// Registered response interceptors, in execution order.
  List<ResponseInterceptor> get responseInterceptors =>
      List<ResponseInterceptor>.unmodifiable(_responseInterceptors);

  /// Updates the project/application API key used on every request.
  void setApiKey(String apiKey) => _apiKey = apiKey;

  /// Stores the access token (JWT) sent as `Authorization: Bearer <token>`.
  void setAccessToken(String accessToken) => _accessToken = accessToken;

  /// Clears the stored access token, e.g. on logout.
  void clearAccessToken() => _accessToken = null;

  /// Returns the currently stored access token, if any.
  String? getAccessToken() => _accessToken;

  /// Stores the refresh token used to obtain new access tokens.
  void setRefreshToken(String refreshToken) => _refreshToken = refreshToken;

  /// Clears the stored refresh token, e.g. on logout.
  void clearRefreshToken() => _refreshToken = null;

  /// Returns the currently stored refresh token, if any.
  String? getRefreshToken() => _refreshToken;

  /// Sets or replaces a single default header.
  void setHeader(String name, String value) => _defaultHeaders[name] = value;

  /// Removes a default header.
  void removeHeader(String name) => _defaultHeaders.remove(name);

  /// Registers a [RequestInterceptor], returning a callback that removes it.
  void Function() addRequestInterceptor(RequestInterceptor interceptor) {
    _requestInterceptors.add(interceptor);
    return () => _requestInterceptors.remove(interceptor);
  }

  /// Registers a [ResponseInterceptor], returning a callback that removes it.
  void Function() addResponseInterceptor(ResponseInterceptor interceptor) {
    _responseInterceptors.add(interceptor);
    return () => _responseInterceptors.remove(interceptor);
  }

  /// Writes a diagnostic through [logger], if one is configured.
  void log(SupersoLogLevel level, String message, [Object? error]) {
    logger?.call(level, message, error);
  }

  /// Resolves a resource path (e.g. `/auth/login`) against [baseUrl].
  ///
  /// This is the ONLY place base URL and path concatenation happens — no
  /// module should ever build URLs manually.
  String resolveUrl(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$_baseUrl$cleanPath';
  }

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
