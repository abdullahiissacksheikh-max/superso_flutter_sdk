/// The Media error contract (canonical contract §8).
///
/// Every failed Media response carries `{"success": false, "error": {"code",
/// "message"}}` where `code` is one of [MediaErrorCodes]. The SDK surfaces
/// that code verbatim as [MediaError.code] — switch on the code, never on the
/// message. `MEDIA_NOT_HOST` and `MEDIA_INSUFFICIENT_RANK` are raised as the
/// more specific [HostAuthorizationError].
///
/// Source of truth: `backend/internal/modules/media/errors/errors.go`.
library;

import '../errors/superso_error.dart';

/// Every machine-readable Media error code the backend can return.
abstract final class MediaErrorCodes {
  /// 400 — malformed request.
  static const String invalidRequest = 'MEDIA_INVALID_REQUEST';

  /// 422 — semantically invalid request.
  static const String validationFailed = 'MEDIA_VALIDATION_FAILED';

  /// 401 — missing/invalid credentials (e.g. a bad participant token).
  static const String unauthorized = 'MEDIA_UNAUTHORIZED';

  /// 403 — forbidden by server media policy.
  static const String forbidden = 'MEDIA_FORBIDDEN';

  /// 403 — dashboard admin does not own the project.
  static const String projectAccessDenied = 'MEDIA_PROJECT_ACCESS_DENIED';

  /// 403 — the caller is not a privileged participant of the session.
  static const String notHost = 'MEDIA_NOT_HOST';

  /// 403 — the caller does not strictly outrank the target.
  static const String insufficientRank = 'MEDIA_INSUFFICIENT_RANK';

  /// 403 — the caller could not prove it is the target participant.
  static const String participantMismatch = 'MEDIA_PARTICIPANT_MISMATCH';

  /// 403 — Media is disabled for the project.
  static const String disabled = 'MEDIA_DISABLED';

  /// 403 — SDK host moderation is disabled in the project settings.
  static const String moderationDisabled = 'MEDIA_MODERATION_DISABLED';

  /// 403 — guests may not join this session.
  static const String guestsNotAllowed = 'MEDIA_GUESTS_NOT_ALLOWED';

  /// 403 — the room is locked.
  static const String roomLocked = 'MEDIA_ROOM_LOCKED';

  /// 403 — the participant was kicked.
  static const String kicked = 'MEDIA_KICKED';

  /// 403 — the participant was banned.
  static const String banned = 'MEDIA_BANNED';

  /// 403 — the participant may not publish.
  static const String publishNotAllowed = 'MEDIA_PUBLISH_NOT_ALLOWED';

  /// 403 — the session has a waiting room; call `join` first.
  static const String waitingRoomRequired = 'MEDIA_WAITING_ROOM_REQUIRED';

  /// 403 — the participant has not been admitted yet.
  static const String notAdmitted = 'MEDIA_NOT_ADMITTED';

  /// 403 — wrong session password.
  static const String invalidPassword = 'MEDIA_INVALID_PASSWORD';

  /// 409 — the participant is assigned to a breakout room.
  static const String inBreakout = 'MEDIA_IN_BREAKOUT';

  /// 404 — no such session in this project.
  static const String sessionNotFound = 'MEDIA_SESSION_NOT_FOUND';

  /// 404 — no such participant in this session.
  static const String participantNotFound = 'MEDIA_PARTICIPANT_NOT_FOUND';

  /// 404 — no such breakout room in this session.
  static const String breakoutNotFound = 'MEDIA_BREAKOUT_NOT_FOUND';

  /// 404 — no such waiting-room entry in this session.
  static const String waitingEntryNotFound = 'MEDIA_WAITING_ENTRY_NOT_FOUND';

  /// 404 — no such speaker-queue entry in this session.
  static const String speakerEntryNotFound = 'MEDIA_SPEAKER_ENTRY_NOT_FOUND';

  /// 404 — no such permission request.
  static const String requestNotFound = 'MEDIA_REQUEST_NOT_FOUND';

  /// 404 — generic not found.
  static const String notFound = 'MEDIA_NOT_FOUND';

  /// 409 — the session has ended.
  static const String sessionEnded = 'MEDIA_SESSION_ENDED';

  /// 409 — the operation is invalid in the current state.
  static const String invalidState = 'MEDIA_INVALID_STATE';

  /// 409 — conflicting state.
  static const String conflict = 'MEDIA_CONFLICT';

  /// 409 — the session is full.
  static const String sessionFull = 'MEDIA_SESSION_FULL';

  /// 409 — the project's concurrent live-session limit was reached.
  static const String sessionLimitReached = 'MEDIA_SESSION_LIMIT_REACHED';

  /// 500 — internal error (no detail is ever exposed).
  static const String internal = 'MEDIA_INTERNAL';

  /// Every code above.
  static const Set<String> all = <String>{
    invalidRequest,
    validationFailed,
    unauthorized,
    forbidden,
    projectAccessDenied,
    notHost,
    insufficientRank,
    participantMismatch,
    disabled,
    moderationDisabled,
    guestsNotAllowed,
    roomLocked,
    kicked,
    banned,
    publishNotAllowed,
    waitingRoomRequired,
    notAdmitted,
    invalidPassword,
    inBreakout,
    sessionNotFound,
    participantNotFound,
    breakoutNotFound,
    waitingEntryNotFound,
    speakerEntryNotFound,
    requestNotFound,
    notFound,
    sessionEnded,
    invalidState,
    conflict,
    sessionFull,
    sessionLimitReached,
    internal,
  };
}

/// Base class for every Media-domain error.
///
/// [code] is the backend's `MEDIA_*` code whenever the server sent one.
class MediaError extends SupersoError {
  /// Creates a media error.
  const MediaError(
    String message, {
    int? status,
    String? code,
    Object? details,
  }) : super(message: message, status: status, code: code, details: details);
}

/// The caller lacks host standing for this action: `MEDIA_NOT_HOST` (not a
/// privileged participant of the session) or `MEDIA_INSUFFICIENT_RANK` (does
/// not strictly outrank the target).
///
/// Host routes (`U, H` in the contract) require an end-user access token
/// whose user is a privileged participant of *this* session — an API key
/// alone is never enough. Sign in with `auth.login()` first; the shared
/// client attaches the token automatically.
class HostAuthorizationError extends MediaError {
  /// Creates a host-authorization error.
  const HostAuthorizationError(
    String message, {
    String code = MediaErrorCodes.notHost,
    Object? details,
  }) : super(message, status: 403, code: code, details: details);
}

/// Extracts the backend's machine-readable `code` from an error payload.
///
/// The shared client hands the `error` object (`{code, message}`) through as
/// `details`; a nested `{error: {code}}` shape is accepted too.
String? mediaErrorCode(Object? details) {
  if (details is! Map<String, dynamic>) return null;
  final direct = details['code'];
  if (direct is String && direct.isNotEmpty) return direct;
  final nested = details['error'];
  if (nested is Map<String, dynamic>) {
    final code = nested['code'];
    if (code is String && code.isNotEmpty) return code;
  }
  return null;
}

/// Runs a Media call, normalizing failures:
///
///  - `MEDIA_NOT_HOST` / `MEDIA_INSUFFICIENT_RANK` → [HostAuthorizationError];
///  - any other `MEDIA_*` code → [MediaError] carrying that code and status;
///  - transport failures ([NetworkError], [CancelledError]) and non-Media
///    [AuthenticationError]/[RateLimitError] (e.g. API-key middleware) are
///    rethrown unchanged;
///  - anything else becomes a [MediaError] keeping the original code.
Future<T> withMediaErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on NetworkError {
    rethrow;
  } on CancelledError {
    rethrow;
  } on SupersoError catch (error) {
    final code = mediaErrorCode(error.details);
    if (code == MediaErrorCodes.notHost ||
        code == MediaErrorCodes.insufficientRank) {
      throw HostAuthorizationError(
        error.message,
        code: code!,
        details: error.details,
      );
    }
    if (code != null && code.startsWith('MEDIA_')) {
      throw MediaError(
        error.message,
        status: error.status,
        code: code,
        details: error.details,
      );
    }
    if (error is AuthenticationError || error is RateLimitError) rethrow;
    if (error is MediaError) rethrow;
    throw MediaError(
      error.message,
      status: error.status,
      code: code ?? error.code,
      details: error.details,
    );
  }
}
