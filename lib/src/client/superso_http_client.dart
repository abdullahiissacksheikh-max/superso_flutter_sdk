/// The shared HTTP transport used by every module in the SDK.
///
/// Dart port of `supersosdk/src/client/HttpClient.ts`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/superso_config.dart';
import '../errors/superso_error.dart';
import '../types/common.dart';
import '../utils/url.dart';

/// The ONLY component in the SDK allowed to build headers, resolve URLs, or
/// issue network requests.
///
/// Every service module (auth, database, storage, realtime, media,
/// notification, payment, ai) receives the same instance and must route every
/// request through it. This guarantees, SDK-wide:
///
///  - `x-api-key` is attached automatically whenever an API key is configured.
///  - `Authorization: Bearer <token>` is attached automatically whenever an
///    access token has been set via [setAccessToken].
///  - Base URL and path joining happen in exactly one place.
///  - Errors map to the shared [SupersoError] hierarchy consistently.
///
/// No module should ever construct headers, concatenate URLs, or call
/// `package:http` directly — always go through this client.
class SupersoHttpClient {
  /// Creates a client bound to [config].
  ///
  /// [httpClient] exists so tests can inject a mock transport; production code
  /// should omit it and let the client own its own [http.Client].
  SupersoHttpClient(this.config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// The configuration backing this client.
  final SupersoConfig config;

  final http.Client _http;
  final bool _ownsHttpClient;
  bool _closed = false;

  /// Resolves a resource path against the configured base URL.
  String resolveUrl(String path) => config.resolveUrl(path);

  /// Returns the configured project/application API key, if any.
  ///
  /// Used by modules (e.g. Realtime and Media signalling) that need to attach
  /// it somewhere other than the `x-api-key` header — for example as a
  /// WebSocket handshake query parameter, since browsers cannot set custom
  /// headers on a WebSocket upgrade.
  String? getApiKey() => config.apiKey;

  // ── Token management passthroughs ──────────────────────────────────────
  // SupersoConfig remains the single source of truth for tokens. Modules
  // call these instead of touching config directly, so there is exactly one
  // code path for token storage.

  /// Stores the access token (JWT) sent as `Authorization: Bearer <token>`.
  void setAccessToken(String accessToken) => config.setAccessToken(accessToken);

  /// Returns the currently stored access token, if any.
  String? getAccessToken() => config.getAccessToken();

  /// Clears the stored access token, e.g. on logout.
  void clearAccessToken() => config.clearAccessToken();

  /// Stores the refresh token used to obtain new access tokens.
  void setRefreshToken(String refreshToken) =>
      config.setRefreshToken(refreshToken);

  /// Returns the currently stored refresh token, if any.
  String? getRefreshToken() => config.getRefreshToken();

  /// Clears the stored refresh token, e.g. on logout.
  void clearRefreshToken() => config.clearRefreshToken();

  // ── Verb helpers ───────────────────────────────────────────────────────

  /// Issues a `GET` request.
  Future<ApiResponse<T>> get<T>(
    String path, {
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) =>
      send<T>(HttpMethod.get, path, options: options, decoder: decoder);

  /// Issues a `POST` request with an optional JSON [body].
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? body,
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) =>
      send<T>(HttpMethod.post, path,
          body: body, options: options, decoder: decoder);

  /// Issues a `PUT` request with an optional JSON [body].
  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? body,
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) =>
      send<T>(HttpMethod.put, path,
          body: body, options: options, decoder: decoder);

  /// Issues a `PATCH` request with an optional JSON [body].
  Future<ApiResponse<T>> patch<T>(
    String path, {
    Object? body,
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) =>
      send<T>(HttpMethod.patch, path,
          body: body, options: options, decoder: decoder);

  /// Issues a `DELETE` request with an optional JSON [body].
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Object? body,
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) =>
      send<T>(HttpMethod.delete, path,
          body: body, options: options, decoder: decoder);

  /// Uploads [files] as `multipart/form-data`, alongside optional [fields].
  ///
  /// The Content-Type header is deliberately not set here — `package:http`
  /// generates `multipart/form-data; boundary=...` itself, and overriding it
  /// without the generated boundary breaks server-side multipart parsing
  /// entirely. This mirrors the same constraint documented in the JS SDK's
  /// `postFormData`.
  Future<ApiResponse<T>> postMultipart<T>(
    String path, {
    required List<http.MultipartFile> files,
    Map<String, String> fields = const <String, String>{},
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) async {
    _assertOpen();
    final url = _buildUrl(path, options?.query);
    final request = http.MultipartRequest('POST', Uri.parse(url))
      ..fields.addAll(fields)
      ..files.addAll(files);

    final headers = _buildHeaders(extra: options?.headers, isMultipart: true);
    request.headers.addAll(headers);

    config.log(SupersoLogLevel.debug, 'POST (multipart) $url');

    try {
      final streamed = await _withCancellation(
        _http.send(request),
        options?.cancelToken,
      ).timeout(options?.timeout ?? config.timeout);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse<T>(response, url, decoder);
    } on TimeoutException {
      throw NetworkError('Request timed out: POST $url');
    } on SupersoError {
      rethrow;
    } on Object catch (err) {
      throw NetworkError('Network request failed: $err', err);
    }
  }

  /// Issues a request with an arbitrary [method]. Prefer the verb helpers.
  ///
  /// When [decoder] is omitted, the envelope's `data` is returned as-is and
  /// [T] must be compatible with the raw decoded JSON (typically
  /// `Map<String, dynamic>`, `List<dynamic>`, or `void`).
  Future<ApiResponse<T>> send<T>(
    HttpMethod method,
    String path, {
    Object? body,
    RequestOptions? options,
    T Function(Object? data)? decoder,
  }) async {
    _assertOpen();
    final url = _buildUrl(path, options?.query);
    final isRetryable =
        config.retryPolicy.retryableMethods.contains(method.value);
    final maxAttempts = isRetryable ? config.retryPolicy.maxAttempts : 1;

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        final delay = config.retryPolicy.backoffFor(attempt);
        config.log(
          SupersoLogLevel.debug,
          'Retrying ${method.value} $url (attempt $attempt/$maxAttempts) '
          'after ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      }

      try {
        return await _attempt<T>(method, url, body, options, decoder);
      } on CancelledError {
        rethrow;
      } on ValidationError {
        rethrow;
      } on AuthenticationError {
        rethrow;
      } on PermissionError {
        rethrow;
      } on NotFoundError {
        rethrow;
      } on ConflictError {
        rethrow;
      } on SupersoError catch (err) {
        lastError = err;
        final status = err.status;
        final retryable =
            status == null || config.retryPolicy.retryOnStatus.contains(status);
        if (!retryable || attempt == maxAttempts) rethrow;
      }
    }

    // Unreachable in practice: the loop either returns or rethrows.
    throw lastError is SupersoError
        ? lastError
        : NetworkError('Request failed: ${method.value} $url');
  }

  Future<ApiResponse<T>> _attempt<T>(
    HttpMethod method,
    String url,
    Object? body,
    RequestOptions? options,
    T Function(Object? data)? decoder,
  ) async {
    var intercepted = InterceptedRequest(
      method: method.value,
      url: url,
      headers: _buildHeaders(extra: options?.headers),
      body: body,
    );
    for (final interceptor in config.requestInterceptors) {
      intercepted = await interceptor(intercepted);
    }

    final encodedBody =
        intercepted.body == null ? null : jsonEncode(intercepted.body);

    config.log(
        SupersoLogLevel.debug, '${intercepted.method} ${intercepted.url}');

    final request = http.Request(intercepted.method, Uri.parse(intercepted.url))
      ..headers.addAll(intercepted.headers);
    if (encodedBody != null) request.body = encodedBody;

    try {
      final streamed = await _withCancellation(
        _http.send(request),
        options?.cancelToken,
      ).timeout(options?.timeout ?? config.timeout);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse<T>(response, intercepted.url, decoder);
    } on TimeoutException {
      throw NetworkError(
        'Request timed out after '
        '${(options?.timeout ?? config.timeout).inMilliseconds}ms: '
        '${intercepted.method} ${intercepted.url}',
      );
    } on SupersoError {
      rethrow;
    } on Object catch (err) {
      throw NetworkError('Network request failed: $err', err);
    }
  }

  Future<ApiResponse<T>> _handleResponse<T>(
    http.Response response,
    String url,
    T Function(Object? data)? decoder,
  ) async {
    var intercepted = InterceptedResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body,
      url: url,
    );
    for (final interceptor in config.responseInterceptors) {
      intercepted = await interceptor(intercepted);
    }

    final text = intercepted.body;
    final json = text.isEmpty ? null : _safeJsonDecode(text);

    if (intercepted.statusCode < 200 || intercepted.statusCode >= 300) {
      final message = _extractErrorMessage(json, 'Request failed.');
      final details = _extractErrorDetails(json);
      config.log(
        SupersoLogLevel.error,
        'HTTP ${intercepted.statusCode} $url — $message',
      );
      throw errorFromResponse(intercepted.statusCode, message, details);
    }

    if (json is Map<String, dynamic>) {
      return ApiResponse<T>.fromJson(
        json,
        (data) => _decode<T>(data, decoder),
      );
    }

    // A 2xx with an empty or non-object body — treated as a bare success
    // acknowledgement, exactly as the JS SDK does.
    return ApiResponse<T>(
      success: true,
      message: '',
      data: _decode<T>(json, decoder),
    );
  }

  T _decode<T>(Object? data, T Function(Object? data)? decoder) {
    if (decoder != null) return decoder(data);
    if (data is T) return data;
    // `void` / dynamic call sites: there is nothing meaningful to return.
    if (null is T) return null as T;
    throw SupersoError(
      message: 'Superso: response payload was ${data.runtimeType}, '
          'which is not assignable to the expected type $T. '
          'Pass a `decoder` to convert it explicitly.',
      code: 'DECODE_ERROR',
      details: data,
    );
  }

  Map<String, String> _buildHeaders({
    Map<String, String>? extra,
    bool isMultipart = false,
  }) {
    final headers = <String, String>{
      // A multipart body must NOT get an explicit Content-Type here — the
      // http package sets `multipart/form-data; boundary=...` itself. Setting
      // it manually (without the generated boundary) breaks server-side
      // multipart parsing entirely.
      if (!isMultipart) 'Content-Type': 'application/json',
      ...config.defaultHeaders,
      if (extra != null) ...extra,
    };

    final apiKey = config.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['x-api-key'] = apiKey;
    }

    final token = config.getAccessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  String _buildUrl(String path, Map<String, Object?>? query) {
    final resolved = resolveUrl(path);
    if (query == null || query.isEmpty) return resolved;
    return '$resolved${buildQueryString(query)}';
  }

  /// Races [operation] against [token]'s cancellation.
  Future<S> _withCancellation<S>(Future<S> operation, CancelToken? token) {
    if (token == null) return operation;
    if (token.isCancelled) {
      return Future<S>.error(CancelledError(token.reason!));
    }
    final completer = Completer<S>();
    void onCancel(String reason) {
      if (!completer.isCompleted) {
        completer.completeError(CancelledError(reason));
      }
    }

    token.addListener(onCancel);
    // The underlying request keeps running after a cancellation — there is no
    // way to abort an in-flight HTTP call portably — but its result is
    // discarded, and its error is still consumed here so it never surfaces as
    // an unhandled async error.
    unawaited(
      operation.then((value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      }).catchError((Object error, StackTrace stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      }).whenComplete(() => token.removeListener(onCancel)),
    );
    return completer.future;
  }

  void _assertOpen() {
    if (_closed) {
      throw const SupersoError(
        message: 'Superso: this client has been disposed and can no longer '
            'issue requests. Construct a new Superso instance.',
        code: 'CLIENT_DISPOSED',
      );
    }
  }

  /// Releases the underlying HTTP connection pool.
  ///
  /// Call this when the SDK instance is no longer needed — typically from a
  /// `State.dispose` or a service-locator teardown. Requests issued after
  /// disposal throw a [SupersoError] with code `CLIENT_DISPOSED`.
  void dispose() {
    if (_closed) return;
    _closed = true;
    if (_ownsHttpClient) _http.close();
  }
}

Object? _safeJsonDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return <String, dynamic>{'success': false, 'message': text};
  }
}

/// Extracts a human-readable error message from an error body.
///
/// Different Superso services document slightly different error envelopes —
/// Auth uses a flat `{ message }`, Database uses a nested
/// `{ error: { code, message } }` — so this checks both shapes rather than
/// forcing every module to re-implement the same extraction logic.
String _extractErrorMessage(Object? json, String fallback) {
  if (json is Map<String, dynamic>) {
    final message = json['message'];
    if (message is String && message.isNotEmpty) return message;
    final error = json['error'];
    if (error is Map<String, dynamic>) {
      final nested = error['message'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
  }
  return fallback;
}

/// Extracts the backend's structured `error.details` payload, when present.
///
/// The platform populates this for Database document errors and, since
/// backend v0.3.1, API-key permission rejections. Surfacing it verbatim means
/// a caller can read `(e.details as Map)['required_permission']` without the
/// SDK needing per-module knowledge of what the backend put there.
Object? _extractErrorDetails(Object? json) {
  if (json is Map<String, dynamic>) {
    final error = json['error'];
    if (error is Map<String, dynamic>) {
      return error['details'] ?? error;
    }
  }
  return json;
}
