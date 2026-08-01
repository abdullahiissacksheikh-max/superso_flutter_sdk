/// Core session authentication.
///
/// Dart port of `supersosdk/src/auth/session.ts`.
library;

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../types/common.dart';
import 'auth_decoders.dart';
import 'auth_types.dart';
import 'session_capture.dart';

/// Implements §5 Core Authentication from `docs/auth.md`: register, login,
/// logout, refresh, current user, and delete account.
///
/// Every request is issued through the shared [SupersoHttpClient] — no local
/// headers, URL building, or `Authorization` logic.
class SessionModule {
  /// Creates a session module bound to [client].
  const SessionModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /auth/register` — creates an account and returns a session.
  ///
  /// The returned tokens are captured automatically; you do not need to call
  /// `tokens.setAccessToken()` yourself.
  Future<ApiResponse<AuthSession>> register({
    required String email,
    required String password,
    String? name,
    RegisterOptions? options,
    RequestOptions? requestOptions,
  }) {
    return withSessionCapture(
      _client,
      _client.post<AuthSession>(
        '/auth/register',
        body: <String, dynamic>{
          'email': email,
          'password': password,
          if (name != null) 'name': name,
          if (options != null) 'options': options.toJson(),
        },
        options: requestOptions,
        decoder: decodeAuthSession,
      ),
      sessionTokens,
    );
  }

  /// `POST /auth/login` — authenticates with email and password.
  Future<ApiResponse<AuthSession>> login({
    required String email,
    required String password,
    LoginOptions? options,
    RequestOptions? requestOptions,
  }) {
    return withSessionCapture(
      _client,
      _client.post<AuthSession>(
        '/auth/login',
        body: <String, dynamic>{
          'email': email,
          'password': password,
          if (options != null) 'options': options.toJson(),
        },
        options: requestOptions,
        decoder: decodeAuthSession,
      ),
      sessionTokens,
    );
  }

  /// `POST /auth/logout` — revokes the given refresh-token session.
  ///
  /// Falls back to the token stored via `tokens.setRefreshToken()` when
  /// [refreshToken] is omitted. Throws a [ValidationError] if neither is
  /// available.
  ///
  /// The stored session is cleared once the server accepts the logout — the
  /// mirror image of the automatic capture on login. Without this, a
  /// logged-out client keeps sending a stale `Authorization` header and keeps
  /// attaching the dead token to Media WebSocket connections, so a signed-out
  /// user could still be recorded under their old identity. Tokens are cleared
  /// only on success, so a failed logout leaves the session intact and
  /// retryable.
  Future<ApiResponse<void>> logout([String? refreshToken]) async {
    final token = refreshToken ?? _client.getRefreshToken();
    if (token == null || token.isEmpty) {
      throw const ValidationError(
        'logout() requires a refresh token — pass one explicitly or call '
        'auth.tokens.setRefreshToken() first.',
      );
    }
    final response = await _client.post<void>(
      '/auth/logout',
      body: <String, dynamic>{'refresh_token': token},
      decoder: decodeVoid,
    );
    _client.clearAccessToken();
    _client.clearRefreshToken();
    return response;
  }

  /// `POST /auth/refresh` — issues a new access token and rotates the refresh
  /// token.
  ///
  /// Falls back to the stored refresh token when [refreshToken] is omitted.
  Future<ApiResponse<AuthTokens>> refresh([String? refreshToken]) {
    final token = refreshToken ?? _client.getRefreshToken();
    if (token == null || token.isEmpty) {
      throw const ValidationError(
        'refresh() requires a refresh token — pass one explicitly or call '
        'auth.tokens.setRefreshToken() first.',
      );
    }
    return withSessionCapture(
      _client,
      _client.post<AuthTokens>(
        '/auth/refresh',
        body: <String, dynamic>{'refresh_token': token},
        decoder: decodeAuthTokens,
      ),
      tokenPairTokens,
    );
  }

  /// `GET /auth/me` — the currently authenticated user.
  ///
  /// Requires an active access token.
  Future<ApiResponse<AuthUser>> me({RequestOptions? requestOptions}) {
    return _client.get<AuthUser>(
      '/auth/me',
      options: requestOptions,
      decoder: decodeAuthUser,
    );
  }

  /// `DELETE /auth/account` — irreversibly deletes the current account.
  ///
  /// Requires an active access token.
  Future<ApiResponse<void>> deleteAccount() {
    return _client.delete<void>('/auth/account', decoder: decodeVoid);
  }
}
