/// The contract every service module implements.
///
/// Dart port of `supersosdk/src/interfaces/index.ts`.
library;

import '../client/superso_http_client.dart';

/// Implemented by every service module (auth, database, storage, realtime,
/// media, notification, payment, ai).
///
/// A module only ever receives the shared [SupersoHttpClient] — never its own
/// config, headers, or URL builder — so there is exactly one code path for
/// HTTP, auth headers, and error handling across the whole SDK.
abstract interface class SdkModule {
  /// The shared HTTP client this module issues every request through.
  SupersoHttpClient get client;
}

/// Implemented by modules that hold resources needing explicit teardown —
/// WebSocket connections, timers, or stream controllers.
///
/// This has no TypeScript counterpart: JavaScript's garbage collector reclaims
/// an unreferenced socket eventually, but a Flutter `State` that leaks a live
/// `StreamController` triggers the framework's own leak diagnostics and keeps
/// the connection open. Modules that need it (realtime, media) implement this,
/// and [Superso.dispose] fans out to all of them.
abstract interface class Disposable {
  /// Releases every resource held by this object.
  ///
  /// Implementations must be safe to call more than once.
  Future<void> dispose();
}
