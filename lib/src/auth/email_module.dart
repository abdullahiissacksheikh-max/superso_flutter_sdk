/// Email authentication.
///
/// Dart port of `supersosdk/src/auth/email.ts`.
library;

import '../client/superso_http_client.dart';
import '../types/common.dart';
import 'auth_decoders.dart';
import 'auth_types.dart';
import 'otp.dart';
import 'session_capture.dart';

/// Implements §6 Email Authentication from `docs/auth.md`.
///
/// Exposed at `superso.auth.email`. [register] and [login] are identical to
/// the top-level `superso.auth.register()` / `login()` — both URLs are
/// documented and kept so callers can use whichever reads more clearly in
/// their codebase.
class EmailModule {
  /// Creates an email module bound to [client].
  const EmailModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /auth/email/register`
  Future<ApiResponse<AuthSession>> register({
    required String email,
    required String password,
    String? name,
    RegisterOptions? options,
  }) {
    return withSessionCapture(
      _client,
      _client.post<AuthSession>(
        '/auth/email/register',
        body: <String, dynamic>{
          'email': email,
          'password': password,
          if (name != null) 'name': name,
          if (options != null) 'options': options.toJson(),
        },
        decoder: decodeAuthSession,
      ),
      sessionTokens,
    );
  }

  /// `POST /auth/email/login`
  Future<ApiResponse<AuthSession>> login({
    required String email,
    required String password,
    LoginOptions? options,
  }) {
    return withSessionCapture(
      _client,
      _client.post<AuthSession>(
        '/auth/email/login',
        body: <String, dynamic>{
          'email': email,
          'password': password,
          if (options != null) 'options': options.toJson(),
        },
        decoder: decodeAuthSession,
      ),
      sessionTokens,
    );
  }

  /// `POST /auth/email/send-verification`
  Future<ApiResponse<void>> sendVerification(String email) {
    return _client.post<void>(
      '/auth/email/send-verification',
      body: <String, dynamic>{'email': email},
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/email/verify`
  Future<ApiResponse<void>> verify({
    required String email,
    required String code,
  }) {
    return _client.post<void>(
      '/auth/email/verify',
      body: <String, dynamic>{'email': email, 'code': code},
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/email/change` — initiates an email address change.
  ///
  /// Sends a verification OTP to the new address. Requires an active access
  /// token.
  Future<ApiResponse<void>> change({
    required String newEmail,
    required String password,
  }) {
    return _client.post<void>(
      '/auth/email/change',
      body: <String, dynamic>{'new_email': newEmail, 'password': password},
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/email/confirm-change` — completes the email address change
  /// by validating the OTP sent to the new address.
  Future<ApiResponse<void>> confirmChange({
    required String newEmail,
    required String code,
  }) {
    return _client.post<void>(
      '/auth/email/confirm-change',
      body: <String, dynamic>{'new_email': newEmail, 'code': code},
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/email/send-otp` — generic OTP for custom flows (e.g. MFA).
  ///
  /// [purpose] namespaces the code so it cannot be replayed against another
  /// flow. See [OtpPurpose].
  Future<ApiResponse<void>> sendOtp({
    required String email,
    String? purpose,
  }) {
    return _client.post<void>(
      '/auth/email/send-otp',
      body: <String, dynamic>{
        'email': email,
        if (purpose != null) 'purpose': purpose,
      },
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/email/verify-otp` — validates a generic OTP for a purpose.
  Future<ApiResponse<void>> verifyOtp({
    required String email,
    required String code,
    String? purpose,
  }) {
    return _client.post<void>(
      '/auth/email/verify-otp',
      body: <String, dynamic>{
        'email': email,
        'code': code,
        if (purpose != null) 'purpose': purpose,
      },
      decoder: decodeVoid,
    );
  }
}
