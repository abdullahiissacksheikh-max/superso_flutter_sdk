/// Barrel export for the Auth module.
///
/// [AuthModule] is the only thing the rest of the SDK needs to import — the
/// submodule classes and models are re-exported so advanced consumers can
/// reference them directly (for typing a variable, or unit-testing a submodule
/// in isolation).
///
/// `auth_decoders.dart` is deliberately NOT exported: it is an internal
/// implementation detail.
library;

export 'auth_module.dart';
export 'auth_types.dart';
export 'email_module.dart';
export 'oauth_module.dart';
export 'otp.dart';
export 'password_module.dart';
export 'phone_module.dart';
export 'profile_module.dart';
export 'session_module.dart';
export 'tokens_module.dart';
export 'user_module.dart';
