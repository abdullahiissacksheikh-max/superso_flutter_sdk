/// The Media module (Superso Media Engine v0.4.0): sessions, admission,
/// participants, self-service permissions, host moderation, voice rooms,
/// breakout rooms, waiting room, speaker queue, attendance, settings,
/// analytics, raw WebRTC signaling and realtime events.
///
/// Every route here is declared by `register()` in
/// `backend/internal/modules/media/api/routes.go` and documented in
/// `docs/internal/MEDIA_CANONICAL_CONTRACT.md` (§9.1 and the §14 addendum).
/// Auth legend used in the doc comments: R/W/D = API-key scope
/// read/write/delete, U = end-user access token, H = privileged participant
/// of the session, P = participant proof (the participant's token sent as
/// `X-Media-Participant-Token`, or the access token of that participant's
/// user).
library;

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../realtime/realtime_socket.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'media_errors.dart';
import 'media_signaling.dart';
import 'media_tokens.dart';
import 'media_types.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

Map<String, dynamic> _json(Object? data) =>
    (data is Map<String, dynamic>) ? data : const <String, dynamic>{};

List<Map<String, dynamic>> _jsonList(Object? value) => (value is List<dynamic>)
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];

MediaSession _session(Object? data) => MediaSession.fromJson(_json(data));

MediaParticipant _participant(Object? data) =>
    MediaParticipant.fromJson(_json(data));

MediaResource _resource(Object? data) => MediaResource.fromJson(_json(data));

MediaPage<MediaResource> _resourcePage(Object? data) =>
    MediaPage<MediaResource>.fromJson(_json(data), MediaResource.fromJson);

MediaParticipantList _participantList(Object? data) =>
    MediaParticipantList.fromJson(_json(data));

MediaSelfServiceResult _selfResult(Object? data) =>
    MediaSelfServiceResult.fromJson(_json(data));

MediaWaitingEntry _waitingEntry(Object? data) =>
    MediaWaitingEntry.fromJson(_json(data));

MediaBreakoutRoom _breakoutRoom(Object? data) =>
    MediaBreakoutRoom.fromJson(_json(data));

MediaSpeakerQueueEntry _speakerEntry(Object? data) =>
    MediaSpeakerQueueEntry.fromJson(_json(data));

void _ack(Object? _) {}

String _sessionPath(String sessionId, [String suffix = '']) =>
    '/media/sessions/${encodeSegment(sessionId)}$suffix';

String _sessionParticipantPath(
  String sessionId,
  String participantId, [
  String suffix = '',
]) =>
    _sessionPath(
      sessionId,
      '/participants/${encodeSegment(participantId)}$suffix',
    );

String _voicePath(String roomId, [String suffix = '']) =>
    '/media/voice-rooms/${encodeSegment(roomId)}$suffix';

/// Request options carrying a participant token, or `null` when there is no
/// token (the call then relies on the end-user access token, if any).
RequestOptions? _asParticipant(String? participantToken) =>
    participantToken == null || participantToken.isEmpty
        ? null
        : RequestOptions(
            headers: <String, String>{
              mediaParticipantTokenHeader: participantToken,
            },
          );

/// The participant-list filters of contract §14.
Map<String, Object?> _participantQuery({
  String? status,
  bool? publishersOnly,
  bool? isPublisher,
  String? voiceRole,
  int? limit,
  int? offset,
}) =>
    <String, Object?>{
      'status': status,
      'publishers_only': publishersOnly == true ? 'true' : null,
      'is_publisher': isPublisher,
      'voice_role': voiceRole,
      'limit': limit,
      'offset': offset,
    };

Map<String, Object?> _pageQuery(int? limit, int? offset) =>
    <String, Object?>{'limit': limit, 'offset': offset};

Map<String, dynamic>? _reasonBody(String? reason) =>
    reason == null ? null : <String, dynamic>{'reason': reason};

/// `POST …/join` shared by sessions and voice rooms. Stores the issued
/// participant token in [tokens].
Future<ApiResponse<MediaJoinResult>> _join(
  SupersoHttpClient client,
  MediaParticipantTokens tokens,
  String path,
  String sessionId, {
  String? displayName,
  String? password,
  String? joinToken,
  String? participantToken,
  bool resume = true,
  String? platform,
  String? sdkVersion,
  String? appVersion,
  String? networkType,
}) async {
  final resumeToken =
      participantToken ?? (resume ? tokens.forSession(sessionId) : null);
  final response = await withMediaErrors(
    () => client.post<MediaJoinResult>(
      path,
      body: <String, dynamic>{
        if (displayName != null) 'display_name': displayName,
        if (password != null) 'password': password,
        if (joinToken != null) 'join_token': joinToken,
        if (resumeToken != null && resumeToken.isNotEmpty)
          'participant_token': resumeToken,
        if (platform != null) 'platform': platform,
        if (sdkVersion != null) 'sdk_version': sdkVersion,
        if (appVersion != null) 'app_version': appVersion,
        if (networkType != null) 'network_type': networkType,
      },
      decoder: (data) => MediaJoinResult.fromJson(_json(data)),
    ),
  );
  final result = response.data;
  if (result.participantToken.isNotEmpty && result.participant.id.isNotEmpty) {
    tokens.store(
      sessionId: sessionId,
      participantId: result.participant.id,
      token: result.participantToken,
      expiresAt: result.participantTokenExpiresAt,
    );
  }
  return response;
}

// ── Sessions ────────────────────────────────────────────────────────────────

/// Session lifecycle, admission and the caller's own participant state.
///
/// Exposed at `superso.media.sessions`.
class MediaSessionsModule {
  /// Creates a sessions module.
  MediaSessionsModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// `POST /media/sessions` (W, U optional) — creates a session.
  ///
  /// With an end-user access token set, that user owns the session and
  /// becomes its host on first join. A trusted server without a user token
  /// may designate the owner with [hostUserId]. Omitted booleans fall back
  /// to project settings (`waiting_room_default`, `screen_share_default`) or
  /// the documented defaults.
  Future<ApiResponse<MediaSession>> create({
    required String title,
    String? description,
    String? type,
    String? visibility,
    String? password,
    String? sessionMode,
    int? maxPublishers,
    int? maxParticipants,
    bool? waitingRoom,
    bool? screenShareEnabled,
    bool? guestAllowed,
    bool? attendanceEnabled,
    bool? allowSelfUnmute,
    int? hostLeaveTimeoutSec,
    String? topic,
    String? scheduledAt,
    String? expiresAt,
    Map<String, dynamic>? metadata,
    String? hostUserId,
  }) {
    if (title.trim().isEmpty) {
      throw const ValidationError('Superso: a session title is required.');
    }
    return withMediaErrors(
      () => _client.post<MediaSession>(
        '/media/sessions',
        body: <String, dynamic>{
          'title': title,
          if (description != null) 'description': description,
          if (type != null) 'type': type,
          if (visibility != null) 'visibility': visibility,
          if (password != null) 'password': password,
          if (sessionMode != null) 'session_mode': sessionMode,
          if (maxPublishers != null) 'max_publishers': maxPublishers,
          if (maxParticipants != null) 'max_participants': maxParticipants,
          if (waitingRoom != null) 'waiting_room': waitingRoom,
          if (screenShareEnabled != null)
            'screen_share_enabled': screenShareEnabled,
          if (guestAllowed != null) 'guest_allowed': guestAllowed,
          if (attendanceEnabled != null)
            'attendance_enabled': attendanceEnabled,
          if (allowSelfUnmute != null) 'allow_self_unmute': allowSelfUnmute,
          if (hostLeaveTimeoutSec != null)
            'host_leave_timeout_sec': hostLeaveTimeoutSec,
          if (topic != null) 'topic': topic,
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
          if (expiresAt != null) 'expires_at': expiresAt,
          if (metadata != null) 'metadata': metadata,
          if (hostUserId != null) 'host_user_id': hostUserId,
        },
        decoder: _session,
      ),
    );
  }

  /// `GET /media/sessions` (R) — paginated; filters `status`, `voice_room`.
  Future<ApiResponse<MediaSessionList>> list({
    String? status,
    bool? voiceRoom,
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaSessionList>(
        '/media/sessions',
        options: RequestOptions(
          query: <String, Object?>{
            'status': status,
            'voice_room': voiceRoom,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => MediaSessionList.fromJson(_json(data)),
      ),
    );
  }

  /// `GET /media/sessions/by-join-token` (R) — `{session, valid}`.
  Future<ApiResponse<MediaJoinTokenResolution>> byJoinToken(String joinToken) {
    return withMediaErrors(
      () => _client.get<MediaJoinTokenResolution>(
        '/media/sessions/by-join-token',
        options: RequestOptions(
          query: <String, Object?>{'join_token': joinToken},
        ),
        decoder: (data) => MediaJoinTokenResolution.fromJson(_json(data)),
      ),
    );
  }

  /// `GET /media/sessions/:sessionId` (R).
  Future<ApiResponse<MediaSession>> get(String sessionId) {
    return withMediaErrors(
      () => _client.get<MediaSession>(
        _sessionPath(sessionId),
        decoder: _session,
      ),
    );
  }

  /// `PATCH /media/sessions/:sessionId` (W, U, H) — partial update. Only the
  /// fields you pass are sent. Emits `session_updated`.
  Future<ApiResponse<MediaSession>> update(
    String sessionId, {
    String? title,
    String? description,
    String? topic,
    bool? roomLocked,
    bool? waitingRoom,
    bool? guestAllowed,
    bool? screenShareEnabled,
    bool? allowSelfUnmute,
    int? maxPublishers,
    int? maxParticipants,
    int? hostLeaveTimeoutSec,
  }) {
    return withMediaErrors(
      () => _client.patch<MediaSession>(
        _sessionPath(sessionId),
        body: <String, dynamic>{
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (topic != null) 'topic': topic,
          if (roomLocked != null) 'room_locked': roomLocked,
          if (waitingRoom != null) 'waiting_room': waitingRoom,
          if (guestAllowed != null) 'guest_allowed': guestAllowed,
          if (screenShareEnabled != null)
            'screen_share_enabled': screenShareEnabled,
          if (allowSelfUnmute != null) 'allow_self_unmute': allowSelfUnmute,
          if (maxPublishers != null) 'max_publishers': maxPublishers,
          if (maxParticipants != null) 'max_participants': maxParticipants,
          if (hostLeaveTimeoutSec != null)
            'host_leave_timeout_sec': hostLeaveTimeoutSec,
        },
        decoder: _session,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/start` (W; the owner or a privileged
  /// participant's access token when the session has an owner).
  Future<ApiResponse<MediaSession>> start(String sessionId) {
    return withMediaErrors(
      () => _client.post<MediaSession>(
        _sessionPath(sessionId, '/start'),
        decoder: _session,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/end` (W, U, H).
  Future<ApiResponse<MediaSession>> end(String sessionId) {
    return withMediaErrors(
      () => _client.post<MediaSession>(
        _sessionPath(sessionId, '/end'),
        decoder: _session,
      ),
    );
  }

  /// `DELETE /media/sessions/:sessionId` (W, U, H) — cancels the session and
  /// returns it with status `cancelled`.
  Future<ApiResponse<MediaSession>> cancel(String sessionId) {
    return withMediaErrors(
      () => _client.delete<MediaSession>(
        _sessionPath(sessionId),
        decoder: _session,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/join` (W, U optional) — the single
  /// admission gate.
  ///
  /// The returned participant token is stored in `superso.media.tokens` and
  /// used automatically by every self-service call and by signaling. When
  /// [participantToken] is omitted and [resume] is true, a token previously
  /// stored for this session is sent so a guest resumes the same row.
  /// [MediaJoinResult.admission] is `waiting` when the session has a
  /// waiting room and the caller is not privileged.
  Future<ApiResponse<MediaJoinResult>> join(
    String sessionId, {
    String? displayName,
    String? password,
    String? joinToken,
    String? participantToken,
    bool resume = true,
    String? platform,
    String? sdkVersion,
    String? appVersion,
    String? networkType,
  }) =>
      _join(
        _client,
        _tokens,
        _sessionPath(sessionId, '/join'),
        sessionId,
        displayName: displayName,
        password: password,
        joinToken: joinToken,
        participantToken: participantToken,
        resume: resume,
        platform: platform,
        sdkVersion: sdkVersion,
        appVersion: appVersion,
        networkType: networkType,
      );

  /// `GET /media/sessions/:sessionId/participants` (R) — paginated; filters
  /// `status`, `publishers_only`, `is_publisher`, `voice_role`.
  Future<ApiResponse<MediaParticipantList>> participants(
    String sessionId, {
    String? status,
    bool? publishersOnly,
    bool? isPublisher,
    String? voiceRole,
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaParticipantList>(
        _sessionPath(sessionId, '/participants'),
        options: RequestOptions(
          query: _participantQuery(
            status: status,
            publishersOnly: publishersOnly,
            isPublisher: isPublisher,
            voiceRole: voiceRole,
            limit: limit,
            offset: offset,
          ),
        ),
        decoder: _participantList,
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/participants/:participantId` (R).
  Future<ApiResponse<MediaParticipant>> getParticipant(
    String sessionId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.get<MediaParticipant>(
        _sessionParticipantPath(sessionId, participantId),
        decoder: _participant,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/participants/:participantId/leave`
  /// (W, P) — immediate leave; every signaling socket of the participant is
  /// closed with `MEDIA_LEFT` (never reconnected).
  Future<ApiResponse<void>> leave(
    String sessionId,
    String participantId, {
    String? participantToken,
  }) {
    return withMediaErrors(
      () => _client.post<void>(
        _sessionParticipantPath(sessionId, participantId, '/leave'),
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: _ack,
      ),
    );
  }

  /// `PATCH /media/sessions/:sessionId/participants/:participantId/media-state`
  /// (W, P) — reports the client's camera/microphone/screen state. Enabling
  /// a source forbidden by server policy fails with `MEDIA_FORBIDDEN`;
  /// enabling the microphone while muted (and allowed) self-unmutes.
  Future<ApiResponse<MediaParticipant>> updateMediaState(
    String sessionId,
    String participantId, {
    bool? cameraEnabled,
    bool? microphoneEnabled,
    bool? screenShareActive,
    String? participantToken,
  }) {
    return withMediaErrors(
      () => _client.patch<MediaParticipant>(
        _sessionParticipantPath(sessionId, participantId, '/media-state'),
        body: <String, dynamic>{
          if (cameraEnabled != null) 'camera_enabled': cameraEnabled,
          if (microphoneEnabled != null)
            'microphone_enabled': microphoneEnabled,
          if (screenShareActive != null)
            'screen_share_active': screenShareActive,
        },
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: _participant,
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/speakers` (R) — `{speakers, count}`,
  /// decoded as the list of currently speaking participants.
  Future<ApiResponse<List<MediaParticipant>>> speakers(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaParticipant>>(
        _sessionPath(sessionId, '/speakers'),
        decoder: (data) => _jsonList(_json(data)['speakers'])
            .map(MediaParticipant.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/timeline` (R) — paginated session event
  /// log.
  Future<ApiResponse<MediaPage<MediaResource>>> timeline(
    String sessionId, {
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaPage<MediaResource>>(
        _sessionPath(sessionId, '/timeline'),
        options: RequestOptions(query: _pageQuery(limit, offset)),
        decoder: _resourcePage,
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/tracks` (R) — paginated persisted
  /// tracks.
  Future<ApiResponse<MediaPage<MediaResource>>> tracks(
    String sessionId, {
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaPage<MediaResource>>(
        _sessionPath(sessionId, '/tracks'),
        options: RequestOptions(query: _pageQuery(limit, offset)),
        decoder: _resourcePage,
      ),
    );
  }
}

// ── Participants (project-level) ────────────────────────────────────────────

/// Project-wide participant lookup and telemetry.
///
/// Exposed at `superso.media.participants`.
class MediaParticipantsModule {
  /// Creates a participants module.
  MediaParticipantsModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// `GET /media/participants` (R) — every participant of the project,
  /// paginated; filters `status`, `publishers_only`, `is_publisher`,
  /// `voice_role`.
  Future<ApiResponse<MediaParticipantList>> list({
    String? status,
    bool? publishersOnly,
    bool? isPublisher,
    String? voiceRole,
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaParticipantList>(
        '/media/participants',
        options: RequestOptions(
          query: _participantQuery(
            status: status,
            publishersOnly: publishersOnly,
            isPublisher: isPublisher,
            voiceRole: voiceRole,
            limit: limit,
            offset: offset,
          ),
        ),
        decoder: _participantList,
      ),
    );
  }

  /// `GET /media/participants/:participantId` (R) — `{participant, tracks}`.
  Future<ApiResponse<MediaParticipantDetail>> get(String participantId) {
    return withMediaErrors(
      () => _client.get<MediaParticipantDetail>(
        '/media/participants/${encodeSegment(participantId)}',
        decoder: (data) => MediaParticipantDetail.fromJson(_json(data)),
      ),
    );
  }

  /// `PATCH /media/participants/:participantId/telemetry` (W, P) — reports
  /// connection quality. Only the participant itself may report.
  ///
  /// Resolves to the updated participant, or `null` when the project has
  /// `analytics_enabled = false` (the server answers 202 and stores
  /// nothing).
  Future<ApiResponse<MediaParticipant?>> pushTelemetry(
    String participantId, {
    int? bitrateKbps,
    double? packetLossPct,
    int? rttMs,
    double? jitterMs,
    String? networkType,
    String? iceState,
    String? dtlsState,
    String? participantToken,
  }) {
    return withMediaErrors(
      () => _client.patch<MediaParticipant?>(
        '/media/participants/${encodeSegment(participantId)}/telemetry',
        body: <String, dynamic>{
          if (bitrateKbps != null) 'bitrate_kbps': bitrateKbps,
          if (packetLossPct != null) 'packet_loss_pct': packetLossPct,
          if (rttMs != null) 'rtt_ms': rttMs,
          if (jitterMs != null) 'jitter_ms': jitterMs,
          if (networkType != null) 'network_type': networkType,
          if (iceState != null) 'ice_state': iceState,
          if (dtlsState != null) 'dtls_state': dtlsState,
        },
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: (data) =>
            (data is Map<String, dynamic>) ? MediaParticipant.fromJson(data) : null,
      ),
    );
  }
}

// ── Self-service permissions ────────────────────────────────────────────────

/// Participant self-service (stage and camera/microphone/screen requests)
/// plus the host views of pending requests and the permission audit.
///
/// Exposed at `superso.media.permissions`. Self-service calls are `W, P`:
/// the participant's stored token is sent as `X-Media-Participant-Token`
/// automatically (override with `participantToken`). Every self-service call
/// resolves to `{participant, request?}`.
class MediaPermissionsModule {
  /// Creates a permissions module.
  MediaPermissionsModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// `POST …/participants/:participantId/request-stage` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> requestStage(
    String sessionId,
    String participantId, {
    String? reason,
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'request-stage',
          _reasonBody(reason), participantToken);

  /// `POST …/participants/:participantId/cancel-stage-request` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> cancelStageRequest(
    String sessionId,
    String participantId, {
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'cancel-stage-request', null,
          participantToken);

  /// `POST …/participants/:participantId/accept-stage-invite` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> acceptStageInvite(
    String sessionId,
    String participantId, {
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'accept-stage-invite', null,
          participantToken);

  /// `POST …/participants/:participantId/decline-stage-invite` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> declineStageInvite(
    String sessionId,
    String participantId, {
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'decline-stage-invite', null,
          participantToken);

  /// `POST …/participants/:participantId/request-camera` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> requestCamera(
    String sessionId,
    String participantId, {
    String? reason,
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'request-camera', _reasonBody(reason),
          participantToken);

  /// `POST …/participants/:participantId/request-microphone` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> requestMicrophone(
    String sessionId,
    String participantId, {
    String? reason,
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'request-microphone',
          _reasonBody(reason), participantToken);

  /// `POST …/participants/:participantId/request-screen` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> requestScreen(
    String sessionId,
    String participantId, {
    String? reason,
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'request-screen', _reasonBody(reason),
          participantToken);

  /// `POST …/participants/:participantId/cancel-request` (W, P) — body
  /// `{request_type}` (`camera|microphone|screen|stage`). `speaking` only
  /// appears on legacy rows and is rejected with an [ArgumentError].
  Future<ApiResponse<MediaSelfServiceResult>> cancelRequest(
    String sessionId,
    String participantId,
    MediaRequestType requestType, {
    String? participantToken,
  }) {
    if (requestType == MediaRequestType.speaking) {
      throw ArgumentError.value(requestType, 'requestType',
          'must be camera, microphone, screen or stage');
    }
    return _self(
      sessionId,
      participantId,
      'cancel-request',
      <String, dynamic>{'request_type': requestType.wireValue},
      participantToken,
    );
  }

  /// `POST …/participants/:participantId/stop-screen-share` (W, P).
  Future<ApiResponse<MediaSelfServiceResult>> stopScreenShare(
    String sessionId,
    String participantId, {
    String? participantToken,
  }) =>
      _self(sessionId, participantId, 'stop-screen-share', null,
          participantToken);

  /// `GET /media/sessions/:sessionId/permission-requests` (R, U, H) —
  /// `{requests, total}`, decoded as the list of pending requests.
  Future<ApiResponse<List<PermissionRequest>>> listRequests(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<PermissionRequest>>(
        _sessionPath(sessionId, '/permission-requests'),
        decoder: (data) => _jsonList(_json(data)['requests'])
            .map(PermissionRequest.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/permission-audit` (R, U, H) —
  /// paginated before/after permission snapshots.
  Future<ApiResponse<MediaPage<MediaResource>>> audit(
    String sessionId, {
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaPage<MediaResource>>(
        _sessionPath(sessionId, '/permission-audit'),
        options: RequestOptions(query: _pageQuery(limit, offset)),
        decoder: _resourcePage,
      ),
    );
  }

  Future<ApiResponse<MediaSelfServiceResult>> _self(
    String sessionId,
    String participantId,
    String action,
    Map<String, dynamic>? body,
    String? participantToken,
  ) {
    return withMediaErrors(
      () => _client.post<MediaSelfServiceResult>(
        _sessionParticipantPath(sessionId, participantId, '/$action'),
        body: body,
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: _selfResult,
      ),
    );
  }
}

// ── Host moderation ─────────────────────────────────────────────────────────

/// Host moderation (`W, U, H`).
///
/// Exposed at `superso.media.moderation`. **Every method requires an
/// end-user access token** whose user is a privileged participant (owner,
/// teacher, co-host, assistant teacher or moderator) of the session, and the
/// caller must strictly outrank the target. Failures surface as
/// [HostAuthorizationError] (`MEDIA_NOT_HOST` / `MEDIA_INSUFFICIENT_RANK`);
/// `MEDIA_MODERATION_DISABLED` when the project disabled SDK moderation.
/// Every action resolves to the updated participant.
class MediaModerationModule {
  /// Creates a moderation module.
  const MediaModerationModule(this._client);

  final SupersoHttpClient _client;

  /// `approve-camera`.
  Future<ApiResponse<MediaParticipant>> approveCamera(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-camera', reason);

  /// `reject-camera`.
  Future<ApiResponse<MediaParticipant>> rejectCamera(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-camera', reason);

  /// `revoke-camera`.
  Future<ApiResponse<MediaParticipant>> revokeCamera(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'revoke-camera', reason);

  /// `approve-microphone`.
  Future<ApiResponse<MediaParticipant>> approveMicrophone(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-microphone', reason);

  /// `reject-microphone`.
  Future<ApiResponse<MediaParticipant>> rejectMicrophone(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-microphone', reason);

  /// `revoke-microphone`.
  Future<ApiResponse<MediaParticipant>> revokeMicrophone(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'revoke-microphone', reason);

  /// `approve-screen`.
  Future<ApiResponse<MediaParticipant>> approveScreen(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-screen', reason);

  /// `reject-screen`.
  Future<ApiResponse<MediaParticipant>> rejectScreen(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-screen', reason);

  /// `revoke-screen`.
  Future<ApiResponse<MediaParticipant>> revokeScreen(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'revoke-screen', reason);

  /// `mute`.
  Future<ApiResponse<MediaParticipant>> mute(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'mute', reason);

  /// `unmute` (fails with `MEDIA_INVALID_STATE` while force-muted).
  Future<ApiResponse<MediaParticipant>> unmute(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'unmute', reason);

  /// `force-mute` — the participant cannot self-unmute until
  /// [clearForceMute].
  Future<ApiResponse<MediaParticipant>> forceMute(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'force-mute', reason);

  /// `clear-force-mute`.
  Future<ApiResponse<MediaParticipant>> clearForceMute(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'clear-force-mute', reason);

  /// `hide-video`.
  Future<ApiResponse<MediaParticipant>> hideVideo(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'hide-video', reason);

  /// `show-video`.
  Future<ApiResponse<MediaParticipant>> showVideo(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'show-video', reason);

  /// `pin`.
  Future<ApiResponse<MediaParticipant>> pin(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'pin', reason);

  /// `unpin`.
  Future<ApiResponse<MediaParticipant>> unpin(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'unpin', reason);

  /// `spotlight`.
  Future<ApiResponse<MediaParticipant>> spotlight(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'spotlight', reason);

  /// `unspotlight`.
  Future<ApiResponse<MediaParticipant>> unspotlight(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'unspotlight', reason);

  /// `approve-stage` — approves a pending stage request.
  Future<ApiResponse<MediaParticipant>> approveStageRequest(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'approve-stage', reason);

  /// `reject-stage` — rejects a pending stage request.
  Future<ApiResponse<MediaParticipant>> rejectStageRequest(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'reject-stage', reason);

  /// `invite-to-stage`.
  Future<ApiResponse<MediaParticipant>> inviteToStage(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'invite-to-stage', reason);

  /// `remove-from-stage`.
  Future<ApiResponse<MediaParticipant>> removeFromStage(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'remove-from-stage', reason);

  /// `promote` — to publisher.
  Future<ApiResponse<MediaParticipant>> promote(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'promote', reason);

  /// `demote` — to viewer (publisher sockets close with
  /// `MEDIA_PUBLISH_REVOKED`).
  Future<ApiResponse<MediaParticipant>> demote(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'demote', reason);

  /// `kick` — every socket closes with `MEDIA_KICKED`.
  Future<ApiResponse<MediaParticipant>> kick(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'kick', reason);

  /// `ban` — sticky: the same user can never rejoin (`MEDIA_BANNED`).
  Future<ApiResponse<MediaParticipant>> ban(
          String sessionId, String participantId, {String? reason}) =>
      _act(sessionId, participantId, 'ban', reason);

  /// `assign-role` — body `{role}`. Only [ClassroomRole.assignable] roles are
  /// sent; anything else throws a [ValidationError] before any request. The
  /// server additionally requires the role to rank strictly below the
  /// caller's own (`MEDIA_INSUFFICIENT_RANK`).
  Future<ApiResponse<MediaParticipant>> assignRole(
    String sessionId,
    String participantId,
    ClassroomRole role, {
    String? reason,
  }) {
    if (!ClassroomRole.assignable.contains(role)) {
      throw ValidationError(
        'Superso: `${role.wireValue}` cannot be assigned. Assignable roles '
        'are: ${ClassroomRole.assignable.map((r) => r.wireValue).join(', ')}.',
      );
    }
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _sessionParticipantPath(sessionId, participantId, '/assign-role'),
        body: <String, dynamic>{
          'role': role.wireValue,
          if (reason != null) 'reason': reason,
        },
        decoder: _participant,
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
        _sessionParticipantPath(sessionId, participantId, '/$action'),
        body: _reasonBody(reason),
        decoder: _participant,
      ),
    );
  }
}

// ── Voice rooms ─────────────────────────────────────────────────────────────

/// Voice rooms (audio sessions with `voice_room = true`).
///
/// Exposed at `superso.media.voiceRooms`. A voice room id is a session id:
/// every session-scoped call (moderation, waiting room, speaker queue, ...)
/// accepts it too.
class MediaVoiceRoomsModule {
  /// Creates a voice-rooms module.
  MediaVoiceRoomsModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// `GET /media/voice-rooms` (R) — paginated; filter `status`.
  Future<ApiResponse<MediaSessionList>> list({
    String? status,
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaSessionList>(
        '/media/voice-rooms',
        options: RequestOptions(
          query: <String, Object?>{
            'status': status,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => MediaSessionList.fromJson(_json(data)),
      ),
    );
  }

  /// `POST /media/voice-rooms` (W, U optional).
  Future<ApiResponse<MediaSession>> create({
    required String title,
    String? description,
    String? visibility,
    String? password,
    String? roomType,
    bool? allowListenersToSpeak,
    bool? requireHandRaise,
    int? maxParticipants,
    bool? waitingRoom,
    bool? guestAllowed,
    String? topic,
    String? scheduledAt,
    String? expiresAt,
    String? hostUserId,
  }) {
    if (title.trim().isEmpty) {
      throw const ValidationError('Superso: a voice room title is required.');
    }
    return withMediaErrors(
      () => _client.post<MediaSession>(
        '/media/voice-rooms',
        body: <String, dynamic>{
          'title': title,
          if (description != null) 'description': description,
          if (visibility != null) 'visibility': visibility,
          if (password != null) 'password': password,
          if (roomType != null) 'room_type': roomType,
          if (allowListenersToSpeak != null)
            'allow_listeners_to_speak': allowListenersToSpeak,
          if (requireHandRaise != null) 'require_hand_raise': requireHandRaise,
          if (maxParticipants != null) 'max_participants': maxParticipants,
          if (waitingRoom != null) 'waiting_room': waitingRoom,
          if (guestAllowed != null) 'guest_allowed': guestAllowed,
          if (topic != null) 'topic': topic,
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
          if (expiresAt != null) 'expires_at': expiresAt,
          if (hostUserId != null) 'host_user_id': hostUserId,
        },
        decoder: _session,
      ),
    );
  }

  /// `GET /media/voice-rooms/:roomId` (R).
  Future<ApiResponse<MediaSession>> get(String roomId) {
    return withMediaErrors(
      () => _client.get<MediaSession>(_voicePath(roomId), decoder: _session),
    );
  }

  /// `PATCH /media/voice-rooms/:roomId` (W, U, H) — partial update. Emits
  /// `voice_room.updated`.
  Future<ApiResponse<MediaSession>> update(
    String roomId, {
    String? title,
    String? description,
    String? topic,
    String? roomType,
    bool? allowListenersToSpeak,
    bool? requireHandRaise,
    bool? roomLocked,
  }) {
    return withMediaErrors(
      () => _client.patch<MediaSession>(
        _voicePath(roomId),
        body: <String, dynamic>{
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (topic != null) 'topic': topic,
          if (roomType != null) 'room_type': roomType,
          if (allowListenersToSpeak != null)
            'allow_listeners_to_speak': allowListenersToSpeak,
          if (requireHandRaise != null) 'require_hand_raise': requireHandRaise,
          if (roomLocked != null) 'room_locked': roomLocked,
        },
        decoder: _session,
      ),
    );
  }

  /// `POST /media/voice-rooms/:roomId/start` (W, as session start).
  Future<ApiResponse<MediaSession>> start(String roomId) {
    return withMediaErrors(
      () => _client.post<MediaSession>(
        _voicePath(roomId, '/start'),
        decoder: _session,
      ),
    );
  }

  /// `POST /media/voice-rooms/:roomId/end` (W, U, H).
  Future<ApiResponse<MediaSession>> end(String roomId) {
    return withMediaErrors(
      () => _client.post<MediaSession>(
        _voicePath(roomId, '/end'),
        decoder: _session,
      ),
    );
  }

  /// `POST /media/voice-rooms/:roomId/transfer-host` (W, U, H owner) — body
  /// `{participant_id}`; resolves to the new host.
  Future<ApiResponse<MediaParticipant>> transferHost(
    String roomId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _voicePath(roomId, '/transfer-host'),
        body: <String, dynamic>{'participant_id': participantId},
        decoder: _participant,
      ),
    );
  }

  /// `POST /media/voice-rooms/:roomId/join` (W, U optional) — same admission
  /// gate as `sessions.join`; the participant token is stored.
  Future<ApiResponse<MediaJoinResult>> join(
    String roomId, {
    String? displayName,
    String? password,
    String? joinToken,
    String? participantToken,
    bool resume = true,
    String? platform,
    String? sdkVersion,
    String? appVersion,
    String? networkType,
  }) =>
      _join(
        _client,
        _tokens,
        _voicePath(roomId, '/join'),
        roomId,
        displayName: displayName,
        password: password,
        joinToken: joinToken,
        participantToken: participantToken,
        resume: resume,
        platform: platform,
        sdkVersion: sdkVersion,
        appVersion: appVersion,
        networkType: networkType,
      );

  /// `GET /media/voice-rooms/:roomId/participants` (R) — paginated; filters
  /// `status`, `publishers_only`, `is_publisher`, `voice_role`.
  Future<ApiResponse<MediaParticipantList>> participants(
    String roomId, {
    String? status,
    bool? publishersOnly,
    bool? isPublisher,
    String? voiceRole,
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaParticipantList>(
        _voicePath(roomId, '/participants'),
        options: RequestOptions(
          query: _participantQuery(
            status: status,
            publishersOnly: publishersOnly,
            isPublisher: isPublisher,
            voiceRole: voiceRole,
            limit: limit,
            offset: offset,
          ),
        ),
        decoder: _participantList,
      ),
    );
  }

  /// `POST …/participants/:participantId/raise-hand` (W, P).
  Future<ApiResponse<MediaParticipant>> raiseHand(
    String roomId,
    String participantId, {
    String? participantToken,
  }) =>
      _self(roomId, participantId, 'raise-hand', participantToken);

  /// `POST …/participants/:participantId/lower-hand` (W, P).
  Future<ApiResponse<MediaParticipant>> lowerHand(
    String roomId,
    String participantId, {
    String? participantToken,
  }) =>
      _self(roomId, participantId, 'lower-hand', participantToken);

  /// `promote` (W, U, H) — listener → speaker.
  Future<ApiResponse<MediaParticipant>> promote(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'promote');

  /// `demote` (W, U, H) — speaker → listener.
  Future<ApiResponse<MediaParticipant>> demote(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'demote');

  /// `mute` (W, U, H).
  Future<ApiResponse<MediaParticipant>> mute(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'mute');

  /// `unmute` (W, U, H).
  Future<ApiResponse<MediaParticipant>> unmute(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'unmute');

  /// `accept-hand` (W, U, H).
  Future<ApiResponse<MediaParticipant>> acceptHand(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'accept-hand');

  /// `reject-hand` (W, U, H).
  Future<ApiResponse<MediaParticipant>> rejectHand(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'reject-hand');

  /// `add-moderator` (W, U, H).
  Future<ApiResponse<MediaParticipant>> addModerator(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'add-moderator');

  /// `remove-moderator` (W, U, H).
  Future<ApiResponse<MediaParticipant>> removeModerator(
          String roomId, String participantId) =>
      _host(roomId, participantId, 'remove-moderator');

  Future<ApiResponse<MediaParticipant>> _self(
    String roomId,
    String participantId,
    String action,
    String? participantToken,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _voicePath(roomId, '/participants/${encodeSegment(participantId)}/$action'),
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: _participant,
      ),
    );
  }

  Future<ApiResponse<MediaParticipant>> _host(
    String roomId,
    String participantId,
    String action,
  ) {
    return withMediaErrors(
      () => _client.post<MediaParticipant>(
        _voicePath(roomId, '/participants/${encodeSegment(participantId)}/$action'),
        decoder: _participant,
      ),
    );
  }
}

// ── Breakout rooms ──────────────────────────────────────────────────────────

/// Breakout rooms.
///
/// Exposed at `superso.media.breakoutRooms`. A moved participant's sockets
/// close with `MEDIA_BREAKOUT_MOVED` (reason = room id) and the SDK's
/// signaling connection reconnects into the room automatically; closing a
/// room sends `MEDIA_BREAKOUT_CLOSED` and reconnects to the main room.
class MediaBreakoutRoomsModule {
  /// Creates a breakout-rooms module.
  const MediaBreakoutRoomsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /media/sessions/:sessionId/breakout-rooms` (R) — `{rooms, total}`,
  /// decoded as the list of rooms (each with `participant_ids`).
  Future<ApiResponse<List<MediaBreakoutRoom>>> list(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaBreakoutRoom>>(
        _sessionPath(sessionId, '/breakout-rooms'),
        decoder: (data) => _jsonList(_json(data)['rooms'])
            .map(MediaBreakoutRoom.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/breakout-rooms/:roomId` (R).
  Future<ApiResponse<MediaBreakoutRoom>> get(String sessionId, String roomId) {
    return withMediaErrors(
      () => _client.get<MediaBreakoutRoom>(
        _sessionPath(sessionId, '/breakout-rooms/${encodeSegment(roomId)}'),
        decoder: _breakoutRoom,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/breakout-rooms` (W, U, H) — `{title}`.
  Future<ApiResponse<MediaBreakoutRoom>> create(
    String sessionId, {
    required String title,
  }) {
    return withMediaErrors(
      () => _client.post<MediaBreakoutRoom>(
        _sessionPath(sessionId, '/breakout-rooms'),
        body: <String, dynamic>{'title': title},
        decoder: _breakoutRoom,
      ),
    );
  }

  /// `PATCH /media/sessions/:sessionId/breakout-rooms/:roomId` (W, U, H) —
  /// renames the room.
  Future<ApiResponse<MediaBreakoutRoom>> update(
    String sessionId,
    String roomId, {
    required String title,
  }) {
    return withMediaErrors(
      () => _client.patch<MediaBreakoutRoom>(
        _sessionPath(sessionId, '/breakout-rooms/${encodeSegment(roomId)}'),
        body: <String, dynamic>{'title': title},
        decoder: _breakoutRoom,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/breakout-rooms/:roomId/close`
  /// (W, U, H) — members return to the main session.
  Future<ApiResponse<void>> close(String sessionId, String roomId) {
    return withMediaErrors(
      () => _client.post<void>(
        _sessionPath(
          sessionId,
          '/breakout-rooms/${encodeSegment(roomId)}/close',
        ),
        decoder: _ack,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/breakout-rooms/close-all` (W, U, H) —
  /// resolves to the number of rooms closed (`{closed}`).
  Future<ApiResponse<int>> closeAll(String sessionId) {
    return withMediaErrors(
      () => _client.post<int>(
        _sessionPath(sessionId, '/breakout-rooms/close-all'),
        decoder: (data) => (_json(data)['closed'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// `DELETE /media/sessions/:sessionId/breakout-rooms/:roomId` (W, U, H).
  Future<ApiResponse<void>> delete(String sessionId, String roomId) {
    return withMediaErrors(
      () => _client.delete<void>(
        _sessionPath(sessionId, '/breakout-rooms/${encodeSegment(roomId)}'),
        decoder: _ack,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/breakout-rooms/:roomId/participants/:participantId/move`
  /// (W, U, H) — resolves to the assignment row.
  Future<ApiResponse<MediaResource>> move(
    String sessionId,
    String roomId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.post<MediaResource>(
        _sessionPath(
          sessionId,
          '/breakout-rooms/${encodeSegment(roomId)}'
          '/participants/${encodeSegment(participantId)}/move',
        ),
        decoder: _resource,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/breakout-rooms/participants/:participantId/return`
  /// (W, U, H) — returns one participant to the main session.
  Future<ApiResponse<void>> returnToMain(
    String sessionId,
    String participantId,
  ) {
    return withMediaErrors(
      () => _client.post<void>(
        _sessionPath(
          sessionId,
          '/breakout-rooms/participants/${encodeSegment(participantId)}/return',
        ),
        decoder: _ack,
      ),
    );
  }
}

// ── Waiting room ────────────────────────────────────────────────────────────

/// The waiting room. Participants enter it through `sessions.join`
/// (`admission = waiting`); there is no separate enqueue call.
///
/// Exposed at `superso.media.waitingRoom`.
class MediaWaitingRoomModule {
  /// Creates a waiting-room module.
  MediaWaitingRoomModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// `GET /media/sessions/:sessionId/waiting-room/queue` (R, U, H) —
  /// `{entries, total}`, decoded as the ordered entries (each embeds its
  /// participant).
  Future<ApiResponse<List<MediaWaitingEntry>>> queue(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaWaitingEntry>>(
        _sessionPath(sessionId, '/waiting-room/queue'),
        decoder: (data) => _jsonList(_json(data)['entries'])
            .map(MediaWaitingEntry.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/waiting-room/:entryId` (R; P for the
  /// entry's own participant, or U + H) — poll your own admission status.
  /// Sends the session's stored participant token unless [participantToken]
  /// is given.
  Future<ApiResponse<MediaWaitingEntry>> status(
    String sessionId,
    String entryId, {
    String? participantToken,
  }) {
    return withMediaErrors(
      () => _client.get<MediaWaitingEntry>(
        _sessionPath(sessionId, '/waiting-room/${encodeSegment(entryId)}'),
        options: _asParticipant(
          participantToken ?? _tokens.forSession(sessionId),
        ),
        decoder: _waitingEntry,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/waiting-room/:entryId/admit` (W, U, H).
  Future<ApiResponse<MediaWaitingEntry>> admit(
    String sessionId,
    String entryId, {
    String? reason,
  }) =>
      _decide(sessionId, entryId, 'admit', reason);

  /// `POST /media/sessions/:sessionId/waiting-room/:entryId/reject`
  /// (W, U, H).
  Future<ApiResponse<MediaWaitingEntry>> reject(
    String sessionId,
    String entryId, {
    String? reason,
  }) =>
      _decide(sessionId, entryId, 'reject', reason);

  /// `POST /media/sessions/:sessionId/waiting-room/:entryId/ban` (W, U, H) —
  /// sticky ban of the entry's participant.
  Future<ApiResponse<MediaWaitingEntry>> ban(
    String sessionId,
    String entryId, {
    String? reason,
  }) =>
      _decide(sessionId, entryId, 'ban', reason);

  /// `POST /media/sessions/:sessionId/waiting-room/admit-all` (W, U, H) —
  /// resolves to the number admitted (`{admitted}`).
  Future<ApiResponse<int>> admitAll(String sessionId) {
    return withMediaErrors(
      () => _client.post<int>(
        _sessionPath(sessionId, '/waiting-room/admit-all'),
        decoder: (data) => (_json(data)['admitted'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Future<ApiResponse<MediaWaitingEntry>> _decide(
    String sessionId,
    String entryId,
    String decision,
    String? reason,
  ) {
    return withMediaErrors(
      () => _client.post<MediaWaitingEntry>(
        _sessionPath(
          sessionId,
          '/waiting-room/${encodeSegment(entryId)}/$decision',
        ),
        body: _reasonBody(reason),
        decoder: _waitingEntry,
      ),
    );
  }
}

// ── Speaker queue ───────────────────────────────────────────────────────────

/// The speaker queue.
///
/// Exposed at `superso.media.speakerQueue`.
class MediaSpeakerQueueModule {
  /// Creates a speaker-queue module.
  MediaSpeakerQueueModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// `GET /media/sessions/:sessionId/speaker-queue` (R) —
  /// `{session_id, entries, total}`.
  Future<ApiResponse<MediaSpeakerQueue>> list(String sessionId) {
    return withMediaErrors(
      () => _client.get<MediaSpeakerQueue>(
        _sessionPath(sessionId, '/speaker-queue'),
        decoder: (data) => MediaSpeakerQueue.fromJson(_json(data)),
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/speaker-queue` (W, P) — body
  /// `{participant_id, reason?}`; you can only enqueue yourself.
  Future<ApiResponse<MediaSpeakerQueueEntry>> join(
    String sessionId,
    String participantId, {
    String? reason,
    String? participantToken,
  }) {
    return withMediaErrors(
      () => _client.post<MediaSpeakerQueueEntry>(
        _sessionPath(sessionId, '/speaker-queue'),
        body: <String, dynamic>{
          'participant_id': participantId,
          if (reason != null) 'reason': reason,
        },
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: _speakerEntry,
      ),
    );
  }

  /// `DELETE /media/sessions/:sessionId/speaker-queue/:participantId`
  /// (W, P or U + H) — the participant leaves, or a host removes them.
  Future<ApiResponse<void>> leave(
    String sessionId,
    String participantId, {
    String? participantToken,
  }) {
    return withMediaErrors(
      () => _client.delete<void>(
        _sessionPath(
          sessionId,
          '/speaker-queue/${encodeSegment(participantId)}',
        ),
        options: _asParticipant(
          participantToken ?? _tokens.forParticipant(participantId),
        ),
        decoder: _ack,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/speaker-queue/promote` (W, U, H) —
  /// promotes [entryId], or the next entry when omitted.
  Future<ApiResponse<MediaSpeakerQueueEntry>> promote(
    String sessionId, {
    String? entryId,
  }) {
    return withMediaErrors(
      () => _client.post<MediaSpeakerQueueEntry>(
        _sessionPath(sessionId, '/speaker-queue/promote'),
        body: <String, dynamic>{if (entryId != null) 'entry_id': entryId},
        decoder: _speakerEntry,
      ),
    );
  }

  /// `POST /media/sessions/:sessionId/speaker-queue/entries/:entryId/end`
  /// (W, U, H) — ends the current turn.
  Future<ApiResponse<void>> endTurn(String sessionId, String entryId) {
    return withMediaErrors(
      () => _client.post<void>(
        _sessionPath(
          sessionId,
          '/speaker-queue/entries/${encodeSegment(entryId)}/end',
        ),
        decoder: _ack,
      ),
    );
  }

  /// `DELETE /media/sessions/:sessionId/speaker-queue/entries/:entryId`
  /// (W, U, H) — removes an entry from the queue.
  Future<ApiResponse<void>> remove(String sessionId, String entryId) {
    return withMediaErrors(
      () => _client.delete<void>(
        _sessionPath(
          sessionId,
          '/speaker-queue/entries/${encodeSegment(entryId)}',
        ),
        decoder: _ack,
      ),
    );
  }

  /// `PATCH /media/sessions/:sessionId/speaker-queue/entries/:entryId/priority`
  /// (W, U, H) — body `{priority}`.
  Future<ApiResponse<void>> setPriority(
    String sessionId,
    String entryId,
    int priority,
  ) {
    return withMediaErrors(
      () => _client.patch<void>(
        _sessionPath(
          sessionId,
          '/speaker-queue/entries/${encodeSegment(entryId)}/priority',
        ),
        body: <String, dynamic>{'priority': priority},
        decoder: _ack,
      ),
    );
  }
}

// ── Attendance ──────────────────────────────────────────────────────────────

/// Attendance.
///
/// Exposed at `superso.media.attendance`.
class MediaAttendanceModule {
  /// Creates an attendance module.
  const MediaAttendanceModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /media/sessions/:sessionId/attendance` (R, U, H) —
  /// `{summary, total}`, decoded as the per-participant summary rows.
  Future<ApiResponse<List<MediaResource>>> summary(String sessionId) {
    return withMediaErrors(
      () => _client.get<List<MediaResource>>(
        _sessionPath(sessionId, '/attendance'),
        decoder: (data) => _jsonList(_json(data)['summary'])
            .map(MediaResource.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `GET /media/sessions/:sessionId/attendance/events` (R, U, H) —
  /// paginated attendance records.
  Future<ApiResponse<MediaPage<MediaResource>>> events(
    String sessionId, {
    int? limit,
    int? offset,
  }) {
    return withMediaErrors(
      () => _client.get<MediaPage<MediaResource>>(
        _sessionPath(sessionId, '/attendance/events'),
        options: RequestOptions(query: _pageQuery(limit, offset)),
        decoder: _resourcePage,
      ),
    );
  }
}

// ── Signaling roles ─────────────────────────────────────────────────────────

/// Publisher-role signaling (`GET /media/signal?role=publisher`, R).
///
/// Exposed at `superso.media.publishers`. Transport only: the host app's
/// WebRTC plugin drives the peer connection. Apply
/// `MediaSignalingReady.mediaConstraints` to capture/encodings and never
/// enable simulcast (single-layer SFU). Label each published track with
/// [MediaSignalingConnection.sendTrackInfo].
class MediaPublishersModule {
  /// Creates a publishers module sharing [tokens].
  MediaPublishersModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// The signaling connection opened by [join].
  late final MediaSignalingConnection connection =
      MediaSignalingConnection(_client, tokens: _tokens);

  /// Opens the publisher socket for [sessionId]. The participant token
  /// stored by `sessions.join` is used unless [participantToken] is given;
  /// pass `MediaJoinResult.breakoutRoomId` as [breakoutRoomId] when assigned
  /// to a breakout room.
  Future<MediaSignalingConnection> join(
    String sessionId, {
    String? participantToken,
    String? breakoutRoomId,
    String? displayName,
    String? platform,
    String? sdkVersion,
    String? appVersion,
    String? networkType,
  }) async {
    await connection.connect(
      sessionId,
      SignalingRole.publisher,
      participantToken: participantToken,
      breakoutRoomId: breakoutRoomId,
      displayName: displayName,
      platform: platform,
      sdkVersion: sdkVersion,
      appVersion: appVersion,
      networkType: networkType,
    );
    return connection;
  }

  /// Closes the publisher socket (no automatic reconnect).
  Future<void> leave() => connection.disconnect();
}

/// Subscriber-role signaling (`GET /media/signal?role=subscriber`, R).
///
/// Exposed at `superso.media.subscribers`.
class MediaSubscribersModule {
  /// Creates a subscribers module sharing [tokens].
  MediaSubscribersModule(this._client, this._tokens);

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// The signaling connection opened by [join].
  late final MediaSignalingConnection connection =
      MediaSignalingConnection(_client, tokens: _tokens);

  /// Opens the subscriber socket for [sessionId]; see
  /// [MediaPublishersModule.join].
  Future<MediaSignalingConnection> join(
    String sessionId, {
    String? participantToken,
    String? breakoutRoomId,
    String? displayName,
    String? platform,
    String? sdkVersion,
    String? appVersion,
    String? networkType,
  }) async {
    await connection.connect(
      sessionId,
      SignalingRole.subscriber,
      participantToken: participantToken,
      breakoutRoomId: breakoutRoomId,
      displayName: displayName,
      platform: platform,
      sdkVersion: sdkVersion,
      appVersion: appVersion,
      networkType: networkType,
    );
    return connection;
  }

  /// Closes the subscriber socket (no automatic reconnect).
  Future<void> leave() => connection.disconnect();
}

// ── Composition root ────────────────────────────────────────────────────────

/// The composition root for the Media module.
///
/// ```dart
/// final session = await superso.media.sessions.create(title: 'Standup');
/// await superso.media.sessions.start(session.data.id);
///
/// // Admission: stores the participant token automatically.
/// final join = await superso.media.sessions.join(session.data.id);
/// if (join.data.isWaiting) { /* poll waitingRoom.status or listen */ }
///
/// // Realtime events (catalogue in media_events.dart).
/// superso.media.on(session.data.id, MediaParticipantEvents.joined)
///     .listen((e) => print(e.asParticipant.displayName));
///
/// // Signaling: drive your own WebRTC plugin over the connection.
/// final conn = await superso.media.publishers.join(
///   session.data.id,
///   breakoutRoomId: join.data.breakoutRoomId,
/// );
/// conn.onReady.listen((ready) { /* ready.iceServers, ready.mediaConstraints */ });
/// ```
class MediaModule implements SdkModule, Disposable {
  /// Creates the media module bound to [client].
  MediaModule(SupersoHttpClient client)
      : this._(client, MediaParticipantTokens());

  MediaModule._(this.client, this.tokens)
      : sessions = MediaSessionsModule(client, tokens),
        participants = MediaParticipantsModule(client, tokens),
        permissions = MediaPermissionsModule(client, tokens),
        moderation = MediaModerationModule(client),
        voiceRooms = MediaVoiceRoomsModule(client, tokens),
        breakoutRooms = MediaBreakoutRoomsModule(client),
        waitingRoom = MediaWaitingRoomModule(client, tokens),
        speakerQueue = MediaSpeakerQueueModule(client, tokens),
        attendance = MediaAttendanceModule(client),
        publishers = MediaPublishersModule(client, tokens),
        subscribers = MediaSubscribersModule(client, tokens),
        websocket = MediaSignalingConnection(client, tokens: tokens);

  @override
  final SupersoHttpClient client;

  /// Participant tokens issued by `join` (and signaling `ready`), shared by
  /// every sub-module.
  final MediaParticipantTokens tokens;

  /// Session lifecycle, admission and own-participant state.
  final MediaSessionsModule sessions;

  /// Project-wide participant lookup and telemetry.
  final MediaParticipantsModule participants;

  /// Participant self-service and permission views.
  final MediaPermissionsModule permissions;

  /// Host moderation (end-user access token of a privileged participant).
  final MediaModerationModule moderation;

  /// Voice rooms.
  final MediaVoiceRoomsModule voiceRooms;

  /// Breakout rooms.
  final MediaBreakoutRoomsModule breakoutRooms;

  /// The waiting room.
  final MediaWaitingRoomModule waitingRoom;

  /// The speaker queue.
  final MediaSpeakerQueueModule speakerQueue;

  /// Attendance.
  final MediaAttendanceModule attendance;

  /// Publisher-role signaling.
  final MediaPublishersModule publishers;

  /// Subscriber-role signaling.
  final MediaSubscribersModule subscribers;

  /// A standalone signaling connection — open it with either role via
  /// [MediaSignalingConnection.connect].
  final MediaSignalingConnection websocket;

  final Map<String, RealtimeSocket> _sockets = <String, RealtimeSocket>{};

  /// `GET /media/overview` (R) — live statistics plus today's usage.
  Future<ApiResponse<MediaResource>> overview() {
    return withMediaErrors(
      () => client.get<MediaResource>('/media/overview', decoder: _resource),
    );
  }

  /// `GET /media/usage` (R) — `{usage, days}`, decoded as the daily usage
  /// rows of the last [days] days.
  Future<ApiResponse<List<MediaResource>>> usage({int? days}) {
    return withMediaErrors(
      () => client.get<List<MediaResource>>(
        '/media/usage',
        options: RequestOptions(query: <String, Object?>{'days': days}),
        decoder: (data) => _jsonList(_json(data)['usage'])
            .map(MediaResource.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `GET /media/settings` (R).
  Future<ApiResponse<MediaSettings>> getSettings() {
    return withMediaErrors(
      () => client.get<MediaSettings>(
        '/media/settings',
        decoder: (data) => MediaSettings.fromJson(_json(data)),
      ),
    );
  }

  /// `PUT /media/settings` (**D** — requires a `delete`-scope, server-side
  /// API key; never ship that key in a client app). Partial update: only
  /// the fields you pass are sent.
  Future<ApiResponse<MediaSettings>> updateSettings({
    bool? enabled,
    int? maxSessions,
    int? maxPublishersPerSession,
    int? maxParticipantsPerSession,
    int? maxSessionDurationSec,
    int? connectionTimeoutSec,
    bool? voiceRoomsEnabled,
    bool? webrtcEnabled,
    List<String>? stunUrls,
    bool? turnEnabled,
    String? turnUrl,
    String? turnUsername,
    String? turnCredential,
    int? maxVideoBitrateKbps,
    int? maxAudioBitrateKbps,
    String? defaultResolution,
    int? defaultFps,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? waitingRoomDefault,
    bool? screenShareDefault,
    bool? moderationEnabled,
    bool? analyticsEnabled,
    bool? auditEnabled,
  }) {
    return withMediaErrors(
      () => client.put<MediaSettings>(
        '/media/settings',
        body: <String, dynamic>{
          if (enabled != null) 'enabled': enabled,
          if (maxSessions != null) 'max_sessions': maxSessions,
          if (maxPublishersPerSession != null)
            'max_publishers_per_session': maxPublishersPerSession,
          if (maxParticipantsPerSession != null)
            'max_participants_per_session': maxParticipantsPerSession,
          if (maxSessionDurationSec != null)
            'max_session_duration_sec': maxSessionDurationSec,
          if (connectionTimeoutSec != null)
            'connection_timeout_sec': connectionTimeoutSec,
          if (voiceRoomsEnabled != null) 'voice_rooms_enabled': voiceRoomsEnabled,
          if (webrtcEnabled != null) 'webrtc_enabled': webrtcEnabled,
          if (stunUrls != null) 'stun_urls': stunUrls,
          if (turnEnabled != null) 'turn_enabled': turnEnabled,
          if (turnUrl != null) 'turn_url': turnUrl,
          if (turnUsername != null) 'turn_username': turnUsername,
          if (turnCredential != null) 'turn_credential': turnCredential,
          if (maxVideoBitrateKbps != null)
            'max_video_bitrate_kbps': maxVideoBitrateKbps,
          if (maxAudioBitrateKbps != null)
            'max_audio_bitrate_kbps': maxAudioBitrateKbps,
          if (defaultResolution != null) 'default_resolution': defaultResolution,
          if (defaultFps != null) 'default_fps': defaultFps,
          if (noiseSuppression != null) 'noise_suppression': noiseSuppression,
          if (echoCancellation != null) 'echo_cancellation': echoCancellation,
          if (waitingRoomDefault != null)
            'waiting_room_default': waitingRoomDefault,
          if (screenShareDefault != null)
            'screen_share_default': screenShareDefault,
          if (moderationEnabled != null) 'moderation_enabled': moderationEnabled,
          if (analyticsEnabled != null) 'analytics_enabled': analyticsEnabled,
          if (auditEnabled != null) 'audit_enabled': auditEnabled,
        },
        decoder: (data) => MediaSettings.fromJson(_json(data)),
      ),
    );
  }

  /// Every realtime event on the session channel `media.<sessionId>`
  /// (server-publish-only). Opens lazily on first listen; shared by every
  /// listener of that session.
  Stream<MediaEvent> events(String sessionId) {
    final socket = _sockets.putIfAbsent(
      sessionId,
      () => RealtimeSocket(client, channel: 'media.$sessionId'),
    );
    return socket.messages.map(MediaEvent.fromJson);
  }

  /// Events named [eventName] on a session's channel.
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

  /// The event name. See `MediaEvents.all`.
  final String event;

  /// The event payload.
  final Object? data;

  /// The complete decoded frame.
  final Map<String, dynamic> raw;

  /// The payload as a JSON map, or an empty map when it is not one.
  Map<String, dynamic> get dataAsMap {
    final payload = data;
    return (payload is Map<String, dynamic>)
        ? payload
        : const <String, dynamic>{};
  }

  /// `session_id` — present on every Media event.
  String? get sessionId {
    final value = dataAsMap['session_id'];
    return value is String ? value : null;
  }

  /// `participant_id` — present on participant events.
  String? get participantId {
    final value = dataAsMap['participant_id'];
    return value is String ? value : null;
  }

  /// The public participant view carried by participant events (the
  /// `participant` field), falling back to the payload itself.
  MediaParticipant get asParticipant {
    final nested = dataAsMap['participant'];
    return MediaParticipant.fromJson(
      (nested is Map<String, dynamic>) ? nested : dataAsMap,
    );
  }

  /// The session carried by `session_updated` / `voice_room.updated` (the
  /// `session` field), falling back to the payload itself.
  MediaSession get asSession {
    final nested = dataAsMap['session'];
    return MediaSession.fromJson(
      (nested is Map<String, dynamic>) ? nested : dataAsMap,
    );
  }

  @override
  String toString() => 'MediaEvent($event)';
}
