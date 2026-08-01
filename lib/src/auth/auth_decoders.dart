/// Internal JSON decoders shared by the Auth submodules.
///
/// This file is deliberately NOT exported from the package barrel — it is an
/// implementation detail. Each decoder converts the raw `data` value of an API
/// envelope into a typed model.
///
/// These exist because Dart, unlike TypeScript, cannot treat an arbitrary
/// decoded `Map` as a typed interface: every model needs an explicit
/// conversion step. Centralising them here keeps that step out of the module
/// classes and guarantees every endpoint returning the same shape decodes it
/// identically.
library;

import 'auth_types.dart';

/// Decodes an [AuthSession] payload.
AuthSession decodeAuthSession(Object? data) => AuthSession.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Decodes an [AuthTokens] payload.
AuthTokens decodeAuthTokens(Object? data) => AuthTokens.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Decodes an [AuthUser] payload.
AuthUser decodeAuthUser(Object? data) => AuthUser.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Decodes an [AuthProfile] payload.
AuthProfile decodeAuthProfile(Object? data) => AuthProfile.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Decodes a [DisabledUserResult] payload.
DisabledUserResult decodeDisabledUser(Object? data) =>
    DisabledUserResult.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Decodes a [UserListResult] payload.
UserListResult decodeUserList(Object? data) => UserListResult.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Discards a payload for endpoints documented as returning `data: null`.
///
/// Every OTP send/verify endpoint, and every acknowledgement-only endpoint,
/// uses this.
void decodeVoid(Object? data) {}

/// Extracts the `(access, refresh)` token pair from a session, for
/// automatic session capture.
(String?, String?) sessionTokens(AuthSession session) =>
    (session.accessToken, session.refreshToken);

/// Extracts the `(access, refresh)` token pair from a bare token response.
(String?, String?) tokenPairTokens(AuthTokens tokens) =>
    (tokens.accessToken, tokens.refreshToken);
