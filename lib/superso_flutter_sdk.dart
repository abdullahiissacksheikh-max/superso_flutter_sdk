/// Official Flutter SDK for Superso Core.
///
/// A single [Superso] instance gives you Auth, Database, Storage, Realtime,
/// Media, Notifications, Payments, and AI through one shared configuration and
/// HTTP client, so headers, base URLs, and token handling are never duplicated
/// across modules.
///
/// ```dart
/// import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';
///
/// final superso = Superso(
///   baseUrl: 'https://api.superso.io/v1',
///   apiKey: 'sp_live_xxxxxxxxx',
/// );
///
/// final result = await superso.auth.login(
///   email: 'ada@example.com',
///   password: 'correct horse battery staple',
/// );
/// // Tokens are captured automatically — no manual setAccessToken() needed.
///
/// final posts = await superso.database
///     .collection('posts')
///     .where('published', WhereOperator.equal, true)
///     .orderBy('created_at', OrderByDirection.desc)
///     .limit(20)
///     .get();
/// ```
///
/// This package mirrors the official JavaScript SDK (`supersosdk`) module for
/// module and endpoint for endpoint, adapted to idiomatic Dart: immutable
/// models with `fromJson`, `Future`-based calls, `Stream`-based events, typed
/// exceptions, [CancelToken] in place of `AbortSignal`, and explicit
/// [Superso.dispose] for resource teardown.
library superso_flutter_sdk;

import 'src/ai/ai_module.dart';
import 'src/auth/auth_module.dart';
import 'src/client/superso_http_client.dart';
import 'src/config/superso_config.dart';
import 'src/database/database_module.dart';
import 'src/interfaces/sdk_module.dart';
import 'src/media/media_module.dart';
import 'src/notification/notification_module.dart';
import 'src/payment/payment_module.dart';
import 'src/realtime/realtime_module.dart';
import 'src/storage/storage_module.dart';

export 'src/ai/ai.dart';
export 'src/auth/auth.dart';
export 'src/client/superso_http_client.dart';
export 'src/config/superso_config.dart';
export 'src/database/database.dart';
export 'src/errors/superso_error.dart';
export 'src/interfaces/sdk_module.dart';
export 'src/media/media.dart';
export 'src/notification/notification.dart';
export 'src/payment/payment.dart';
export 'src/realtime/realtime.dart';
export 'src/storage/storage.dart';
export 'src/types/common.dart';
export 'src/utils/mime.dart' show defaultMimeType, inferMimeType;
export 'src/utils/url.dart' show buildQueryString, encodeSegment, joinPath;

/// The single entry point for the `superso_flutter_sdk` package.
///
/// Construct one instance with your project's base URL and API key; every
/// service module shares the same configuration and HTTP client underneath.
///
/// Create the instance once for the lifetime of the app — typically as a
/// provider, a service-locator singleton, or an `InheritedWidget` — and call
/// [dispose] when it is no longer needed.
class Superso implements Disposable {
  /// Creates a Superso client.
  ///
  /// [baseUrl] is required and must include the API version, e.g.
  /// `https://api.superso.io/v1`. [apiKey] identifies your project and is sent
  /// as `x-api-key` on every request.
  ///
  /// [timeout] bounds each request (default 30 seconds). [retryPolicy] controls
  /// automatic retries of transport failures and 5xx/429 responses on
  /// idempotent verbs — see [RetryPolicy]. Supply [logger] to observe SDK
  /// diagnostics; nothing is logged when it is null.
  ///
  /// [httpClient] exists for tests, which can inject a mock transport.
  Superso({
    required String baseUrl,
    String? apiKey,
    String? accessToken,
    String? refreshToken,
    Map<String, String>? defaultHeaders,
    Duration timeout = const Duration(seconds: 30),
    RetryPolicy retryPolicy = const RetryPolicy(),
    SupersoLogger? logger,
    SupersoHttpClient? httpClient,
  })  : config = SupersoConfig(
          baseUrl: baseUrl,
          apiKey: apiKey,
          accessToken: accessToken,
          refreshToken: refreshToken,
          defaultHeaders: defaultHeaders,
          timeout: timeout,
          retryPolicy: retryPolicy,
          logger: logger,
        ),
        _injectedClient = httpClient {
    client = _injectedClient ?? SupersoHttpClient(config);
    auth = AuthModule(client);
    database = DatabaseModule(client);
    storage = StorageModule(client);
    realtime = RealtimeModule(client);
    media = MediaModule(client);
    notification = NotificationModule(client);
    payment = PaymentModule(client);
    ai = AIModule(client);
  }

  /// The shared configuration backing every module.
  final SupersoConfig config;

  final SupersoHttpClient? _injectedClient;

  /// The shared HTTP client every module issues requests through.
  late final SupersoHttpClient client;

  /// Authentication — sign-up, sign-in, OTP, OAuth, profile, user management.
  late final AuthModule auth;

  /// Document database — collections, documents, queries, batches,
  /// transactions.
  late final DatabaseModule database;

  /// File storage — buckets, uploads, downloads, chunked sessions, and
  /// realtime file events.
  late final StorageModule storage;

  /// Realtime — channels, presence, broadcast, and the database event bridge.
  late final RealtimeModule realtime;

  /// Media — sessions, participants, moderation, voice rooms, classroom,
  /// whiteboard, breakout rooms, and realtime session events.
  late final MediaModule media;

  /// Notifications — send, broadcast, trigger, inbox, templates, schedules,
  /// queue, devices, preferences, and providers.
  late final NotificationModule notification;

  /// Payments — WaafiPay-family operations plus Stripe.
  late final PaymentModule payment;

  /// AI — the chat gateway across every configured provider.
  late final AIModule ai;

  /// Updates the project API key used on every request.
  void setApiKey(String apiKey) => config.setApiKey(apiKey);

  /// Stores the access token sent as `Authorization: Bearer <token>`.
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

  /// Releases every resource held by this instance and its modules.
  ///
  /// After this call the instance cannot issue further requests. This has no
  /// JavaScript counterpart — the JS SDK relies on garbage collection — but a
  /// Flutter app that leaks an HTTP connection pool or a broadcast
  /// `StreamController` will be flagged by the framework's own leak
  /// diagnostics, so teardown is explicit here.
  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      auth.dispose(),
      storage.dispose(),
      realtime.dispose(),
      media.dispose(),
    ]);
    client.dispose();
  }
}
