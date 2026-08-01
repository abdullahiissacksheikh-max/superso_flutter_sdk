/// Request and response models for the Auth module, mirrored exactly from
/// `docs/auth.md`.
///
/// Field optionality reflects what each documented endpoint actually returns —
/// different endpoints return different subsets of the user object, so only
/// `id` and `provider` are guaranteed on [AuthUser].
///
/// Dart port of `supersosdk/src/auth/types.ts`. Where TypeScript uses plain
/// structural interfaces, Dart uses immutable classes with explicit
/// `fromJson`/`toJson`, because Dart has no structural typing.
library;

import 'package:meta/meta.dart';

/// Identity provider that authenticated a user.
///
/// The backend accepts additional provider strings, so [AuthUser.provider] is
/// kept as a `String`; this class holds the values the docs name explicitly.
abstract final class AuthProvider {
  /// Email + password authentication.
  static const String email = 'email';

  /// Passwordless phone + OTP authentication.
  static const String phone = 'phone';

  /// Google OAuth.
  static const String google = 'google';

  /// Facebook OAuth.
  static const String facebook = 'facebook';
}

/// A user account as returned by the Auth endpoints.
@immutable
class AuthUser {
  /// Creates a user.
  const AuthUser({
    required this.id,
    required this.provider,
    this.publicId,
    this.projectId,
    this.email,
    this.phone,
    this.fullName,
    this.username,
    this.avatarUrl,
    this.country,
    this.timezone,
    this.verified,
    this.phoneVerified,
    this.disabled,
    this.lastLoginAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a user from JSON.
  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        publicId: json['public_id'] as String?,
        projectId: json['project_id'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        fullName: json['full_name'] as String?,
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        country: json['country'] as String?,
        timezone: json['timezone'] as String?,
        verified: json['verified'] as bool?,
        phoneVerified: json['phone_verified'] as bool?,
        disabled: json['disabled'] as bool?,
        lastLoginAt: json['last_login_at'] as String?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// The user's unique identifier.
  final String id;

  /// Which provider authenticated this user. See [AuthProvider].
  final String provider;

  /// Public-facing identifier, safe to expose in URLs.
  final String? publicId;

  /// The project this user belongs to.
  final String? projectId;

  /// Email address, if the account has one.
  final String? email;

  /// Phone number in E.164 format, if the account has one.
  final String? phone;

  /// The user's display name.
  final String? fullName;

  /// Unique username, if set.
  final String? username;

  /// URL of the user's avatar image.
  final String? avatarUrl;

  /// ISO country code.
  final String? country;

  /// IANA timezone identifier, e.g. `Africa/Mogadishu`.
  final String? timezone;

  /// Whether the email address has been verified.
  final bool? verified;

  /// Whether the phone number has been verified.
  final bool? phoneVerified;

  /// Whether the account is disabled and cannot log in.
  final bool? disabled;

  /// ISO-8601 timestamp of the most recent login.
  final String? lastLoginAt;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// Encodes this user back to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'provider': provider,
        if (publicId != null) 'public_id': publicId,
        if (projectId != null) 'project_id': projectId,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (fullName != null) 'full_name': fullName,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (country != null) 'country': country,
        if (timezone != null) 'timezone': timezone,
        if (verified != null) 'verified': verified,
        if (phoneVerified != null) 'phone_verified': phoneVerified,
        if (disabled != null) 'disabled': disabled,
        if (lastLoginAt != null) 'last_login_at': lastLoginAt,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthUser && other.id == id && other.provider == provider);

  @override
  int get hashCode => Object.hash(id, provider);

  @override
  String toString() => 'AuthUser(id: $id, provider: $provider, email: $email)';
}

/// Access/refresh token pair issued by SuperAuth.
@immutable
class AuthTokens {
  /// Creates a token pair.
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  /// Decodes a token pair from JSON.
  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String? ?? '',
        refreshToken: json['refresh_token'] as String? ?? '',
        tokenType: json['token_type'] as String? ?? 'Bearer',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      );

  /// Short-lived JWT sent as `Authorization: Bearer <token>`.
  final String accessToken;

  /// Long-lived token used to obtain a new [accessToken].
  final String refreshToken;

  /// Token scheme, always `Bearer` in practice.
  final String tokenType;

  /// Lifetime of [accessToken], in seconds.
  final int expiresIn;

  /// The instant [accessToken] expires, computed from [expiresIn].
  ///
  /// This has no TypeScript equivalent — the JS SDK exposes only the raw
  /// `expires_in`. Dart's `DateTime` makes proactive refresh scheduling
  /// straightforward, so the derived value is offered directly.
  DateTime expiresAtFrom(DateTime issuedAt) =>
      issuedAt.add(Duration(seconds: expiresIn));

  @override
  String toString() =>
      'AuthTokens(tokenType: $tokenType, expiresIn: ${expiresIn}s)';
}

/// The payload of register/login/phone-login — a user plus a token pair.
@immutable
class AuthSession {
  /// Creates a session.
  const AuthSession({required this.user, required this.tokens});

  /// Decodes a session from JSON.
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: AuthUser.fromJson(
          json['user'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
        tokens: AuthTokens.fromJson(json),
      );

  /// The authenticated user.
  final AuthUser user;

  /// The issued token pair.
  final AuthTokens tokens;

  /// Convenience accessor for the access token.
  String get accessToken => tokens.accessToken;

  /// Convenience accessor for the refresh token.
  String get refreshToken => tokens.refreshToken;

  @override
  String toString() => 'AuthSession(user: ${user.id})';
}

/// The payload returned by `PATCH /auth/profile`.
@immutable
class AuthProfile {
  /// Creates a profile.
  const AuthProfile({
    required this.id,
    this.fullName,
    this.username,
    this.avatarUrl,
    this.country,
    this.timezone,
    this.updatedAt,
  });

  /// Decodes a profile from JSON.
  factory AuthProfile.fromJson(Map<String, dynamic> json) => AuthProfile(
        id: json['id'] as String? ?? '',
        fullName: json['full_name'] as String?,
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        country: json['country'] as String?,
        timezone: json['timezone'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// The user's identifier.
  final String id;

  /// The user's display name.
  final String? fullName;

  /// Unique username.
  final String? username;

  /// URL of the user's avatar image.
  final String? avatarUrl;

  /// ISO country code.
  final String? country;

  /// IANA timezone identifier.
  final String? timezone;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  @override
  String toString() => 'AuthProfile(id: $id, fullName: $fullName)';
}

/// The payload returned by `POST /users/disable` and `POST /users/enable`.
@immutable
class DisabledUserResult {
  /// Creates a disable/enable result.
  const DisabledUserResult({required this.id, required this.disabled});

  /// Decodes the result from JSON.
  factory DisabledUserResult.fromJson(Map<String, dynamic> json) =>
      DisabledUserResult(
        id: json['id'] as String? ?? '',
        disabled: json['disabled'] as bool? ?? false,
      );

  /// The affected user's identifier.
  final String id;

  /// The account's resulting disabled state.
  final bool disabled;

  @override
  String toString() => 'DisabledUserResult(id: $id, disabled: $disabled)';
}

/// The payload returned by `GET /users`.
@immutable
class UserListResult {
  /// Creates a user list result.
  const UserListResult({
    required this.users,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  /// Decodes a user list from JSON.
  factory UserListResult.fromJson(Map<String, dynamic> json) => UserListResult(
        users: (json['users'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(AuthUser.fromJson)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
        totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      );

  /// The users on this page.
  final List<AuthUser> users;

  /// Total users matching the query across all pages.
  final int total;

  /// Current page number.
  final int page;

  /// Page size.
  final int limit;

  /// Total number of pages.
  final int totalPages;

  @override
  String toString() =>
      'UserListResult(users: ${users.length}, total: $total, page: $page)';
}

// ── Request bodies ───────────────────────────────────────────────────────

/// Notification side effects requested alongside registration.
@immutable
class RegisterOptions {
  /// Creates registration options.
  const RegisterOptions({
    this.sendWelcomeEmail,
    this.sendVerificationEmail,
    this.sendWelcomeSms,
  });

  /// Send a welcome email after the account is created.
  final bool? sendWelcomeEmail;

  /// Send an email-verification message after the account is created.
  final bool? sendVerificationEmail;

  /// Send a welcome SMS after the account is created.
  final bool? sendWelcomeSms;

  /// Encodes these options to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (sendWelcomeEmail != null) 'sendWelcomeEmail': sendWelcomeEmail,
        if (sendVerificationEmail != null)
          'sendVerificationEmail': sendVerificationEmail,
        if (sendWelcomeSms != null) 'sendWelcomeSMS': sendWelcomeSms,
      };
}

/// Notification side effects requested alongside login.
@immutable
class LoginOptions {
  /// Creates login options.
  const LoginOptions({this.sendLoginAlertEmail, this.sendLoginAlertSms});

  /// Send a "new login" alert email.
  final bool? sendLoginAlertEmail;

  /// Send a "new login" alert SMS.
  final bool? sendLoginAlertSms;

  /// Encodes these options to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (sendLoginAlertEmail != null)
          'sendLoginAlertEmail': sendLoginAlertEmail,
        if (sendLoginAlertSms != null) 'sendLoginAlertSMS': sendLoginAlertSms,
      };
}

/// Notification side effects requested alongside a password-reset request.
@immutable
class ForgotPasswordOptions {
  /// Creates forgot-password options.
  const ForgotPasswordOptions({
    this.sendPasswordResetEmail,
    this.sendPasswordResetSms,
  });

  /// Deliver the reset code by email.
  final bool? sendPasswordResetEmail;

  /// Deliver the reset code by SMS.
  final bool? sendPasswordResetSms;

  /// Encodes these options to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (sendPasswordResetEmail != null)
          'sendPasswordResetEmail': sendPasswordResetEmail,
        if (sendPasswordResetSms != null)
          'sendPasswordResetSMS': sendPasswordResetSms,
      };
}

/// Notification side effects requested alongside a phone login.
@immutable
class PhoneLoginOptions {
  /// Creates phone-login options.
  const PhoneLoginOptions({this.sendLoginAlertSms});

  /// Send a "new login" alert SMS.
  final bool? sendLoginAlertSms;

  /// Encodes these options to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (sendLoginAlertSms != null) 'sendLoginAlertSMS': sendLoginAlertSms,
      };
}

/// Fields updatable via `PATCH /auth/profile` and `PATCH /users/:id`.
@immutable
class UpdateProfileRequest {
  /// Creates a profile update request.
  const UpdateProfileRequest({
    this.fullName,
    this.username,
    this.avatarUrl,
    this.country,
    this.timezone,
  });

  /// New display name.
  final String? fullName;

  /// New username.
  final String? username;

  /// New avatar URL.
  final String? avatarUrl;

  /// New ISO country code.
  final String? country;

  /// New IANA timezone identifier.
  final String? timezone;

  /// Encodes this request to the platform's JSON shape.
  ///
  /// Only non-null fields are included, so omitted fields remain unchanged
  /// server-side — matching the documented `PATCH` semantics.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (fullName != null) 'full_name': fullName,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (country != null) 'country': country,
        if (timezone != null) 'timezone': timezone,
      };
}

/// Query parameters accepted by `GET /users`.
@immutable
class ListUsersQuery {
  /// Creates a user-list query.
  const ListUsersQuery({
    this.page,
    this.limit,
    this.search,
    this.provider,
    this.status,
  });

  /// 1-based page number.
  final int? page;

  /// Page size.
  final int? limit;

  /// Free-text search across name, email, and phone.
  final String? search;

  /// Filter by identity provider. See [AuthProvider].
  final String? provider;

  /// Filter by account status: `active`, `disabled`, or `unverified`.
  final String? status;

  /// Encodes this query to URL parameters.
  Map<String, Object?> toQuery() => <String, Object?>{
        'page': page,
        'limit': limit,
        'search': search,
        'provider': provider,
        'status': status,
      };
}
