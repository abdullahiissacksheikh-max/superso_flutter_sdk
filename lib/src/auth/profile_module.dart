/// Profile updates.
///
/// Dart port of `supersosdk/src/auth/profile.ts`.
library;

import '../client/superso_http_client.dart';
import '../types/common.dart';
import 'auth_decoders.dart';
import 'auth_types.dart';

/// Implements §5.6 Update Profile from `docs/auth.md`.
///
/// `PATCH /auth/profile` — only fields present in the request body are
/// updated; omitted fields remain unchanged. [UpdateProfileRequest.toJson]
/// enforces this by serializing only non-null fields.
class ProfileModule {
  /// Creates a profile module bound to [client].
  const ProfileModule(this._client);

  final SupersoHttpClient _client;

  /// `PATCH /auth/profile` — updates the current user's profile.
  ///
  /// Requires an active access token.
  Future<ApiResponse<AuthProfile>> update(UpdateProfileRequest request) {
    return _client.patch<AuthProfile>(
      '/auth/profile',
      body: request.toJson(),
      decoder: decodeAuthProfile,
    );
  }
}
