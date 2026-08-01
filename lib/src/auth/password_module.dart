/// Password recovery.
///
/// Dart port of `supersosdk/src/auth/password.ts`.
library;

import '../client/superso_http_client.dart';
import '../types/common.dart';
import 'auth_decoders.dart';
import 'auth_types.dart';

/// Implements the password-recovery endpoints documented under §6 Email
/// Authentication: forgot-password (§6.5) and reset-password (§6.6).
///
/// Exposed at `superso.auth.password`.
class PasswordModule {
  /// Creates a password module bound to [client].
  const PasswordModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /auth/email/forgot-password`
  ///
  /// Always returns `200` regardless of whether the email is registered, to
  /// prevent user-enumeration attacks. Treat a success response as "if that
  /// account exists, a code has been sent" — never as confirmation that the
  /// address is registered.
  Future<ApiResponse<void>> forgot(
    String email, {
    ForgotPasswordOptions? options,
  }) {
    return _client.post<void>(
      '/auth/email/forgot-password',
      body: <String, dynamic>{
        'email': email,
        if (options != null) 'options': options.toJson(),
      },
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/email/reset-password`
  ///
  /// Validates the reset OTP and sets the new password. Revokes all active
  /// sessions on success, so the user must sign in again afterwards.
  Future<ApiResponse<void>> reset({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _client.post<void>(
      '/auth/email/reset-password',
      body: <String, dynamic>{
        'email': email,
        'code': code,
        'new_password': newPassword,
      },
      decoder: decodeVoid,
    );
  }
}
