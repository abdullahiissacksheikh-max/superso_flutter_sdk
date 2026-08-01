/// Shared OTP concerns reused by both the email and phone submodules, so
/// purpose namespacing is defined once instead of duplicated per channel.
///
/// Dart port of `supersosdk/src/auth/otp.ts`.
library;

/// Namespaces an OTP so a code issued for one flow cannot be replayed against
/// another (`docs/auth.md` §6.9, §9.1).
///
/// The API accepts any string for `purpose`; this class lists only the values
/// the documentation names explicitly. Any other string remains valid.
abstract final class OtpPurpose {
  /// Passwordless login by phone number.
  static const String phoneLogin = 'phone_login';

  /// Verifying ownership of a phone number.
  static const String verifyPhone = 'verify_phone';

  /// Verifying ownership of an email address.
  static const String verifyEmail = 'verify_email';

  /// Every purpose the documentation names explicitly.
  static const List<String> values = <String>[
    phoneLogin,
    verifyPhone,
    verifyEmail,
  ];
}
