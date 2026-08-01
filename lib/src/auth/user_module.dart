/// Admin-level user management.
///
/// Dart port of `supersosdk/src/auth/user.ts`.
library;

import '../client/superso_http_client.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'auth_decoders.dart';
import 'auth_types.dart';

/// Implements §10 User APIs from `docs/auth.md` — admin-level endpoints for
/// managing users within a project.
///
/// These are typically called from a backend using a `read`/`write`/`delete`
/// API key; end users should never call them directly from a mobile client,
/// because doing so requires shipping a privileged key inside the app binary.
///
/// Exposed at `superso.auth.users`.
class UserModule {
  /// Creates a user module bound to [client].
  const UserModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /users` — paginated, filterable list of users in the project.
  Future<ApiResponse<UserListResult>> list([ListUsersQuery? query]) {
    return _client.get<UserListResult>(
      '/users',
      options: query == null ? null : RequestOptions(query: query.toQuery()),
      decoder: decodeUserList,
    );
  }

  /// `GET /users/:id`
  Future<ApiResponse<AuthUser>> get(String id) {
    return _client.get<AuthUser>(
      '/users/${encodeSegment(id)}',
      decoder: decodeAuthUser,
    );
  }

  /// `PATCH /users/:id`
  Future<ApiResponse<AuthUser>> update(
    String id,
    UpdateProfileRequest request,
  ) {
    return _client.patch<AuthUser>(
      '/users/${encodeSegment(id)}',
      body: request.toJson(),
      decoder: decodeAuthUser,
    );
  }

  /// `DELETE /users/:id` — soft-deletes the user and revokes all sessions.
  Future<ApiResponse<void>> delete(String id) {
    return _client.delete<void>(
      '/users/${encodeSegment(id)}',
      decoder: decodeVoid,
    );
  }

  /// `POST /users/disable` — prevents login without deleting the account.
  Future<ApiResponse<DisabledUserResult>> disable(String userId) {
    return _client.post<DisabledUserResult>(
      '/users/disable',
      body: <String, dynamic>{'user_id': userId},
      decoder: decodeDisabledUser,
    );
  }

  /// `POST /users/enable` — re-enables a previously disabled account.
  Future<ApiResponse<DisabledUserResult>> enable(String userId) {
    return _client.post<DisabledUserResult>(
      '/users/enable',
      body: <String, dynamic>{'user_id': userId},
      decoder: decodeDisabledUser,
    );
  }
}
