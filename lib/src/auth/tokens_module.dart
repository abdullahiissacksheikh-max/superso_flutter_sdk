/// Token accessors exposed at `superso.auth.tokens`.
///
/// Dart port of `supersosdk/src/auth/tokens.ts`.
library;

import '../client/superso_http_client.dart';

/// Exposes access/refresh token accessors.
///
/// Holds no state of its own — every call delegates straight to the shared
/// [SupersoHttpClient] (which in turn delegates to `SupersoConfig`), so there
/// is exactly one place tokens are ever stored, and the client automatically
/// attaches `Authorization: Bearer <token>` the moment [setAccessToken] has
/// been called.
class TokensModule {
  /// Creates a tokens module bound to [client].
  const TokensModule(this._client);

  final SupersoHttpClient _client;

  /// Stores the access token (JWT).
  void setAccessToken(String token) => _client.setAccessToken(token);

  /// Returns the currently stored access token, if any.
  String? getAccessToken() => _client.getAccessToken();

  /// Clears the stored access token.
  void clearAccessToken() => _client.clearAccessToken();

  /// Stores the refresh token.
  void setRefreshToken(String token) => _client.setRefreshToken(token);

  /// Returns the currently stored refresh token, if any.
  String? getRefreshToken() => _client.getRefreshToken();

  /// Clears the stored refresh token.
  void clearRefreshToken() => _client.clearRefreshToken();

  /// Whether an access token is currently held.
  ///
  /// Convenience for gating UI on sign-in state without exposing the token
  /// itself. No TypeScript equivalent; added because Flutter widgets commonly
  /// need exactly this boolean.
  bool get hasAccessToken {
    final token = _client.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Clears both tokens. Equivalent to a local sign-out with no server call.
  void clear() {
    _client.clearAccessToken();
    _client.clearRefreshToken();
  }
}
