/// Automatic session capture.
///
/// Dart port of `supersosdk/src/auth/capture.ts` (introduced in JS SDK v0.2.8).
///
/// ROOT CAUSE this fixes: every authentication entry point (`auth.login()`,
/// `auth.register()`, `auth.email.*`, `auth.phone.*`, `auth.refresh()`)
/// returns an [AuthSession] containing the access and refresh tokens — but
/// historically never STORED it. The application was expected to notice and
/// call `auth.tokens.setAccessToken(...)` itself. Any app that did not left
/// the shared HTTP client with no token, which meant:
///
///   - REST calls silently went out without `Authorization: Bearer …`, and
///   - the Media WebSocket carried no identity, so the backend correctly
///     recorded the participant as a Guest.
///
/// The user was authenticated; the SDK simply never told itself. Tokens are
/// therefore captured automatically at the single point every auth response
/// flows through.
///
/// This is additive and non-breaking: the response is returned unchanged, so
/// code that manually calls `setAccessToken()` keeps working — it simply sets
/// a value that is already there.
library;

import '../client/superso_http_client.dart';
import '../types/common.dart';

/// Stores any tokens present on [response] into [client], then returns the
/// response untouched.
///
/// Only non-empty tokens are stored, so a partial response (for example an OTP
/// step that returns no refresh token) never clears a token already held.
ApiResponse<T> captureSession<T>(
  SupersoHttpClient client,
  ApiResponse<T> response,
  String? accessToken,
  String? refreshToken,
) {
  if (accessToken != null && accessToken.isNotEmpty) {
    client.setAccessToken(accessToken);
  }
  if (refreshToken != null && refreshToken.isNotEmpty) {
    client.setRefreshToken(refreshToken);
  }
  return response;
}

/// Future-aware wrapper used by every token-returning auth call.
///
/// [extractTokens] pulls the `(access, refresh)` pair out of the decoded
/// payload; returning `(null, null)` skips capture entirely.
Future<ApiResponse<T>> withSessionCapture<T>(
  SupersoHttpClient client,
  Future<ApiResponse<T>> future,
  (String?, String?) Function(T data) extractTokens,
) async {
  final response = await future;
  final (access, refresh) = extractTokens(response.data);
  return captureSession(client, response, access, refresh);
}
