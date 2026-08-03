/// The Media module: sessions, participants, moderation, permissions, voice
/// rooms, classroom, whiteboard, breakout rooms, waiting room, lobby chat,
/// signalling, telemetry, analytics, and realtime events.
///
/// Dart port of `supersosdk/src/media/*`.
library;

import 'dart:async';

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../realtime/realtime_socket.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'media_types.dart';

/// Base class for every Media-domain error.
class MediaError extends SupersoError {
  /// Creates a media error.
  const MediaError(
    String message, {
    int? status,
    String? code,
    Object? details,
  }) : super(message: message, status: status, code: code, details: details);
}

/// A moderation call was rejected because the caller lacks host standing.
///
/// Every moderation route requires an end-user access token belonging to that
/// session's host, teacher, assistant teacher, co-host, or moderator. Being
/// merely authenticated is not sufficient, and an API key alone never is.
///
/// If you see this unexpectedly, check that `auth.login()` has run and that
/// the signed-in user actually holds a privileged role in *this* session.
class HostAuthorizationError extends MediaError {
  /// Creates a host-authorization error.
  const HostAuthorizationError(
    String message, [
    Object? details,
  ]) : super(
          message,
          status: 403,
          code: 'HOST_AUTHORIZATION_REQUIRED',
          details: details,
        );
}

/// Drawing is not currently permitted on the target whiteboard.
///
/// Raised when a non-privileged participant draws while the host has
/// `allowParticipantDraw` turned off. The backend supplies the specific reason
/// in [SupersoError.details].
class WhiteboardPermissionError extends MediaError {
  /// Creates a whiteboard permission error.
  const WhiteboardPermissionError(
    String message, [
    Object? details,
  ]) : super(
          message,
          status: 403,
          code: 'WHITEBOARD_DRAW_NOT_PERMITTED',
          details: details,
        );
}

/// Extracts the backend's machine-readable `code` from an error payload.
///
/// The platform sends two shapes depending on the endpoint — the error object
/// directly (`{code, message}`) or nested under `error` — and the shared client
/// may hand either one through as `details`. Both are checked, so callers never
/// have to care which endpoint produced the failure.
String? mediaErrorCode(Object? details) {
  if (details is! Map<String, dynamic>) return null;
  final direct = details['code'];
  if (direct is String) return direct;
  final nested = details['error'];
  if (nested is Map<String, dynamic>) {
    final code = nested['code'];
    if (code is String) return code;
  }
  return null;
}

/// Wraps a Media call, normalizing failures into this hierarchy.
Future<T> withMediaErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on AuthenticationError {
    rethrow;
  } on RateLimitError {
    rethrow;
  } on NetworkError {
    rethrow;
  } on CancelledError {
    rethrow;
  } on PermissionError catch (error) {
    if (mediaErrorCode(error.details) == 'WHITEBOARD_DRAW_NOT_PERMITTED') {
      throw WhiteboardPermissionError(error.message, error.details);
    }
    throw HostAuthorizationError(error.message, error.details);
  } on SupersoError catch (error) {
    throw MediaError(
      error.message,
      status: error.status,
      code: error.code,
      details: error.details,
    );
  } on Object catch (error) {
    throw MediaError('$error');
  }
}

String _sessionPath(String sessionId, [String suffix = '']) =>
    '/media/sessions/${encodeSegment(sessionId)}'
    '${suffix.isEmpty ? '' : '/$suffix'}';

String _participantPath(String sessionId, String participantId, String action) =>
    '/media/sessions/${encodeSegment(sessionId)}'
    '/participants/${encodeSegment(participantId)}/$action';

MediaResource _resource(Object? data) => MediaResource.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

List<MediaResource> _resourceList(Object? data, [String? key]) {
  final list = data is List<dynamic>
      ? data
      : (data as Map<String, dynamic>?)?[key ?? 'items'] as List<dynamic>? ??
          const <dynamic>[];
  return list
      .whereType<Map<String, dynamic>>()
      .map(MediaResource.fromJson)
      .toList(growable: false);
}

MediaParticipant _participant(Object? data) => MediaParticipant.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

MediaSession _session(Object? data) => MediaSession.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// Session lifecycle.
///
/// Exposed at `superso.media.sessions`.
class MediaSessionsModule {
  /// Creates a sessions module bound to [client].
  const MediaSessionsModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/media/sessions` — creates a session.
  ///
  /// If an end-user access token is set, that user becomes the session's
  /// `createdBy` and will automatically become its host the first time they
  /// join. Sign in before calling this if you want the creator to be able to
  /// moderate.
  Future<ApiResponse<MediaSession>> create({
    required String title,
    String? type,
    String? visibility,
    String? description,
    String? scheduledAt,
    Map<String, dynamic>? settings,
  }) {
    if (title.trim().isEmpty) {
      throw const ValidationError('Superso: a session title is required.');
    }
    return withMediaErrors(
      () => _client.post<MediaSession>(
        '/media/sessions',
        body: <String, dynamic>{
          'title': title,
          if (type != null) 'type': type,
          if (visibility != null) 'visibility': visibility,
          if (description != null) 'description': description,
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
          if (settings != null) ...settings,
        },
        decoder: _session,
      ),
    );
  }

  /// `GET /v1/media/sessions` — lists sessions.
  Future<ApiResponse<MediaSessionList>> list({
    String? status,
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaSessionList>(
        '/media/sessions',
        options: RequestOptions(
          query: <String, Object?>{
            'status': status,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => MediaSessionList.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `GET /v1/media/sessions/:sessionId`
  Future<ApiResponse<MediaSession>> get(String sessionId) {
    return withMediaErrors(
      () => _client.get<MediaSession>(
        _sessionPath(sessionId),
        decoder: _session,
      ),
    );
  }

  /// `GET /v1/media/sessions/by-join-token` — resolves a session by token.
  Future<ApiResponse<MediaResource>> byJoinToken(String joinToken) {
    return withMediaErrors(
      () => _client.get<MediaResource>(
        '/media/sessions/by-join-token',
        options: RequestOptions(
          query: <String, Object?>{'join_token': joinToken},
        ),
        decoder: _resource,
      ),
    );
  }

  /// `POST /v1/media/sessions/:sessionId/start` — transitions to live.
  Future<ApiResponse<MediaSession>> start(String sessionId) {
    return withMediaErrors(
      () => _client.post<MediaSession>(
        _sessionPath(sessionId, 'start'),
        decoder: _session,
      ),
    );
  }

  /// `POST /v1/media/sessions/:sessionId/end` — ends the session.
  Future<ApiResponse<MediaSession>> end(String sessionId) {
    return withMediaErrors(
      () => _client.post<MediaSession>(
        _sessionPath(sessionId, 'end'),
        decoder: _session,
      ),
    );
  }

  /// `DELETE /v1/media/sessions/:sessionId` — cancels a session.
  Future<ApiResponse<void>> cancel(String sessionId) {
    return withMediaErrors(
      () => _client.delete<void>(_sessionPath(sessionId), decoder: (_) {}),
    );
  }

  /// `GET /v1/media/sessions/:sessionId/participants`
  Future<ApiResponse<MediaParticipantList>> participants(String sessionId) {
    return withMediaErrors(
      () => _client.get<MediaParticipantList>(
        _sessionPath(sessionId, 'participants'),
        decoder: (data) => MediaParticipantList.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `GET /v1/media/sessions/:sessionId/timeline` — the session event log.
  Future<ApiResponse<List<MediaResource>>> timeline(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'timeline'),
        decoder: (data) => _resourceList(data, 'events'),
      ),
    );
  }

  /// `GET /v1/media/sessions/:sessionId/tracks` — published media tracks.
  Future<ApiResponse<List<MediaResource>>> tracks(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'tracks'),
        decoder: (data) => _resourceList(data, 'tracks'),
      ),
    );
  }
}

/// Participant lookup, telemetry, and removal.
///
/// Exposed at `superso.media.participants`.
class MediaParticipantsModule {
  /// Creates a participants module bound to [client].
  const MediaParticipantsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /v1/media/participants` — every participant in the project.
  Future<ApiResponse<MediaParticipantList>> list({int? limit, int? offset}) {
    return withMediaErrors(
      () => _client.get<MediaParticipantList>(
        '/media/participants',
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => MediaParticipantList.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `GET /v1/media/participants/:participantId`
  Future<ApiResponse<MediaParticipant>> get(String participantId) {
    return withMediaErrors(
      () => _client.get<MediaParticipant>(
        '/media/participants/${encodeSegment(participantId)}',
        decoder: _participant,
      ),
    );
  }

  /// `PATCH /v1/media/participants/:participantId/telemetry` — reports
  /// connection quality.
  Future<ApiResponse<void>> pushTelemetry(
    String participantId, {
    double? rttMs,
    double? packetLossPct,
    double? jitterMs,
    int? bitrateKbps,
    Map<String, dynamic>? extra,
  }) {
    return withMediaErrors(
      () => _client.patch<void>(
        '/media/participants/${encodeSegment(participantId)}/telemetry',
        body: <String, dynamic>{
          if (rttMs != null) 'rtt_ms': rttMs,
          if (packetLossPct != null) 'packet_loss_pct': packetLossPct,
          if (jitterMs != null) 'jitter_ms': jitterMs,
          if (bitrateKbps != null) 'bitrate_kbps': bitrateKbps,
          if (extra != null) ...extra,
        },
        decoder: (_) {},
      ),
    );
  }

  /// `POST /v1/media/sessions/:sessionId/participants/:participantId/kick`
  ///
  /// Requires an end-user access token belonging to this session's host,
  /// teacher, co-host, or moderator. Before v0.3.0 this route had no
  /// per-caller authorization at all — any write-scoped API key could remove
  /// anyone, including the host.
  Future<ApiResponse<void>> kick(
    String sessionId,
    String participantId, {
    String? reason,
  }) {
    return withMediaErrors(
      () => _client.post<void>(
        _participantPath(sessionId, participantId, 'kick'),
        body: reason == null ? null : <String, dynamic>{'reason': reason},
        decoder: (_) {},
      ),
    );
  }
}

/// Participant self-service permission requests.
///
/// Exposed at `superso.media.permissions`. These are the participant-initiated
/// counterparts to the host-initiated calls on [MediaModerationModule], and
/// need only the project API key.
class MediaPermissionsModule {
  /// Creates a permissions module bound to [client].
  const MediaPermissionsModule(this._client);

  final SupersoHttpClient _client;

  /// Requests camera access.
  Future<ApiResponse<MediaParticipant>> requestCamera(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _request(sessionId, participantId, 'request-camera', reason);

  /// Requests microphone access.
  Future<ApiResponse<MediaParticipant>> requestMicrophone(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _request(sessionId, participantId, 'request-microphone', reason);

  /// Requests screen-share access.
  Future<ApiResponse<MediaParticipant>> requestScreen(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _request(sessionId, participantId, 'request-screen', reason);

  /// Requests to join the stage.
  Future<ApiResponse<MediaParticipant>> requestStage(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _request(sessionId, participantId, 'request-stage', reason);

  /// Cancels a pending stage request.
  Future<ApiResponse<MediaParticipant>> cancelStageRequest(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'cancel-stage-request', null);

  /// Cancels any pending permission request.
  Future<ApiResponse<MediaParticipant>> cancelRequest(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'cancel-request', null);

  /// Raises the caller's hand.
  Future<ApiResponse<MediaParticipant>> raiseHand(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'raise-hand', null);

  /// Lowers the caller's hand.
  Future<ApiResponse<MediaParticipant>> lowerHand(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'lower-hand', null);

  /// Accepts a host's stage invitation.
  Future<ApiResponse<MediaParticipant>> acceptStageInvite(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'accept-stage-invite', null);

  /// Declines a host's stage invitation.
  Future<ApiResponse<MediaParticipant>> declineStageInvite(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'decline-stage-invite', null);

  /// Signals intent to share a screen. A host must still approve.
  Future<ApiResponse<MediaParticipant>> requestScreenShare(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'request-screen-share', null);

  /// Stops an active screen share.
  Future<ApiResponse<MediaParticipant>> stopScreenShare(
    String sessionId,
    String participantId,
  ) =>
      _request(sessionId, participantId, 'stop-screen-share', null);

  Future<ApiResponse<MediaParticipant>> _request(
    String sessionId,
    String participantId,
    String action,
    String? reason,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _participantPath(sessionId, participantId, action),
        body: reason == null ? null : <String, dynamic>{'reason': reason},
        decoder: _participant,
      ),
    );
  }
}

/// Host moderation.
///
/// Exposed at `superso.media.moderation`.
///
/// **Every method here requires an end-user access token** belonging to this
/// session's host, teacher, assistant teacher, co-host, or moderator — an API
/// key alone is not enough, and being merely authenticated is not enough
/// either. Call `auth.login()` first; the shared client attaches the token
/// automatically. A caller without standing gets a [HostAuthorizationError].
///
/// A session's creator becomes its host automatically the first time they
/// join, provided they were signed in when the session was created.
class MediaModerationModule {
  /// Creates a moderation module bound to [client].
  const MediaModerationModule(this._client);

  final SupersoHttpClient _client;

  /// Grants camera publish permission.
  Future<ApiResponse<MediaParticipant>> approveCamera(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-camera', reason);

  /// Denies a pending camera request.
  Future<ApiResponse<MediaParticipant>> rejectCamera(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-camera', reason);

  /// Revokes camera publish permission.
  Future<ApiResponse<MediaParticipant>> revokeCamera(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'revoke-camera', reason);

  /// Grants microphone publish permission.
  Future<ApiResponse<MediaParticipant>> approveMicrophone(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-microphone', reason);

  /// Denies a pending microphone request.
  Future<ApiResponse<MediaParticipant>> rejectMicrophone(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-microphone', reason);

  /// Revokes microphone publish permission.
  Future<ApiResponse<MediaParticipant>> revokeMicrophone(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'revoke-microphone', reason);

  /// Grants screen-share permission.
  Future<ApiResponse<MediaParticipant>> approveScreen(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-screen', reason);

  /// Denies a pending screen-share request.
  Future<ApiResponse<MediaParticipant>> rejectScreen(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-screen', reason);

  /// Revokes screen-share permission.
  Future<ApiResponse<MediaParticipant>> revokeScreen(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'revoke-screen', reason);

  /// Mutes a participant's microphone.
  Future<ApiResponse<MediaParticipant>> mute(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'mute', reason);

  /// Unmutes a participant.
  Future<ApiResponse<MediaParticipant>> unmute(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'unmute', null);

  /// Force-mutes a participant. They cannot self-unmute until
  /// [clearForceMute].
  Future<ApiResponse<MediaParticipant>> forceMute(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'force-mute', null);

  /// Lifts a force-mute.
  Future<ApiResponse<MediaParticipant>> clearForceMute(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'clear-force-mute', null);

  /// Hides a participant's video tile for everyone else.
  Future<ApiResponse<MediaParticipant>> hideVideo(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'hide-video', null);

  /// Restores a participant's video tile.
  Future<ApiResponse<MediaParticipant>> showVideo(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'show-video', null);

  /// Pins a participant in every viewer's layout.
  Future<ApiResponse<MediaParticipant>> pin(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'pin', null);

  /// Removes a participant's pin.
  Future<ApiResponse<MediaParticipant>> unpin(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'unpin', null);

  /// Spotlights a participant.
  Future<ApiResponse<MediaParticipant>> spotlight(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'spotlight', null);

  /// Removes a participant's spotlight.
  Future<ApiResponse<MediaParticipant>> unspotlight(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'unspotlight', null);

  /// Approves a pending stage request.
  Future<ApiResponse<MediaParticipant>> approveStageRequest(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-stage', reason);

  /// Rejects a pending stage request.
  Future<ApiResponse<MediaParticipant>> rejectStageRequest(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-stage', reason);

  /// Invites a participant onto the stage.
  Future<ApiResponse<MediaParticipant>> inviteToStage(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'invite-to-stage', null);

  /// Removes a participant from the stage.
  Future<ApiResponse<MediaParticipant>> removeFromStage(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'remove-from-stage', reason);

  /// Promotes a participant to publisher.
  Future<ApiResponse<MediaParticipant>> promote(
          String sessionId, String participantId) =>
      _act(sessionId, participantId, 'promote', null);

  /// Demotes a participant to viewer.
  Future<ApiResponse<MediaParticipant>> demote(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'demote', reason);

  /// Assigns a classroom role.
  ///
  /// This is how a bootstrapped host builds a teaching team without touching
  /// the Admin Dashboard. Only [ClassroomRole.assignable] roles may be
  /// granted; owner is bootstrap-only and the guest roles come from the join
  /// flow, so passing either throws a [ValidationError] before any request.
  Future<ApiResponse<void>> assignRole(
    String sessionId,
    String participantId,
    ClassroomRole role,
  ) {
    if (!ClassroomRole.assignable.contains(role)) {
      throw ValidationError(
        'Superso: `${role.wireValue}` cannot be assigned. Assignable roles '
        'are: ${ClassroomRole.assignable.map((r) => r.wireValue).join(', ')}.',
      );
    }
    return withMediaErrors(
      () => _client.post<void>(
        _participantPath(sessionId, participantId, 'assign-role'),
        body: <String, dynamic>{'role': role.wireValue},
        decoder: (_) {},
      ),
    );
  }

  Future<ApiResponse<MediaParticipant>> _act(
    String sessionId,
    String participantId,
    String action,
    String? reason,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _participantPath(sessionId, participantId, action),
        body: reason == null ? null : <String, dynamic>{'reason': reason},
        decoder: _participant,
      ),
    );
  }
}

/// The collaborative whiteboard: lifecycle plus the full drawing engine.
///
/// Exposed at `superso.media.whiteboard`.
///
/// Authorization splits two ways:
/// - [start], [end], [updatePermissions], and [clear] require host standing
///   and an end-user access token.
/// - [draw], [addShape], [addText], [erase], [undo], [redo], and [sendPointer]
///   are self-service and need only the project API key. The backend enforces
///   the board's `allowParticipantDraw` flag: a non-privileged participant may
///   draw only when a host has turned it on.
///
/// **Sync model.** A client opening a board mid-session, or reconnecting,
/// should call [listActions] and apply every returned action in order — that
/// reconstructs the exact current canvas with no server-side rendering. From
/// then on the whiteboard event streams keep it live.
class MediaWhiteboardModule {
  /// Creates a whiteboard module bound to [client].
  const MediaWhiteboardModule(this._client);

  final SupersoHttpClient _client;

  String _boardPath(String sessionId, String whiteboardId, String action) =>
      '${_sessionPath(sessionId, 'whiteboard')}'
      '/${encodeSegment(whiteboardId)}/$action';

  String _drawPath(
    String sessionId,
    String participantId,
    String whiteboardId,
    String action,
  ) =>
      '/media/sessions/${encodeSegment(sessionId)}'
      '/participants/${encodeSegment(participantId)}'
      '/whiteboard/${encodeSegment(whiteboardId)}/$action';

  /// `POST /sessions/:sessionId/whiteboard` — opens a board. Host only.
  ///
  /// Each call creates a *new* board with a new ID. An ID from a previous
  /// board permanently 404s once superseded — always use the ID this returns.
  Future<ApiResponse<WhiteboardSession>> start(
    String sessionId, {
    String? title,
    bool allowParticipantDraw = false,
  }) {
    return withMediaErrors(
      () => _client.post<WhiteboardSession>(
        _sessionPath(sessionId, 'whiteboard'),
        body: <String, dynamic>{
          if (title != null) 'title': title,
          'allow_participant_draw': allowParticipantDraw,
        },
        decoder: _whiteboard,
      ),
    );
  }

  /// `GET /sessions/:sessionId/whiteboard` — the active board.
  ///
  /// Returns 404 when no board is currently open — before a host starts one,
  /// after one ends, or when a previous board has been superseded. That is
  /// ordinary REST semantics here, not an error condition.
  Future<ApiResponse<WhiteboardSession>> getActive(String sessionId) {
    return withMediaErrors(
      () => _client.get<WhiteboardSession>(
        _sessionPath(sessionId, 'whiteboard'),
        decoder: _whiteboard,
      ),
    );
  }

  /// `POST .../whiteboard/:whiteboardId/end` — closes the board. Host only.
  Future<ApiResponse<void>> end(String sessionId, String whiteboardId) {
    return withMediaErrors(
      () => _client.post<void>(
        _boardPath(sessionId, whiteboardId, 'end'),
        decoder: (_) {},
      ),
    );
  }

  /// `PATCH .../whiteboard/:whiteboardId/permissions` — toggles whether
  /// non-privileged participants may draw. Host only.
  Future<ApiResponse<void>> updatePermissions(
    String sessionId,
    String whiteboardId, {
    required bool allowParticipantDraw,
  }) {
    return withMediaErrors(
      () => _client.patch<void>(
        _boardPath(sessionId, whiteboardId, 'permissions'),
        body: <String, dynamic>{
          'allow_participant_draw': allowParticipantDraw,
        },
        decoder: (_) {},
      ),
    );
  }

  /// `POST .../whiteboard/:whiteboardId/clear` — removes every object.
  /// Host only.
  Future<ApiResponse<void>> clear(String sessionId, String whiteboardId) {
    return withMediaErrors(
      () => _client.post<void>(
        _boardPath(sessionId, whiteboardId, 'clear'),
        decoder: (_) {},
      ),
    );
  }

  /// `GET .../whiteboard/:whiteboardId/actions` — the full replay log.
  Future<ApiResponse<WhiteboardActionLog>> listActions(
    String sessionId,
    String whiteboardId,
  ) {
    return withMediaErrors(
      () => _client.get<WhiteboardActionLog>(
        _boardPath(sessionId, whiteboardId, 'actions'),
        decoder: (data) => WhiteboardActionLog.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST .../whiteboard/:whiteboardId/draw` — appends a freehand stroke.
  ///
  /// [objectId] must be a client-generated stable identifier; erase, undo, and
  /// redo all resolve objects by it. [points] is an opaque coordinate list the
  /// backend stores verbatim.
  Future<ApiResponse<WhiteboardAction>> draw({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
    required String objectId,
    required List<Map<String, double>> points,
    String? color,
    double? strokeWidth,
  }) {
    if (objectId.trim().isEmpty) {
      throw const ValidationError('Superso: a stroke needs an objectId.');
    }
    return withMediaErrors(
      () => _client.post<WhiteboardAction>(
        _drawPath(sessionId, participantId, whiteboardId, 'draw'),
        body: <String, dynamic>{
          'object_id': objectId,
          'points': points,
          if (color != null) 'color': color,
          if (strokeWidth != null) 'stroke_width': strokeWidth,
        },
        decoder: _action,
      ),
    );
  }

  /// `POST .../whiteboard/:whiteboardId/shapes` — adds a shape.
  Future<ApiResponse<WhiteboardAction>> addShape({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
    required String objectId,
    required Map<String, dynamic> payload,
    String? color,
    double? strokeWidth,
  }) =>
      _addObject(
        sessionId: sessionId,
        participantId: participantId,
        whiteboardId: whiteboardId,
        action: 'shapes',
        objectId: objectId,
        payload: payload,
        color: color,
        strokeWidth: strokeWidth,
      );

  /// `POST .../whiteboard/:whiteboardId/text` — adds a text object.
  Future<ApiResponse<WhiteboardAction>> addText({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
    required String objectId,
    required Map<String, dynamic> payload,
    String? color,
    double? strokeWidth,
  }) =>
      _addObject(
        sessionId: sessionId,
        participantId: participantId,
        whiteboardId: whiteboardId,
        action: 'text',
        objectId: objectId,
        payload: payload,
        color: color,
        strokeWidth: strokeWidth,
      );

  /// `POST .../whiteboard/:whiteboardId/erase` — removes one object.
  Future<ApiResponse<void>> erase({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
    required String objectId,
  }) {
    return withMediaErrors(
      () => _client.post<void>(
        _drawPath(sessionId, participantId, whiteboardId, 'erase'),
        body: <String, dynamic>{'object_id': objectId},
        decoder: (_) {},
      ),
    );
  }

  /// `POST .../whiteboard/:whiteboardId/undo` — reverts your own last action.
  ///
  /// Undo is scoped per participant: you can only undo your own work, so
  /// concurrent editors never stomp on each other's history. Returns `null`
  /// when there is nothing left to undo.
  Future<WhiteboardAction?> undo({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
  }) async {
    final response = await withMediaErrors(
      () => _client.post<Map<String, dynamic>?>(
        _drawPath(sessionId, participantId, whiteboardId, 'undo'),
        decoder: (data) => data as Map<String, dynamic>?,
      ),
    );
    final data = response.data;
    return data == null ? null : WhiteboardAction.fromJson(data);
  }

  /// `POST .../whiteboard/:whiteboardId/redo` — re-applies your own last
  /// undone action. Returns `null` when there is nothing to redo.
  Future<WhiteboardAction?> redo({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
  }) async {
    final response = await withMediaErrors(
      () => _client.post<Map<String, dynamic>?>(
        _drawPath(sessionId, participantId, whiteboardId, 'redo'),
        decoder: (data) => data as Map<String, dynamic>?,
      ),
    );
    final data = response.data;
    return data == null ? null : WhiteboardAction.fromJson(data);
  }

  /// `POST .../whiteboard/:whiteboardId/pointer` — broadcasts a live cursor.
  ///
  /// Deliberately not persisted: a cursor position is meaningless after the
  /// fact and would flood the action log at mouse-move frequency.
  Future<ApiResponse<void>> sendPointer({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
    required double x,
    required double y,
  }) {
    return withMediaErrors(
      () => _client.post<void>(
        _drawPath(sessionId, participantId, whiteboardId, 'pointer'),
        body: <String, dynamic>{'x': x, 'y': y},
        decoder: (_) {},
      ),
    );
  }

  Future<ApiResponse<WhiteboardAction>> _addObject({
    required String sessionId,
    required String participantId,
    required String whiteboardId,
    required String action,
    required String objectId,
    required Map<String, dynamic> payload,
    String? color,
    double? strokeWidth,
  }) {
    if (objectId.trim().isEmpty) {
      throw const ValidationError('Superso: an object needs an objectId.');
    }
    return withMediaErrors(
      () => _client.post<WhiteboardAction>(
        _drawPath(sessionId, participantId, whiteboardId, action),
        body: <String, dynamic>{
          'object_id': objectId,
          'payload': payload,
          if (color != null) 'color': color,
          if (strokeWidth != null) 'stroke_width': strokeWidth,
        },
        decoder: _action,
      ),
    );
  }

  static WhiteboardSession _whiteboard(Object? data) =>
      WhiteboardSession.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );

  static WhiteboardAction _action(Object? data) => WhiteboardAction.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );
}

/// The classroom engine: reactions, polls, chat, speaker queue, attendance.
///
/// Exposed at `superso.media.classroom`.
class MediaClassroomModule {
  /// Creates a classroom module bound to [client].
  const MediaClassroomModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /sessions/:sessionId/reactions` — sends an emoji reaction.
  Future<ApiResponse<void>> sendReaction(
    String sessionId, {
    required String participantId,
    required String emoji,
  }) {
    return withMediaErrors(
      () => _client.post<void>(
        _sessionPath(sessionId, 'reactions'),
        body: <String, dynamic>{
          'participant_id': participantId,
          'emoji': emoji,
        },
        decoder: (_) {},
      ),
    );
  }

  /// `GET /sessions/:sessionId/reactions/summary` — per-emoji counts.
  Future<ApiResponse<List<MediaResource>>> reactionSummary(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'reactions/summary'),
        decoder: (data) => _resourceList(data, 'reactions'),
      ),
    );
  }

  /// `POST /sessions/:sessionId/polls` — creates a poll.
  Future<ApiResponse<MediaResource>> createPoll(
    String sessionId, {
    required String question,
    required List<String> options,
    String? createdBy,
    bool? allowMultiple,
    bool? anonymous,
  }) {
    if (options.length < 2) {
      throw const ValidationError('Superso: a poll needs at least two options.');
    }
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'polls'),
        body: <String, dynamic>{
          'question': question,
          'options': options,
          if (createdBy != null) 'created_by': createdBy,
          if (allowMultiple != null) 'allow_multiple': allowMultiple,
          if (anonymous != null) 'anonymous': anonymous,
        },
        decoder: _resource,
      ),
    );
  }

  /// `GET /sessions/:sessionId/polls` — every poll in the session.
  Future<ApiResponse<List<MediaResource>>> listPolls(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'polls'),
        decoder: (data) => _resourceList(data, 'polls'),
      ),
    );
  }

  /// `POST /sessions/:sessionId/polls/:pollId/vote` — submits a vote.
  Future<ApiResponse<MediaResource>> vote(
    String sessionId,
    String pollId, {
    required String participantId,
    required List<int> optionIndexes,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'polls/${encodeSegment(pollId)}/vote'),
        body: <String, dynamic>{
          'participant_id': participantId,
          'option_indexes': optionIndexes,
        },
        decoder: _resource,
      ),
    );
  }

  /// `GET /sessions/:sessionId/polls/:pollId/results` — vote aggregation.
  Future<ApiResponse<MediaResource>> pollResults(
    String sessionId,
    String pollId,
  ) {
    return withMediaErrors(
      () => _client.get<MediaResource>(
        _sessionPath(sessionId, 'polls/${encodeSegment(pollId)}/results'),
        decoder: _resource,
      ),
    );
  }

  /// `GET /sessions/:sessionId/attendance` — per-participant summary.
  Future<ApiResponse<List<MediaResource>>> attendanceSummary(
    String sessionId,
  ) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'attendance'),
        decoder: (data) => _resourceList(data, 'summary'),
      ),
    );
  }

  /// `POST /sessions/:sessionId/chat` — sends a chat message.
  Future<ApiResponse<MediaResource>> sendChatMessage(
    String sessionId, {
    required String participantId,
    required String body,
    String? replyToId,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'chat'),
        body: <String, dynamic>{
          'participant_id': participantId,
          'body': body,
          if (replyToId != null) 'reply_to_id': replyToId,
        },
        decoder: _resource,
      ),
    );
  }

  /// `GET /sessions/:sessionId/chat` — the message history.
  Future<ApiResponse<List<MediaResource>>> listChat(
    String sessionId, {
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'chat'),
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => _resourceList(data, 'messages'),
      ),
    );
  }

  /// `GET /sessions/:sessionId/speaker-queue` — the queue, in priority order.
  Future<ApiResponse<List<MediaResource>>> listSpeakerQueue(
    String sessionId,
  ) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'speaker-queue'),
        decoder: (data) => _resourceList(data, 'queue'),
      ),
    );
  }

  /// `POST /sessions/:sessionId/speaker-queue` — joins the queue.
  Future<ApiResponse<MediaResource>> joinSpeakerQueue(
    String sessionId, {
    required String participantId,
    String? reason,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'speaker-queue'),
        body: <String, dynamic>{
          'participant_id': participantId,
          if (reason != null) 'reason': reason,
        },
        decoder: _resource,
      ),
    );
  }

  /// `DELETE /sessions/:sessionId/speaker-queue/:participantId` — leaves the
  /// queue.
  Future<ApiResponse<void>> leaveSpeakerQueue(
    String sessionId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.delete<void>(
        _sessionPath(
          sessionId,
          'speaker-queue/${encodeSegment(participantId)}',
        ),
        decoder: (_) {},
      ),
    );
  }

  /// `POST /sessions/:sessionId/classroom/raise-hand` — raises a hand, with
  /// classroom metadata.
  Future<ApiResponse<MediaParticipant>> raiseHand(
    String sessionId, {
    required String participantId,
    String? emoji,
    String? questionType,
    int? priority,
  }) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _sessionPath(sessionId, 'classroom/raise-hand'),
        body: <String, dynamic>{
          'participant_id': participantId,
          if (emoji != null) 'emoji': emoji,
          if (questionType != null) 'question_type': questionType,
          if (priority != null) 'priority': priority,
        },
        decoder: _participant,
      ),
    );
  }

  /// `POST /sessions/:sessionId/classroom/lower-hand` — lowers a hand.
  Future<ApiResponse<MediaParticipant>> lowerHand(
    String sessionId, {
    required String participantId,
  }) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _sessionPath(sessionId, 'classroom/lower-hand'),
        body: <String, dynamic>{'participant_id': participantId},
        decoder: _participant,
      ),
    );
  }
}

/// Voice rooms.
///
/// Exposed at `superso.media.voiceRooms`.
class MediaVoiceRoomsModule {
  /// Creates a voice-rooms module bound to [client].
  const MediaVoiceRoomsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /v1/media/voice-rooms`
  Future<ApiResponse<List<MediaResource>>> list({int? limit, int? offset}) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        '/media/voice-rooms',
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => _resourceList(data, 'voice_rooms'),
      ),
    );
  }

  /// `POST /v1/media/voice-rooms`
  Future<ApiResponse<MediaResource>> create({
    required String title,
    String? roomType,
    Map<String, dynamic>? settings,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        '/media/voice-rooms',
        body: <String, dynamic>{
          'title': title,
          if (roomType != null) 'room_type': roomType,
          if (settings != null) ...settings,
        },
        decoder: _resource,
      ),
    );
  }

  /// `GET /v1/media/voice-rooms/:roomId`
  Future<ApiResponse<MediaResource>> get(String roomId) {
    return withMediaErrors(
      () => _client.get<MediaResource>(
        '/media/voice-rooms/${encodeSegment(roomId)}',
        decoder: _resource,
      ),
    );
  }

  /// `POST /v1/media/voice-rooms/:roomId/start`
  Future<ApiResponse<MediaResource>> start(String roomId) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        '/media/voice-rooms/${encodeSegment(roomId)}/start',
        decoder: _resource,
      ),
    );
  }

  /// `POST /v1/media/voice-rooms/:roomId/end`
  Future<ApiResponse<MediaResource>> end(String roomId) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        '/media/voice-rooms/${encodeSegment(roomId)}/end',
        decoder: _resource,
      ),
    );
  }

  /// `GET /v1/media/voice-rooms/:roomId/participants`
  Future<ApiResponse<MediaParticipantList>> participants(String roomId) {
    return withMediaErrors(
      () => _client.get<MediaParticipantList>(
        '/media/voice-rooms/${encodeSegment(roomId)}/participants',
        decoder: (data) => MediaParticipantList.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /voice-rooms/:roomId/participants/:participantId/raise-hand`
  Future<ApiResponse<MediaParticipant>> raiseHand(
    String roomId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        '/media/voice-rooms/${encodeSegment(roomId)}'
        '/participants/${encodeSegment(participantId)}/raise-hand',
        decoder: _participant,
      ),
    );
  }

  /// `POST /voice-rooms/:roomId/participants/:participantId/lower-hand`
  Future<ApiResponse<MediaParticipant>> lowerHand(
    String roomId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        '/media/voice-rooms/${encodeSegment(roomId)}'
        '/participants/${encodeSegment(participantId)}/lower-hand',
        decoder: _participant,
      ),
    );
  }
}

/// Breakout rooms, the waiting room, and lobby chat.
///
/// Exposed at `superso.media.rooms`.
///
/// Breakout rooms are read-only from the SDK: creating, closing, and moving
/// participants between them is Admin-Dashboard-only.
class MediaRoomsModule {
  /// Creates a rooms module bound to [client].
  const MediaRoomsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /sessions/:sessionId/breakout-rooms` — open rooms.
  Future<ApiResponse<List<MediaResource>>> listBreakoutRooms(
    String sessionId,
  ) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'breakout-rooms'),
        decoder: (data) => _resourceList(data, 'rooms'),
      ),
    );
  }

  /// `GET /sessions/:sessionId/breakout-rooms/:roomId`
  Future<ApiResponse<MediaResource>> getBreakoutRoom(
    String sessionId,
    String roomId,
  ) {
    return withMediaErrors(
      () => _client.get<MediaResource>(
        _sessionPath(sessionId, 'breakout-rooms/${encodeSegment(roomId)}'),
        decoder: _resource,
      ),
    );
  }

  /// `POST /sessions/:sessionId/waiting-room` — joins the waiting queue.
  Future<ApiResponse<MediaResource>> enqueueWaitingRoom(
    String sessionId, {
    required String participantId,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'waiting-room'),
        body: <String, dynamic>{'participant_id': participantId},
        decoder: _resource,
      ),
    );
  }

  /// `GET /sessions/:sessionId/waiting-room/:entryId` — queue position and
  /// status.
  Future<ApiResponse<MediaResource>> getWaitingRoomEntry(
    String sessionId,
    String entryId,
  ) {
    return withMediaErrors(
      () => _client.get<MediaResource>(
        _sessionPath(sessionId, 'waiting-room/${encodeSegment(entryId)}'),
        decoder: _resource,
      ),
    );
  }

  /// `GET /sessions/:sessionId/lobby-chat` — lobby messages.
  Future<ApiResponse<List<MediaResource>>> listLobbyChat(
    String sessionId, {
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, 'lobby-chat'),
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => _resourceList(data, 'messages'),
      ),
    );
  }

  /// `POST /sessions/:sessionId/lobby-chat` — sends a lobby message.
  Future<ApiResponse<MediaResource>> sendLobbyMessage(
    String sessionId, {
    required String participantId,
    required String senderName,
    required String body,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'lobby-chat'),
        body: <String, dynamic>{
          'participant_id': participantId,
          'sender_name': senderName,
          'body': body,
        },
        decoder: _resource,
      ),
    );
  }
}

/// Invitations and share links.
///
/// Exposed at `superso.media.invites`.
class MediaInvitesModule {
  /// Creates an invites module bound to [client].
  const MediaInvitesModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /sessions/:sessionId/invitations` — creates an invitation.
  Future<ApiResponse<MediaResource>> create(
    String sessionId, {
    required String inviteType,
    String? email,
    String? phone,
    String? role,
    String? expiresAt,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'invitations'),
        body: <String, dynamic>{
          'invite_type': inviteType,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
          if (role != null) 'role': role,
          if (expiresAt != null) 'expires_at': expiresAt,
        },
        decoder: _resource,
      ),
    );
  }

  /// `POST /sessions/:sessionId/links` — creates a share link.
  Future<ApiResponse<MediaResource>> createLink(
    String sessionId, {
    required String linkType,
    int? maxUses,
    String? expiresAt,
  }) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(sessionId, 'links'),
        body: <String, dynamic>{
          'link_type': linkType,
          if (maxUses != null) 'max_uses': maxUses,
          if (expiresAt != null) 'expires_at': expiresAt,
        },
        decoder: _resource,
      ),
    );
  }

  /// `POST /v1/media/invites/validate` — checks a token without consuming it.
  Future<ApiResponse<MediaResource>> validate(String token) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        '/media/invites/validate',
        body: <String, dynamic>{'token': token},
        decoder: _resource,
      ),
    );
  }

  /// `POST /v1/media/invites/accept` — consumes an invitation token.
  Future<ApiResponse<MediaResource>> accept(String token) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        '/media/invites/accept',
        body: <String, dynamic>{'token': token},
        decoder: _resource,
      ),
    );
  }

  /// `GET /v1/media/join/:token` — resolves a share link.
  ///
  /// Unauthenticated: any holder of the token may resolve it. Expiry and
  /// use-count limits are enforced server-side.
  Future<ApiResponse<MediaResource>> resolveLink(String token) {
    return withMediaErrors(
      () => _client.get<MediaResource>(
        '/media/join/${encodeSegment(token)}',
        decoder: _resource,
      ),
    );
  }
}

/// The composition root for the Media module.
///
/// ```dart
/// // Host creates and starts a session
/// final session = await superso.media.sessions.create(title: 'Standup');
/// await superso.media.sessions.start(session.data.id);
///
/// // Listen to everything happening in it
/// superso.media.events(session.data.id).listen((frame) {
///   print('${frame.event}');
/// });
///
/// // Moderate (requires the host to be signed in)
/// await superso.media.moderation.mute(sessionId, participantId);
///
/// // Whiteboard
/// final board = await superso.media.whiteboard.start(
///   sessionId,
///   allowParticipantDraw: true,
/// );
/// ```
class MediaModule implements SdkModule, Disposable {
  /// Creates the media module bound to [client].
  MediaModule(this.client)
      : sessions = MediaSessionsModule(client),
        participants = MediaParticipantsModule(client),
        permissions = MediaPermissionsModule(client),
        moderation = MediaModerationModule(client),
        whiteboard = MediaWhiteboardModule(client),
        classroom = MediaClassroomModule(client),
        voiceRooms = MediaVoiceRoomsModule(client),
        rooms = MediaRoomsModule(client),
        invites = MediaInvitesModule(client),
        _client = client;

  @override
  final SupersoHttpClient client;

  final SupersoHttpClient _client;

  /// Session lifecycle.
  final MediaSessionsModule sessions;

  /// Participant lookup, telemetry, and removal.
  final MediaParticipantsModule participants;

  /// Participant self-service permission requests.
  final MediaPermissionsModule permissions;

  /// Host moderation. Requires an end-user access token.
  final MediaModerationModule moderation;

  /// The collaborative whiteboard.
  final MediaWhiteboardModule whiteboard;

  /// The classroom engine.
  final MediaClassroomModule classroom;

  /// Voice rooms.
  final MediaVoiceRoomsModule voiceRooms;

  /// Breakout rooms, waiting room, and lobby chat.
  final MediaRoomsModule rooms;

  /// Invitations and share links.
  final MediaInvitesModule invites;

  final Map<String, RealtimeSocket> _sockets = <String, RealtimeSocket>{};

  /// `GET /v1/media/overview` — live statistics plus today's usage.
  Future<ApiResponse<MediaResource>> overview() {
    return withMediaErrors(
      () => _client.get<MediaResource>('/media/overview', decoder: _resource),
    );
  }

  /// `GET /v1/media/usage` — daily usage metrics.
  Future<ApiResponse<List<MediaResource>>> usage({int days = 30}) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        '/media/usage',
        options: RequestOptions(query: <String, Object?>{'days': days}),
        decoder: (data) => _resourceList(data, 'usage'),
      ),
    );
  }

  /// `GET /v1/media/settings` — the project's media settings.
  Future<ApiResponse<MediaResource>> getSettings() {
    return withMediaErrors(
      () => _client.get<MediaResource>('/media/settings', decoder: _resource),
    );
  }

  /// `PUT /v1/media/settings` — updates the project's media settings.
  Future<ApiResponse<MediaResource>> updateSettings(
    Map<String, dynamic> settings,
  ) {
    return withMediaErrors(
      () => _client.put<MediaResource>(
        '/media/settings',
        body: settings,
        decoder: _resource,
      ),
    );
  }

  /// Every realtime event broadcast on a session's channel.
  ///
  /// The connection opens lazily on first listen and is shared by every
  /// listener for that session. Event names are catalogued in
  /// `media_events.dart`.
  ///
  /// ```dart
  /// superso.media.events(sessionId)
  ///     .where((f) => f.event == MediaParticipantEvents.joined)
  ///     .listen((f) => print('joined: ${f.data}'));
  /// ```
  Stream<MediaEvent> events(String sessionId) {
    final socket = _sockets.putIfAbsent(
      sessionId,
      () => RealtimeSocket(_client, channel: 'media.$sessionId'),
    );
    return socket.messages.map(MediaEvent.fromJson);
  }

  /// Events matching one event name on a session's channel.
  Stream<MediaEvent> on(String sessionId, String eventName) =>
      events(sessionId).where((e) => e.event == eventName);

  /// Closes the realtime connection for one session.
  Future<void> disconnect(String sessionId) async {
    final socket = _sockets.remove(sessionId);
    await socket?.dispose();
  }

  /// Closes every open realtime connection.
  Future<void> disconnectAll() async {
    final sockets = List<RealtimeSocket>.of(_sockets.values);
    _sockets.clear();
    await Future.wait(sockets.map((s) => s.dispose()));
  }

  @override
  Future<void> dispose() => disconnectAll();
}

/// A decoded realtime event from a session channel.
class MediaEvent {
  /// Creates a media event.
  const MediaEvent({required this.event, required this.raw, this.data});

  /// Decodes an event from a realtime frame.
  factory MediaEvent.fromJson(Map<String, dynamic> json) => MediaEvent(
        event: json['event'] as String? ?? json['type'] as String? ?? '',
        raw: json,
        data: json['data'],
      );

  /// The event name. See the catalogues in `media_events.dart`.
  final String event;

  /// The event payload.
  final Object? data;

  /// The complete decoded frame.
  final Map<String, dynamic> raw;

  /// The payload as a JSON map, or an empty map when it is not one.
  ///
  /// The `is` test is parenthesized deliberately: `x is Map<K, V> ? a : b`
  /// is genuinely ambiguous to the Dart parser, which reads `Map<K, V>?` as a
  /// nullable type and then fails on the rest of the conditional.
  Map<String, dynamic> get dataAsMap {
    final payload = data;
    return payload is Map<String, dynamic>
        ? payload
        : const <String, dynamic>{};
  }

  /// The payload decoded as a participant.
  ///
  /// Only meaningful for participant-shaped events.
  MediaParticipant get asParticipant => MediaParticipant.fromJson(dataAsMap);

  /// The payload decoded as a session.
  MediaSession get asSession => MediaSession.fromJson(dataAsMap);

  /// The payload decoded as a whiteboard action.
  WhiteboardAction get asWhiteboardAction =>
      WhiteboardAction.fromJson(dataAsMap);

  @override
  String toString() => 'MediaEvent($event)';
}
