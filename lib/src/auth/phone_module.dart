/// Phone authentication.
///
/// Dart port of `supersosdk/src/auth/phone.ts`.
library;

import '../client/superso_http_client.dart';
import '../types/common.dart';
import 'auth_decoders.dart';
import 'auth_types.dart';
import 'otp.dart';
import 'session_capture.dart';

/// Implements §9 Phone Authentication from `docs/auth.md` — a fully
/// passwordless flow: send an OTP by SMS, then submit it to verify or log in.
///
/// Exposed at `superso.auth.phone`.
class PhoneModule {
  /// Creates a phone module bound to [client].
  const PhoneModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /auth/phone/send-otp` — sends a 6-digit OTP via SMS.
  ///
  /// [purpose] namespaces the code. See [OtpPurpose].
  Future<ApiResponse<void>> sendOtp({
    required String phone,
    String? purpose,
  }) {
    return _client.post<void>(
      '/auth/phone/send-otp',
      body: <String, dynamic>{
        'phone': phone,
        if (purpose != null) 'purpose': purpose,
      },
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/phone/verify-otp` — validates an OTP for a phone number and
  /// purpose *without* logging the user in (phone-verification flows).
  Future<ApiResponse<void>> verifyOtp({
    required String phone,
    required String code,
    String? purpose,
  }) {
    return _client.post<void>(
      '/auth/phone/verify-otp',
      body: <String, dynamic>{
        'phone': phone,
        'code': code,
        if (purpose != null) 'purpose': purpose,
      },
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/phone/login` — authenticates with phone plus OTP.
  ///
  /// If no account exists for the phone number, one is created automatically
  /// (passwordless auto-registration). Tokens are captured automatically.
  Future<ApiResponse<AuthSession>> login({
    required String phone,
    required String code,
    PhoneLoginOptions? options,
  }) {
    return withSessionCapture(
      _client,
      _client.post<AuthSession>(
        '/auth/phone/login',
        body: <String, dynamic>{
          'phone': phone,
          'code': code,
          if (options != null) 'options': options.toJson(),
        },
        decoder: decodeAuthSession,
      ),
      sessionTokens,
    );
  }

  /// `POST /auth/phone/change` — initiates a phone number change.
  ///
  /// Sends an OTP to the new number. Requires an active access token.
  Future<ApiResponse<void>> change({
    required String newPhone,
    String? password,
  }) {
    return _client.post<void>(
      '/auth/phone/change',
      body: <String, dynamic>{
        'new_phone': newPhone,
        if (password != null) 'password': password,
      },
      decoder: decodeVoid,
    );
  }

  /// `POST /auth/phone/confirm-change` — completes the phone number change by
  /// validating the OTP sent to the new number.
  Future<ApiResponse<void>> confirmChange({
    required String newPhone,
    required String code,
  }) {
    return _client.post<void>(
      '/auth/phone/confirm-change',
      body: <String, dynamic>{'new_phone': newPhone, 'code': code},
      decoder: decodeVoid,
    );
  }
}
