/// The Media module: sessions, participants, moderation, permissions, voice
/// rooms, classroom, breakout rooms, waiting room, raw WebRTC signaling,
/// telemetry, analytics, and realtime events.
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
import 'media_signaling.dart';
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

PermissionRequest _permissionRequest(Object? data) =>
    PermissionRequest.fromJson(
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

  /// `GET /v1/media/sessions/:sessionId/speakers` — docs/media.md §19
  /// "Active Speaker Detection": participants currently speaking or with
  /// camera on. Documented since before this route existed on the SDK
  /// router; was previously registered only under the Admin-JWT router
  /// (`media_routes.go`) — closed as part of the public SDK endpoint audit,
  /// mirroring `SDKHandler.GetActiveSpeakers`.
  Future<ApiResponse<List<MediaParticipant>>> speakers(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaParticipant>>(
        _sessionPath(sessionId, 'speakers'),
        decoder: (data) =>
            ((data as Map<String, dynamic>?)?['speakers'] as List<dynamic>? ??
                    const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .map(MediaParticipant.fromJson)
                .toList(growable: false),
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
  ///
  /// v0.3.10 fix: this previously discarded the response body entirely
  /// (`ApiResponse<void>`, `decoder: (_) {}`), even though docs/media.md
  /// §25 documents the server as returning "the full updated participant
  /// object" — the same response `supersosdk`'s `telemetry.push()` already
  /// surfaces as a `MediaParticipant`, including the just-recomputed
  /// `connection_score`/`network_quality`. There was no way to read those
  /// recomputed values without an extra, separate `get(participantId)`
  /// call. Now decoded with the same [_participant] decoder `get()` uses,
  /// so the response is a real [MediaParticipant] (any field without a
  /// dedicated getter remains reachable via `.raw`, same as everywhere else
  /// in this class).
  Future<ApiResponse<MediaParticipant>> pushTelemetry(
    String participantId, {
    double? rttMs,
    double? packetLossPct,
    double? jitterMs,
    int? bitrateKbps,
    Map<String, dynamic>? extra,
  }) {
    return withMediaErrors(
      () => _client.patch<MediaParticipant>(
        '/media/participants/${encodeSegment(participantId)}/telemetry',
        body: <String, dynamic>{
          if (rttMs != null) 'rtt_ms': rttMs,
          if (packetLossPct != null) 'packet_loss_pct': packetLossPct,
          if (jitterMs != null) 'jitter_ms': jitterMs,
          if (bitrateKbps != null) 'bitrate_kbps': bitrateKbps,
          if (extra != null) ...extra,
        },
        decoder: _participant,
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
  ///
  /// Returns the created [PermissionRequest] — fixed in v0.3.1. This method
  /// previously declared and decoded its response as [MediaParticipant],
  /// but `sdk_permission_handler.go`'s `RequestCamera` actually responds
  /// with a `PermissionRequestResponse` (a request record: `id`,
  /// `request_type`, `status`, ...), a differently-shaped object.
  Future<ApiResponse<PermissionRequest>> requestCamera(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _requestPermission(sessionId, participantId, 'request-camera', reason);

  /// Requests microphone access.
  ///
  /// Returns the created [PermissionRequest] — see [requestCamera]'s doc
  /// comment for why this is not a [MediaParticipant].
  Future<ApiResponse<PermissionRequest>> requestMicrophone(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _requestPermission(
          sessionId, participantId, 'request-microphone', reason);

  /// Requests screen-share access.
  ///
  /// Returns the created [PermissionRequest] — see [requestCamera]'s doc
  /// comment for why this is not a [MediaParticipant].
  Future<ApiResponse<PermissionRequest>> requestScreen(
    String sessionId,
    String participantId, {
    String? reason,
  }) =>
      _requestPermission(sessionId, participantId, 'request-screen', reason);

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

  /// Like [_request], but for the three actions that respond with a
  /// [PermissionRequest] instead of a [MediaParticipant]. See
  /// [requestCamera]'s doc comment for why these differ.
  Future<ApiResponse<PermissionRequest>> _requestPermission(
    String sessionId,
    String participantId,
    String action,
    String? reason,
  ) {
    return withMediaErrors(
      () => _client.post<PermissionRequest>(
        _participantPath(sessionId, participantId, action),
        body: reason == null ? null : <String, dynamic>{'reason': reason},
        decoder: _permissionRequest,
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

/// A publisher opens the signaling connection with `role: publisher` and
/// negotiates a WebRTC peer connection over it (docs/media.md §12
/// "Publisher Flow").
///
/// Exposed at `superso.media.publishers`.
///
/// This module owns the documented signaling transport
/// ([MediaSignalingConnection]) and the documented REST self-service actions
/// ([MediaModerationModule]/[MediaPermissionsModule]); it does not bundle a
/// WebRTC media-capture engine (no `RTCPeerConnection`, no camera/microphone
/// capture) — the host application supplies its own WebRTC plugin and wires
/// its offer/ICE-candidate calls through the connection [join] returns.
class MediaPublishersModule {
  /// Creates a publishers module bound to [client].
  MediaPublishersModule(this._client);

  final SupersoHttpClient _client;

  /// The signaling connection this module opens and reuses across [join]/
  /// [leave] calls.
  late final MediaSignalingConnection connection =
      MediaSignalingConnection(_client);

  /// Opens the signaling connection for [sessionId] with `role: publisher`.
  /// Returns the same [MediaSignalingConnection] as [connection].
  Future<MediaSignalingConnection> join(String sessionId) async {
    await connection.connect(sessionId, SignalingRole.publisher);
    return connection;
  }

  /// Closes the signaling connection.
  Future<void> leave() => connection.disconnect();
}

/// A subscriber opens the signaling connection with `role: subscriber` to
/// receive tracks from every publisher in the session (docs/media.md §13
/// "Subscriber Flow").
///
/// Exposed at `superso.media.subscribers`.
///
/// As with [MediaPublishersModule], this module owns the documented
/// signaling transport only — decoding received tracks into a renderable
/// view is left to the host application's own WebRTC plugin, which
/// subscribes to [MediaSignalingConnection.onOffer] /
/// [MediaSignalingConnection.onIceCandidate] on the returned connection.
class MediaSubscribersModule {
  /// Creates a subscribers module bound to [client].
  MediaSubscribersModule(this._client);

  final SupersoHttpClient _client;

  /// The signaling connection this module opens and reuses across [join]/
  /// [leave] calls.
  late final MediaSignalingConnection connection =
      MediaSignalingConnection(_client);

  /// Opens the signaling connection for [sessionId] with `role: subscriber`.
  /// Returns the same [MediaSignalingConnection] as [connection].
  Future<MediaSignalingConnection> join(String sessionId) async {
    await connection.connect(sessionId, SignalingRole.subscriber);
    return connection;
  }

  /// Closes the signaling connection.
  Future<void> leave() => connection.disconnect();
}

/// The classroom engine: attendance, speaker queue.
///
/// This class originally also carried Reactions, Polls, and Classroom Hand
/// Raise (`sendReaction`/`reactionSummary`/`createPoll`/`listPolls`/`vote`/
/// `pollResults`/`raiseHand`/`lowerHand`). Those six features (Classroom,
/// Polls, Whiteboard, Reactions, Chat, Webhooks) were removed from Media
/// Core — see docs/media.md. Attendance and Speaker Queue are separate,
/// still-supported features that happened to share this class name; it is
/// kept as-is (not renamed) to avoid an unrelated, unrequested
/// rename/refactor.
///
/// Exposed at `superso.media.classroom`.
class MediaClassroomModule {
  /// Creates a classroom module bound to [client].
  const MediaClassroomModule(this._client);

  final SupersoHttpClient _client;

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

}

/// Voice rooms.
///
/// Exposed at `superso.media.voiceRooms`.
///
/// The backend confirms an SDK REST subset of 8 routes
/// (`sdk_media_routes.go`): create, list, get, start, end, participants,
/// raise-hand, lower-hand.
///
/// `update`, `transferHost`, `promote`, `demote`, `mute`, `unmute`,
/// `acceptHand`, `rejectHand`, `addModerator`, and `removeModerator` are
/// documented under the Admin REST API only (`media_routes.go`, JWT auth) —
/// the SDK router does not register them, so they are intentionally not
/// implemented here to avoid shipping a method that would 404.
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

/// Breakout rooms and the waiting room.
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
/// // Publish: join the signaling socket, then drive your own WebRTC plugin
/// final connection = await superso.media.publishers.join(session.data.id);
/// connection.onReady.listen((ready) {
///   // configure your RTCPeerConnection with ready.iceServers, add camera/mic
///   // tracks, create an offer, then: connection.sendOffer(offer.sdp);
/// });
/// connection.onAnswer.listen((answer) { /* setRemoteDescription(answer) */ });
/// connection.onIceCandidate.listen((c) { /* addIceCandidate(c) */ });
/// ```
class MediaModule implements SdkModule, Disposable {
  /// Creates the media module bound to [client].
  MediaModule(this.client)
      : sessions = MediaSessionsModule(client),
        participants = MediaParticipantsModule(client),
        permissions = MediaPermissionsModule(client),
        moderation = MediaModerationModule(client),
        classroom = MediaClassroomModule(client),
        voiceRooms = MediaVoiceRoomsModule(client),
        rooms = MediaRoomsModule(client),
        publishers = MediaPublishersModule(client),
        subscribers = MediaSubscribersModule(client),
        websocket = MediaSignalingConnection(client),
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

  /// The classroom engine.
  final MediaClassroomModule classroom;

  /// Voice rooms.
  final MediaVoiceRoomsModule voiceRooms;

  /// Breakout rooms and the waiting room.
  final MediaRoomsModule rooms;

  /// Publisher-role raw WebRTC signaling (docs/media.md §12).
  final MediaPublishersModule publishers;

  /// Subscriber-role raw WebRTC signaling (docs/media.md §13).
  final MediaSubscribersModule subscribers;

  /// The raw WebRTC signaling transport (`GET /v1/media/signal`),
  /// independent of [publishers]/[subscribers] — open it directly with
  /// either role via [MediaSignalingConnection.connect].
  final MediaSignalingConnection websocket;

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
  Future<void> dispose() async {
    await Future.wait(<Future<void>>[
      disconnectAll(),
      websocket.dispose(),
      publishers.connection.dispose(),
      subscribers.connection.dispose(),
    ]);
  }
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

  @override
  String toString() => 'MediaEvent($event)';
}
