/// Domain models for the Media module.
///
/// Every field mirrors the JSON the backend actually serializes — see
/// `backend/internal/modules/media/dto/responses.go` (sessions, participants,
/// join, waiting entries, breakout rooms, speaker queue) and
/// `backend/internal/modules/media/model/*.go` (settings, requests, tracks).
/// The canonical contract is `docs/internal/MEDIA_CANONICAL_CONTRACT.md`
/// (v0.4.0, §9 and the §14 addendum).
library;

import 'package:meta/meta.dart';

// ── JSON helpers ─────────────────────────────────────────────────────────────

Map<String, dynamic> _map(Object? value) =>
    (value is Map<String, dynamic>) ? value : const <String, dynamic>{};

String? _str(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

int? _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value.toInt() : null;
}

double? _double(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value.toDouble() : null;
}

bool _bool(Map<String, dynamic> json, String key) => json[key] == true;

List<Map<String, dynamic>> _objects(Object? value) => (value is List<dynamic>)
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];

List<String> _strings(Object? value) => (value is List<dynamic>)
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

// ── Enums ────────────────────────────────────────────────────────────────────

/// Session lifecycle state
/// (`scheduled → waiting → live → ended → archived`, or `cancelled`).
enum MediaSessionStatus {
  /// Created for a future time.
  scheduled('scheduled'),

  /// Open, waiting for the host.
  waiting('waiting'),

  /// In progress.
  live('live'),

  /// Finished.
  ended('ended'),

  /// Finished and archived, excluded from active listings.
  archived('archived'),

  /// Cancelled before it ran.
  cancelled('cancelled');

  const MediaSessionStatus(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [scheduled] for anything
  /// unrecognized.
  static MediaSessionStatus fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => MediaSessionStatus.scheduled,
      );
}

/// Why a session ended (`model.EndedReason`).
enum MediaSessionEndedReason {
  /// A host ended it explicitly.
  hostEnded('host_ended'),

  /// The last participant left.
  roomEmpty('room_empty'),

  /// No privileged participant was connected for `host_leave_timeout_sec`.
  hostLeaveTimeout('host_leave_timeout'),

  /// An operator ended it from the dashboard.
  adminForceEnd('admin_force_end'),

  /// The server shut down.
  systemShutdown('system_shutdown'),

  /// The session was cancelled.
  cancelled('cancelled'),

  /// `max_session_duration_sec` was exceeded.
  maxDuration('max_duration'),

  /// The session's `expires_at` passed.
  expired('expired');

  const MediaSessionEndedReason(this.wireValue);

  /// The value received from the backend.
  final String wireValue;

  /// Parses a wire value, returning `null` for anything unrecognized.
  static MediaSessionEndedReason? fromWire(String? value) {
    for (final reason in values) {
      if (reason.wireValue == value) return reason;
    }
    return null;
  }
}

/// A participant's connection role in a session.
enum MediaParticipantRole {
  /// Publishes audio and video.
  publisher('publisher'),

  /// Receives only.
  subscriber('subscriber'),

  /// Can moderate.
  moderator('moderator'),

  /// Watches without publishing.
  viewer('viewer');

  const MediaParticipantRole(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [subscriber] for anything
  /// unrecognized.
  static MediaParticipantRole fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => MediaParticipantRole.subscriber,
      );
}

/// A participant's classroom role.
///
/// The privileged roles are [owner] (rank 100), [teacher] and [coHost]
/// (80), [assistantTeacher] (60) and [moderator] (40) — see [isPrivileged]
/// and contract §2.
enum ClassroomRole {
  /// Watches only.
  viewer('viewer'),

  /// Part of the audience.
  audience('audience'),

  /// May speak.
  speaker('speaker'),

  /// May present.
  presenter('presenter'),

  /// May moderate.
  moderator('moderator'),

  /// Shares hosting duties.
  coHost('co_host'),

  /// Assists the teacher.
  assistantTeacher('assistant_teacher'),

  /// Runs the class.
  teacher('teacher'),

  /// Owns the session. Never assignable.
  owner('owner'),

  /// An unauthenticated attendee (assignable to guests only).
  guest('guest'),

  /// An attendee from outside the project (assignable to guests only).
  externalGuest('external_guest');

  const ClassroomRole(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Whether this role carries moderation authority.
  bool get isPrivileged =>
      this == owner ||
      this == teacher ||
      this == assistantTeacher ||
      this == coHost ||
      this == moderator;

  /// Parses a wire value, defaulting to [viewer] for anything unrecognized.
  static ClassroomRole fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => ClassroomRole.viewer,
      );

  /// The roles that can be granted to any (non-guest) participant through
  /// `moderation.assignRole`.
  ///
  /// [owner] is never assignable (the server answers
  /// `MEDIA_VALIDATION_FAILED`). [guest]/[externalGuest] are accepted by the
  /// server only for guest participants. The server additionally requires
  /// the granted role to rank strictly below the caller's own
  /// (`MEDIA_INSUFFICIENT_RANK` otherwise).
  static const List<ClassroomRole> assignable = <ClassroomRole>[
    teacher,
    assistantTeacher,
    coHost,
    moderator,
    presenter,
    speaker,
    audience,
    viewer,
  ];
}

/// What a permission request is for (`model.RequestType`). Used by
/// `permissions.cancelRequest`.
enum MediaRequestType {
  /// Camera publishing.
  camera('camera'),

  /// Microphone publishing.
  microphone('microphone'),

  /// Screen sharing.
  screen('screen'),

  /// Joining the stage.
  stage('stage'),

  /// Speaking.
  speaking('speaking');

  const MediaRequestType(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;
}

/// The source label of a published track (signaling `track_info`).
enum MediaTrackSource {
  /// A camera video track.
  camera('camera'),

  /// A microphone audio track.
  microphone('microphone'),

  /// A screen-share video track.
  screen('screen');

  const MediaTrackSource(this.wireValue);

  /// The value sent on the wire.
  final String wireValue;
}

/// The outcome of `POST /sessions/:sessionId/join`.
enum MediaJoinAdmission {
  /// The participant may connect to signaling now.
  admitted('admitted'),

  /// The participant is in the waiting room until a host admits them.
  waiting('waiting');

  const MediaJoinAdmission(this.wireValue);

  /// The value received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [admitted].
  static MediaJoinAdmission fromWire(String? value) =>
      value == 'waiting' ? waiting : admitted;
}

// ── Sessions ─────────────────────────────────────────────────────────────────

/// A media session (`dto.SessionResponse`). Voice rooms are sessions with
/// [voiceRoom] = `true`.
@immutable
class MediaSession {
  /// Creates a session.
  const MediaSession({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.raw,
    this.description,
    this.topic,
    this.type,
    this.visibility,
    this.sessionMode,
    this.voiceRoom = false,
    this.roomType,
    this.allowListenersToSpeak = false,
    this.requireHandRaise = false,
    this.hostParticipantId,
    this.maxPublishers,
    this.maxParticipants,
    this.waitingRoom = false,
    this.roomLocked = false,
    this.screenShareEnabled = false,
    this.guestAllowed = false,
    this.attendanceEnabled = false,
    this.allowSelfUnmute = false,
    this.joinToken,
    this.metadata,
    this.peakPublishers,
    this.peakParticipants,
    this.totalParticipants,
    this.durationSec,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.expiresAt,
    this.endedReason,
    this.archivedAt,
    this.hostLeftAt,
    this.hostLeaveTimeoutSec,
    this.lastActivityAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a session from JSON.
  factory MediaSession.fromJson(Map<String, dynamic> json) => MediaSession(
        id: _str(json, 'id') ?? '',
        projectId: _str(json, 'project_id') ?? '',
        title: _str(json, 'title') ?? '',
        status: MediaSessionStatus.fromWire(_str(json, 'status')),
        raw: json,
        description: _str(json, 'description'),
        topic: _str(json, 'topic'),
        type: _str(json, 'type'),
        visibility: _str(json, 'visibility'),
        sessionMode: _str(json, 'session_mode'),
        voiceRoom: _bool(json, 'voice_room'),
        roomType: _str(json, 'room_type'),
        allowListenersToSpeak: _bool(json, 'allow_listeners_to_speak'),
        requireHandRaise: _bool(json, 'require_hand_raise'),
        hostParticipantId: _str(json, 'host_participant_id'),
        maxPublishers: _int(json, 'max_publishers'),
        maxParticipants: _int(json, 'max_participants'),
        waitingRoom: _bool(json, 'waiting_room'),
        roomLocked: _bool(json, 'room_locked'),
        screenShareEnabled: _bool(json, 'screen_share_enabled'),
        guestAllowed: _bool(json, 'guest_allowed'),
        attendanceEnabled: _bool(json, 'attendance_enabled'),
        allowSelfUnmute: _bool(json, 'allow_self_unmute'),
        joinToken: _str(json, 'join_token'),
        metadata: (json['metadata'] is Map<String, dynamic>)
            ? json['metadata'] as Map<String, dynamic>
            : null,
        peakPublishers: _int(json, 'peak_publishers'),
        peakParticipants: _int(json, 'peak_participants'),
        totalParticipants: _int(json, 'total_participants'),
        durationSec: _int(json, 'duration_sec'),
        scheduledAt: _str(json, 'scheduled_at'),
        startedAt: _str(json, 'started_at'),
        endedAt: _str(json, 'ended_at'),
        expiresAt: _str(json, 'expires_at'),
        endedReason:
            MediaSessionEndedReason.fromWire(_str(json, 'ended_reason')),
        archivedAt: _str(json, 'archived_at'),
        hostLeftAt: _str(json, 'host_left_at'),
        hostLeaveTimeoutSec: _int(json, 'host_leave_timeout_sec'),
        lastActivityAt: _str(json, 'last_activity_at'),
        createdBy: _str(json, 'created_by'),
        createdAt: _str(json, 'created_at'),
        updatedAt: _str(json, 'updated_at'),
      );

  /// Session identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// Display title.
  final String title;

  /// Lifecycle state.
  final MediaSessionStatus status;

  /// Optional description.
  final String? description;

  /// Optional topic / agenda.
  final String? topic;

  /// `video`, `audio` or `screen`.
  final String? type;

  /// `public`, `private`, `invite_only` or `password_protected`.
  final String? visibility;

  /// `conference`, `classroom`, `webinar` or `voice`.
  final String? sessionMode;

  /// Whether this session is a voice room.
  final bool voiceRoom;

  /// Voice rooms only: `open`, `stage` or `moderated`.
  final String? roomType;

  /// Voice rooms only: whether listeners may speak without promotion.
  final bool allowListenersToSpeak;

  /// Voice rooms only: whether speaking requires a raised hand.
  final bool requireHandRaise;

  /// The participant designated as host.
  final String? hostParticipantId;

  /// Publisher cap.
  final int? maxPublishers;

  /// Participant cap.
  final int? maxParticipants;

  /// Whether non-privileged joiners wait for admission.
  final bool waitingRoom;

  /// Whether non-privileged joiners are refused (`MEDIA_ROOM_LOCKED`).
  final bool roomLocked;

  /// Whether screen sharing is enabled.
  final bool screenShareEnabled;

  /// Whether guests (no end-user JWT) may join.
  final bool guestAllowed;

  /// Whether attendance is tracked.
  final bool attendanceEnabled;

  /// Whether participants may unmute themselves.
  final bool allowSelfUnmute;

  /// Invite secret. Only returned to the dashboard, the session owner and
  /// privileged participants.
  final String? joinToken;

  /// Free-form metadata supplied at creation.
  final Map<String, dynamic>? metadata;

  /// Peak concurrent publishers.
  final int? peakPublishers;

  /// Peak concurrent participants.
  final int? peakParticipants;

  /// Total distinct participants.
  final int? totalParticipants;

  /// Duration in seconds.
  final int? durationSec;

  /// ISO-8601 scheduled start.
  final String? scheduledAt;

  /// ISO-8601 start timestamp.
  final String? startedAt;

  /// ISO-8601 end timestamp.
  final String? endedAt;

  /// ISO-8601 expiry timestamp.
  final String? expiresAt;

  /// Why the session ended.
  final MediaSessionEndedReason? endedReason;

  /// ISO-8601 archive timestamp.
  final String? archivedAt;

  /// ISO-8601 timestamp the last host left, starting the grace period.
  final String? hostLeftAt;

  /// How long the session survives without a host, in seconds (0 = never
  /// auto-ends).
  final int? hostLeaveTimeoutSec;

  /// ISO-8601 timestamp of the last activity.
  final String? lastActivityAt;

  /// The end user who owns this session.
  final String? createdBy;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether the session is currently running.
  bool get isLive => status == MediaSessionStatus.live;

  @override
  String toString() =>
      'MediaSession(id: $id, title: $title, ${status.wireValue})';
}

/// A participant in a session or voice room (`dto.ParticipantResponse`).
///
/// `email`, `ip_address` and `user_agent` are Admin-only and never returned
/// to the SDK; they remain reachable through [raw] when present.
@immutable
class MediaParticipant {
  /// Creates a participant.
  const MediaParticipant({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.raw,
    this.userId,
    this.status,
    this.isPublisher = false,
    this.connectionState,
    this.networkQuality,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.guestId,
    this.isGuest = false,
    this.country,
    this.browser,
    this.browserVersion,
    this.os,
    this.deviceType,
    this.platform,
    this.networkType,
    this.sdkVersion,
    this.appVersion,
    this.cameraEnabled = false,
    this.microphoneEnabled = false,
    this.screenShareActive = false,
    this.hadCamera = false,
    this.hadMicrophone = false,
    this.hadScreen = false,
    this.isSpeaking = false,
    this.audioLevel,
    this.lastSpokeAt,
    this.totalSpokeSec,
    this.participantState,
    this.classroomRole,
    this.voiceRole,
    this.isHost = false,
    this.cameraPermission = false,
    this.microphonePermission = false,
    this.screenPermission = false,
    this.publishPermission = false,
    this.canUnmute = false,
    this.isMuted = false,
    this.forceMuted = false,
    this.videoHidden = false,
    this.isPinned = false,
    this.isSpotlighted = false,
    this.handRaisedAt,
    this.requestType,
    this.requestReason,
    this.stageRequestedAt,
    this.invitedAt,
    this.bitrateKbps,
    this.packetLossPct,
    this.rttMs,
    this.jitterMs,
    this.connectionScore,
    this.iceState,
    this.dtlsState,
    this.disconnectReason,
    this.reconnectCount,
    this.joinedAt,
    this.leftAt,
    this.lastSeenAt,
    this.durationSec,
  });

  /// Decodes a participant from JSON.
  factory MediaParticipant.fromJson(Map<String, dynamic> json) =>
      MediaParticipant(
        id: _str(json, 'id') ?? '',
        sessionId: _str(json, 'session_id') ?? '',
        role: MediaParticipantRole.fromWire(_str(json, 'role')),
        raw: json,
        userId: _str(json, 'user_id'),
        status: _str(json, 'status'),
        isPublisher: _bool(json, 'is_publisher'),
        connectionState: _str(json, 'connection_state'),
        networkQuality: _str(json, 'network_quality'),
        displayName: _str(json, 'display_name'),
        username: _str(json, 'username'),
        avatarUrl: _str(json, 'avatar_url'),
        guestId: _str(json, 'guest_id'),
        isGuest: _bool(json, 'is_guest'),
        country: _str(json, 'country'),
        browser: _str(json, 'browser'),
        browserVersion: _str(json, 'browser_version'),
        os: _str(json, 'os'),
        deviceType: _str(json, 'device_type'),
        platform: _str(json, 'platform'),
        networkType: _str(json, 'network_type'),
        sdkVersion: _str(json, 'sdk_version'),
        appVersion: _str(json, 'app_version'),
        cameraEnabled: _bool(json, 'camera_enabled'),
        microphoneEnabled: _bool(json, 'microphone_enabled'),
        screenShareActive: _bool(json, 'screen_share_active'),
        hadCamera: _bool(json, 'had_camera'),
        hadMicrophone: _bool(json, 'had_microphone'),
        hadScreen: _bool(json, 'had_screen'),
        isSpeaking: _bool(json, 'is_speaking'),
        audioLevel: _double(json, 'audio_level'),
        lastSpokeAt: _str(json, 'last_spoke_at'),
        totalSpokeSec: _int(json, 'total_spoke_sec'),
        participantState: _str(json, 'participant_state'),
        classroomRole: _str(json, 'classroom_role') == null
            ? null
            : ClassroomRole.fromWire(_str(json, 'classroom_role')),
        voiceRole: _str(json, 'voice_role'),
        isHost: _bool(json, 'is_host'),
        cameraPermission: _bool(json, 'camera_permission'),
        microphonePermission: _bool(json, 'microphone_permission'),
        screenPermission: _bool(json, 'screen_permission'),
        publishPermission: _bool(json, 'publish_permission'),
        canUnmute: _bool(json, 'can_unmute'),
        isMuted: _bool(json, 'is_muted'),
        forceMuted: _bool(json, 'force_muted'),
        videoHidden: _bool(json, 'video_hidden'),
        isPinned: _bool(json, 'is_pinned'),
        isSpotlighted: _bool(json, 'is_spotlighted'),
        handRaisedAt: _str(json, 'hand_raised_at'),
        requestType: _str(json, 'request_type'),
        requestReason: _str(json, 'request_reason'),
        stageRequestedAt: _str(json, 'stage_requested_at'),
        invitedAt: _str(json, 'invited_at'),
        bitrateKbps: _int(json, 'bitrate_kbps'),
        packetLossPct: _double(json, 'packet_loss_pct'),
        rttMs: _int(json, 'rtt_ms'),
        jitterMs: _double(json, 'jitter_ms'),
        connectionScore: _int(json, 'connection_score'),
        iceState: _str(json, 'ice_state'),
        dtlsState: _str(json, 'dtls_state'),
        disconnectReason: _str(json, 'disconnect_reason'),
        reconnectCount: _int(json, 'reconnect_count'),
        joinedAt: _str(json, 'joined_at'),
        leftAt: _str(json, 'left_at'),
        lastSeenAt: _str(json, 'last_seen_at'),
        durationSec: _int(json, 'duration_sec'),
      );

  /// Participant identifier. This is what every moderation call targets.
  final String id;

  /// The session this participation belongs to.
  final String sessionId;

  /// Connection role: `publisher`, `subscriber` or `moderator`.
  final MediaParticipantRole role;

  /// The authenticated user, or `null` for a guest.
  final String? userId;

  /// `waiting`, `ready`, `joined`, `left`, `kicked` or `banned`.
  final String? status;

  /// Whether the participant currently has a publisher connection.
  final bool isPublisher;

  /// Signaling connection state.
  final String? connectionState;

  /// Derived network quality.
  final String? networkQuality;

  /// Display name. Resolved from Auth for authenticated users.
  final String? displayName;

  /// Username. Resolved from Auth.
  final String? username;

  /// Avatar URL. Resolved from Auth.
  final String? avatarUrl;

  /// Guest identifier for unauthenticated participants.
  final String? guestId;

  /// Whether this participant is unauthenticated.
  final bool isGuest;

  /// Country, when resolved.
  final String? country;

  /// Browser name, when reported.
  final String? browser;

  /// Browser version, when reported.
  final String? browserVersion;

  /// Operating system, when reported.
  final String? os;

  /// Device type, when reported.
  final String? deviceType;

  /// Client platform reported at join / signaling.
  final String? platform;

  /// Network type reported by the client.
  final String? networkType;

  /// SDK version reported by the client.
  final String? sdkVersion;

  /// App version reported by the client.
  final String? appVersion;

  /// Whether the camera is on (client-reported, server-policed).
  final bool cameraEnabled;

  /// Whether the microphone is on (client-reported, server-policed).
  final bool microphoneEnabled;

  /// Whether a screen share is active.
  final bool screenShareActive;

  /// Whether the camera was ever on in this session.
  final bool hadCamera;

  /// Whether the microphone was ever on in this session.
  final bool hadMicrophone;

  /// Whether a screen was ever shared in this session.
  final bool hadScreen;

  /// Whether the participant is currently speaking.
  final bool isSpeaking;

  /// Last measured audio level.
  final double? audioLevel;

  /// ISO-8601 timestamp of the last audio activity.
  final String? lastSpokeAt;

  /// Cumulative speaking seconds.
  final int? totalSpokeSec;

  /// Stage position: `viewer`, `waiting`, `requested`, `invited`,
  /// `accepted`, `stage`, `publisher`, `presenter`, `muted`, `removed` or
  /// `kicked`.
  final String? participantState;

  /// Classroom role.
  final ClassroomRole? classroomRole;

  /// Voice-room role: `host`, `moderator`, `speaker` or `listener`.
  final String? voiceRole;

  /// Whether this participant is the session's host participant.
  final bool isHost;

  /// Server policy: may publish camera video.
  final bool cameraPermission;

  /// Server policy: may publish microphone audio.
  final bool microphonePermission;

  /// Server policy: may share a screen.
  final bool screenPermission;

  /// Server policy: may publish in a webinar.
  final bool publishPermission;

  /// Whether the participant may unmute themselves.
  final bool canUnmute;

  /// Whether a host muted this participant.
  final bool isMuted;

  /// Whether a host force-muted this participant (no self-unmute).
  final bool forceMuted;

  /// Whether a host hid this participant's video.
  final bool videoHidden;

  /// Whether the participant is pinned in every viewer's layout.
  final bool isPinned;

  /// Whether the participant is spotlighted.
  final bool isSpotlighted;

  /// ISO-8601 timestamp of when their hand was raised (voice rooms), or
  /// `null` if not raised.
  final String? handRaisedAt;

  /// The type of the participant's pending request, if any.
  final String? requestType;

  /// The reason of the participant's pending request, if any.
  final String? requestReason;

  /// ISO-8601 timestamp of the last stage request.
  final String? stageRequestedAt;

  /// ISO-8601 timestamp of the last stage invitation.
  final String? invitedAt;

  /// Last reported bitrate (kbps).
  final int? bitrateKbps;

  /// Last reported packet loss (%).
  final double? packetLossPct;

  /// Last reported round-trip time (ms).
  final int? rttMs;

  /// Last reported jitter (ms).
  final double? jitterMs;

  /// Derived connection score.
  final int? connectionScore;

  /// Last reported ICE state.
  final String? iceState;

  /// Last reported DTLS state.
  final String? dtlsState;

  /// Why the participant disconnected, when known.
  final String? disconnectReason;

  /// How many times the participant reconnected.
  final int? reconnectCount;

  /// ISO-8601 join timestamp.
  final String? joinedAt;

  /// ISO-8601 leave timestamp.
  final String? leftAt;

  /// ISO-8601 timestamp the participant was last seen.
  final String? lastSeenAt;

  /// Time spent in the session, in seconds.
  final int? durationSec;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether their hand is raised. Derived from [handRaisedAt].
  bool get handRaised => handRaisedAt != null;

  /// Alias of [screenShareActive], kept for source compatibility.
  @Deprecated('Use screenShareActive (the backend field screen_share_active).')
  bool get screenSharing => screenShareActive;

  /// Whether this participant is privileged (contract §2): the host
  /// participant, a privileged classroom role, a voice host/moderator, or
  /// the `moderator` connection role.
  bool get isPrivileged =>
      isHost ||
      (classroomRole?.isPrivileged ?? false) ||
      voiceRole == 'host' ||
      voiceRole == 'moderator' ||
      role == MediaParticipantRole.moderator;

  @override
  String toString() =>
      'MediaParticipant(id: $id, ${displayName ?? userId ?? 'guest'}, '
      '${role.wireValue})';
}

// ── Collections ──────────────────────────────────────────────────────────────

/// One page of a paginated Media list:
/// `data = {items, total, limit, offset, has_more}`.
@immutable
class MediaPage<T> {
  /// Creates a page.
  const MediaPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  /// Decodes a page, converting each item with [decodeItem].
  factory MediaPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) decodeItem,
  ) =>
      MediaPage<T>(
        items: _objects(json['items']).map(decodeItem).toList(growable: false),
        total: _int(json, 'total') ?? 0,
        limit: _int(json, 'limit') ?? 0,
        offset: _int(json, 'offset') ?? 0,
        hasMore: _bool(json, 'has_more'),
      );

  /// The items on this page.
  final List<T> items;

  /// Total items matching the query.
  final int total;

  /// The page size the server applied.
  final int limit;

  /// The offset of this page.
  final int offset;

  /// Whether more items follow this page.
  final bool hasMore;

  @override
  String toString() => 'MediaPage(${items.length} of $total)';
}

/// A page of sessions (`GET /sessions`, `GET /voice-rooms`).
@immutable
class MediaSessionList {
  /// Creates a session list.
  const MediaSessionList({
    required this.sessions,
    required this.total,
    this.limit = 0,
    this.offset = 0,
    this.hasMore = false,
  });

  /// Decodes a session list from the paginated envelope.
  factory MediaSessionList.fromJson(Map<String, dynamic> json) {
    final page = MediaPage<MediaSession>.fromJson(json, MediaSession.fromJson);
    return MediaSessionList(
      sessions: page.items,
      total: page.total,
      limit: page.limit,
      offset: page.offset,
      hasMore: page.hasMore,
    );
  }

  /// The sessions on this page.
  final List<MediaSession> sessions;

  /// Total sessions matching the query.
  final int total;

  /// The page size the server applied.
  final int limit;

  /// The offset of this page.
  final int offset;

  /// Whether more sessions follow this page.
  final bool hasMore;

  @override
  String toString() => 'MediaSessionList(${sessions.length} of $total)';
}

/// A page of participants.
@immutable
class MediaParticipantList {
  /// Creates a participant list.
  const MediaParticipantList({
    required this.participants,
    required this.total,
    this.limit = 0,
    this.offset = 0,
    this.hasMore = false,
  });

  /// Decodes a participant list from the paginated envelope.
  factory MediaParticipantList.fromJson(Map<String, dynamic> json) {
    final page =
        MediaPage<MediaParticipant>.fromJson(json, MediaParticipant.fromJson);
    return MediaParticipantList(
      participants: page.items,
      total: page.total,
      limit: page.limit,
      offset: page.offset,
      hasMore: page.hasMore,
    );
  }

  /// The participants on this page.
  final List<MediaParticipant> participants;

  /// Total participants.
  final int total;

  /// The page size the server applied.
  final int limit;

  /// The offset of this page.
  final int offset;

  /// Whether more participants follow this page.
  final bool hasMore;

  @override
  String toString() => 'MediaParticipantList(${participants.length} of $total)';
}

/// A generic media resource decoded verbatim — used where a typed model adds
/// no value (overview, usage rows, timeline events, tracks, attendance rows,
/// permission-audit rows, breakout assignments).
@immutable
class MediaResource {
  /// Creates a resource wrapper.
  const MediaResource(this.raw);

  /// Decodes a resource from JSON.
  factory MediaResource.fromJson(Map<String, dynamic> json) =>
      MediaResource(json);

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// The resource identifier, when present.
  String? get id => _str(raw, 'id');

  /// The owning session, when present.
  String? get sessionId => _str(raw, 'session_id');

  /// The creation timestamp, when present.
  String? get createdAt => _str(raw, 'created_at');

  /// Reads an arbitrary field.
  Object? field(String key) => raw[key];

  /// Reads a string field, or `null` when absent or of another type.
  String? stringField(String key) => _str(raw, key);

  /// Reads an integer field, or `null` when absent or of another type.
  int? intField(String key) => _int(raw, key);

  /// Reads a boolean field, or `null` when absent or of another type.
  bool? boolField(String key) {
    final value = raw[key];
    return value is bool ? value : null;
  }

  @override
  String toString() => 'MediaResource(${raw.keys.take(4).join(', ')})';
}

/// `GET /participants/:participantId` — a participant plus its tracks.
@immutable
class MediaParticipantDetail {
  /// Creates a participant detail.
  const MediaParticipantDetail({
    required this.participant,
    required this.tracks,
  });

  /// Decodes `{participant, tracks}`.
  factory MediaParticipantDetail.fromJson(Map<String, dynamic> json) =>
      MediaParticipantDetail(
        participant: MediaParticipant.fromJson(_map(json['participant'])),
        tracks: _objects(json['tracks'])
            .map(MediaResource.fromJson)
            .toList(growable: false),
      );

  /// The participant.
  final MediaParticipant participant;

  /// The participant's persisted tracks (`model.LiveTrack`).
  final List<MediaResource> tracks;
}

/// `GET /sessions/by-join-token` — `{session, valid}`.
@immutable
class MediaJoinTokenResolution {
  /// Creates a resolution.
  const MediaJoinTokenResolution({required this.session, required this.valid});

  /// Decodes `{session, valid}`.
  factory MediaJoinTokenResolution.fromJson(Map<String, dynamic> json) =>
      MediaJoinTokenResolution(
        session: MediaSession.fromJson(_map(json['session'])),
        valid: _bool(json, 'valid'),
      );

  /// The resolved session (without its join token).
  final MediaSession session;

  /// Whether the session currently accepts connections.
  final bool valid;
}

// ── Join / signaling ─────────────────────────────────────────────────────────

/// An ICE server descriptor (`engine.ICEServerConfig`), returned by join and
/// in the signaling `ready` frame.
@immutable
class IceServerConfig {
  /// Creates an ICE server descriptor.
  const IceServerConfig({required this.urls, this.username, this.credential});

  /// Decodes an ICE server descriptor from JSON.
  factory IceServerConfig.fromJson(Map<String, dynamic> json) =>
      IceServerConfig(
        urls: _strings(json['urls']),
        username: _str(json, 'username'),
        credential: _str(json, 'credential'),
      );

  /// Decodes a (possibly `null`) list of descriptors.
  static List<IceServerConfig> listFromJson(Object? value) =>
      _objects(value).map(IceServerConfig.fromJson).toList(growable: false);

  /// STUN/TURN server URLs.
  final List<String> urls;

  /// TURN username.
  final String? username;

  /// TURN credential.
  final String? credential;
}

/// Client capture hints from project settings (`engine.MediaConstraints`).
///
/// These are hints: apply them to your capture and encodings; the server
/// does not transcode. Simulcast is not supported by the SFU — never enable
/// multiple encodings.
@immutable
class MediaConstraints {
  /// Creates constraints.
  const MediaConstraints({
    required this.raw,
    this.maxVideoBitrateKbps,
    this.maxAudioBitrateKbps,
    this.resolution,
    this.fps,
    this.noiseSuppression = false,
    this.echoCancellation = false,
  });

  /// Decodes constraints from JSON.
  factory MediaConstraints.fromJson(Map<String, dynamic> json) =>
      MediaConstraints(
        raw: json,
        maxVideoBitrateKbps: _int(json, 'max_video_bitrate_kbps'),
        maxAudioBitrateKbps: _int(json, 'max_audio_bitrate_kbps'),
        resolution: _str(json, 'resolution'),
        fps: _int(json, 'fps'),
        noiseSuppression: _bool(json, 'noise_suppression'),
        echoCancellation: _bool(json, 'echo_cancellation'),
      );

  /// Maximum video bitrate (kbps).
  final int? maxVideoBitrateKbps;

  /// Maximum audio bitrate (kbps).
  final int? maxAudioBitrateKbps;

  /// Default capture resolution, e.g. `720p`.
  final String? resolution;

  /// Default capture frame rate.
  final int? fps;

  /// Whether to enable noise suppression.
  final bool noiseSuppression;

  /// Whether to enable echo cancellation.
  final bool echoCancellation;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;
}

/// A waiting-room entry (`dto.WaitingEntry`).
@immutable
class MediaWaitingEntry {
  /// Creates a waiting entry.
  const MediaWaitingEntry({
    required this.id,
    required this.sessionId,
    required this.participantId,
    required this.status,
    required this.raw,
    this.position,
    this.reviewedAt,
    this.banReason,
    this.banExpiresAt,
    this.createdAt,
    this.updatedAt,
    this.participant,
  });

  /// Decodes a waiting entry from JSON.
  factory MediaWaitingEntry.fromJson(Map<String, dynamic> json) =>
      MediaWaitingEntry(
        id: _str(json, 'id') ?? '',
        sessionId: _str(json, 'session_id') ?? '',
        participantId: _str(json, 'participant_id') ?? '',
        status: _str(json, 'status') ?? '',
        raw: json,
        position: _int(json, 'position'),
        reviewedAt: _str(json, 'reviewed_at'),
        banReason: _str(json, 'ban_reason'),
        banExpiresAt: _str(json, 'ban_expires_at'),
        createdAt: _str(json, 'created_at'),
        updatedAt: _str(json, 'updated_at'),
        participant: (json['participant'] is Map<String, dynamic>)
            ? MediaParticipant.fromJson(
                json['participant'] as Map<String, dynamic>,
              )
            : null,
      );

  /// Entry identifier.
  final String id;

  /// The session.
  final String sessionId;

  /// The waiting participant.
  final String participantId;

  /// `waiting`, `admitted`, `rejected`, `expired` or `banned`.
  final String status;

  /// Queue position.
  final int? position;

  /// ISO-8601 review timestamp.
  final String? reviewedAt;

  /// Ban reason, when banned.
  final String? banReason;

  /// Ban expiry, when banned with an expiry.
  final String? banExpiresAt;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The waiting participant (embedded in the host queue listing).
  final MediaParticipant? participant;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether the entry is still waiting for a decision.
  bool get isWaiting => status == 'waiting';

  /// Whether the participant was admitted.
  bool get isAdmitted => status == 'admitted';
}

/// The result of `POST /sessions/:sessionId/join` (or
/// `POST /voice-rooms/:roomId/join`).
@immutable
class MediaJoinResult {
  /// Creates a join result.
  const MediaJoinResult({
    required this.participant,
    required this.participantToken,
    required this.admission,
    required this.iceServers,
    required this.mediaConstraints,
    required this.raw,
    this.participantTokenExpiresAt,
    this.waitingEntry,
    this.breakoutRoomId,
    this.signalPath,
  });

  /// Decodes a join response.
  factory MediaJoinResult.fromJson(Map<String, dynamic> json) =>
      MediaJoinResult(
        participant: MediaParticipant.fromJson(_map(json['participant'])),
        participantToken: _str(json, 'participant_token') ?? '',
        participantTokenExpiresAt: _str(json, 'participant_token_expires_at'),
        admission: MediaJoinAdmission.fromWire(_str(json, 'admission')),
        waitingEntry: (json['waiting_entry'] is Map<String, dynamic>)
            ? MediaWaitingEntry.fromJson(
                json['waiting_entry'] as Map<String, dynamic>,
              )
            : null,
        breakoutRoomId: _str(json, 'breakout_room_id'),
        iceServers: IceServerConfig.listFromJson(json['ice_servers']),
        mediaConstraints:
            MediaConstraints.fromJson(_map(json['media_constraints'])),
        signalPath: _str(json, 'signal_path'),
        raw: json,
      );

  /// The caller's participant row.
  final MediaParticipant participant;

  /// The participant token (HMAC, 24h). The SDK stores it automatically and
  /// sends it as `X-Media-Participant-Token` / `?participant_token=`.
  final String participantToken;

  /// ISO-8601 expiry of [participantToken].
  final String? participantTokenExpiresAt;

  /// Whether the participant was admitted or placed in the waiting room.
  final MediaJoinAdmission admission;

  /// The waiting-room entry, when [admission] is `waiting`.
  final MediaWaitingEntry? waitingEntry;

  /// The breakout room the participant is assigned to, if any. Connect
  /// signaling with this `breakout_room_id`.
  final String? breakoutRoomId;

  /// ICE servers to configure the peer connection with.
  final List<IceServerConfig> iceServers;

  /// Client capture hints.
  final MediaConstraints mediaConstraints;

  /// The signaling path, `/v1/media/signal`.
  final String? signalPath;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether the participant is in the waiting room.
  bool get isWaiting => admission == MediaJoinAdmission.waiting;
}

// ── Self-service / permission requests ───────────────────────────────────────

/// A permission request record (`model.PermissionRequest`).
@immutable
class PermissionRequest {
  /// Creates a permission request.
  const PermissionRequest({
    required this.id,
    required this.sessionId,
    required this.participantId,
    required this.projectId,
    required this.requestType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.reason,
    this.reviewedBy,
    this.reviewedAt,
    this.expiresAt,
  });

  /// Decodes a permission request from JSON.
  factory PermissionRequest.fromJson(Map<String, dynamic> json) =>
      PermissionRequest(
        id: _str(json, 'id') ?? '',
        sessionId: _str(json, 'session_id') ?? '',
        participantId: _str(json, 'participant_id') ?? '',
        projectId: _str(json, 'project_id') ?? '',
        requestType: _str(json, 'request_type') ?? '',
        status: _str(json, 'status') ?? '',
        reason: _str(json, 'reason'),
        reviewedBy: _str(json, 'reviewed_by'),
        reviewedAt: _str(json, 'reviewed_at'),
        expiresAt: _str(json, 'expires_at'),
        createdAt: _str(json, 'created_at') ?? '',
        updatedAt: _str(json, 'updated_at') ?? '',
      );

  /// The request's unique identifier.
  final String id;

  /// The session this request belongs to.
  final String sessionId;

  /// The participant who created this request.
  final String participantId;

  /// The owning project.
  final String projectId;

  /// `camera`, `microphone`, `screen`, `stage` or `speaking`.
  final String requestType;

  /// `pending`, `approved`, `denied`, `cancelled` or `expired`.
  final String status;

  /// An optional free-text reason the participant supplied.
  final String? reason;

  /// The participant ID of the reviewer. Null until reviewed.
  final String? reviewedBy;

  /// When the request was reviewed. Null until reviewed.
  final String? reviewedAt;

  /// An optional expiry timestamp.
  final String? expiresAt;

  /// When the request was created.
  final String createdAt;

  /// When the request was last updated.
  final String updatedAt;

  @override
  String toString() => 'PermissionRequest($requestType, $status)';
}

/// The response of every participant self-service action:
/// `{participant, request?}`.
@immutable
class MediaSelfServiceResult {
  /// Creates a self-service result.
  const MediaSelfServiceResult({required this.participant, this.request});

  /// Decodes `{participant, request?}`.
  factory MediaSelfServiceResult.fromJson(Map<String, dynamic> json) =>
      MediaSelfServiceResult(
        participant: MediaParticipant.fromJson(_map(json['participant'])),
        request: (json['request'] is Map<String, dynamic>)
            ? PermissionRequest.fromJson(
                json['request'] as Map<String, dynamic>,
              )
            : null,
      );

  /// The updated participant.
  final MediaParticipant participant;

  /// The created permission request (request-stage / request-camera /
  /// request-microphone / request-screen only).
  final PermissionRequest? request;
}

// ── Breakout rooms / speaker queue ───────────────────────────────────────────

/// A breakout room with its current members (`dto.BreakoutRoom`).
@immutable
class MediaBreakoutRoom {
  /// Creates a breakout room.
  const MediaBreakoutRoom({
    required this.id,
    required this.sessionId,
    required this.title,
    required this.status,
    required this.participantIds,
    required this.raw,
    this.projectId,
    this.createdBy,
    this.participantCount,
    this.createdAt,
    this.endedAt,
    this.updatedAt,
  });

  /// Decodes a breakout room from JSON.
  factory MediaBreakoutRoom.fromJson(Map<String, dynamic> json) =>
      MediaBreakoutRoom(
        id: _str(json, 'id') ?? '',
        sessionId: _str(json, 'session_id') ?? '',
        projectId: _str(json, 'project_id'),
        title: _str(json, 'title') ?? '',
        status: _str(json, 'status') ?? '',
        createdBy: _str(json, 'created_by'),
        participantCount: _int(json, 'participant_count'),
        participantIds: _strings(json['participant_ids']),
        createdAt: _str(json, 'created_at'),
        endedAt: _str(json, 'ended_at'),
        updatedAt: _str(json, 'updated_at'),
        raw: json,
      );

  /// Room identifier (use as `breakout_room_id` on signaling).
  final String id;

  /// The parent session.
  final String sessionId;

  /// The owning project.
  final String? projectId;

  /// Room title.
  final String title;

  /// `open` or `closed`.
  final String status;

  /// The participant who created the room.
  final String? createdBy;

  /// Member count.
  final int? participantCount;

  /// Current members.
  final List<String> participantIds;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 close timestamp.
  final String? endedAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether the room is open.
  bool get isOpen => status == 'open';
}

/// A speaker-queue entry (`model.SpeakerQueueEntry`).
@immutable
class MediaSpeakerQueueEntry {
  /// Creates a speaker-queue entry.
  const MediaSpeakerQueueEntry({
    required this.id,
    required this.sessionId,
    required this.participantId,
    required this.status,
    required this.raw,
    this.projectId,
    this.position,
    this.reason,
    this.priority,
    this.startedAt,
    this.endedAt,
    this.durationSec,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a speaker-queue entry from JSON.
  factory MediaSpeakerQueueEntry.fromJson(Map<String, dynamic> json) =>
      MediaSpeakerQueueEntry(
        id: _str(json, 'id') ?? '',
        sessionId: _str(json, 'session_id') ?? '',
        participantId: _str(json, 'participant_id') ?? '',
        projectId: _str(json, 'project_id'),
        position: _int(json, 'position'),
        status: _str(json, 'status') ?? '',
        reason: _str(json, 'reason'),
        priority: _int(json, 'priority'),
        startedAt: _str(json, 'started_at'),
        endedAt: _str(json, 'ended_at'),
        durationSec: _int(json, 'duration_sec'),
        createdAt: _str(json, 'created_at'),
        updatedAt: _str(json, 'updated_at'),
        raw: json,
      );

  /// Entry identifier.
  final String id;

  /// The session.
  final String sessionId;

  /// The queued participant.
  final String participantId;

  /// The owning project.
  final String? projectId;

  /// Queue position.
  final int? position;

  /// `waiting`, `speaking`, `done` or `removed`.
  final String status;

  /// Optional reason supplied when joining.
  final String? reason;

  /// Priority (-100..100).
  final int? priority;

  /// ISO-8601 turn start.
  final String? startedAt;

  /// ISO-8601 turn end.
  final String? endedAt;

  /// Turn duration in seconds.
  final int? durationSec;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;
}

/// `GET /sessions/:sessionId/speaker-queue` — `{session_id, entries, total}`.
@immutable
class MediaSpeakerQueue {
  /// Creates a speaker queue.
  const MediaSpeakerQueue({
    required this.sessionId,
    required this.entries,
    required this.total,
  });

  /// Decodes `{session_id, entries, total}`.
  factory MediaSpeakerQueue.fromJson(Map<String, dynamic> json) =>
      MediaSpeakerQueue(
        sessionId: _str(json, 'session_id') ?? '',
        entries: _objects(json['entries'])
            .map(MediaSpeakerQueueEntry.fromJson)
            .toList(growable: false),
        total: _int(json, 'total') ?? 0,
      );

  /// The session.
  final String sessionId;

  /// Active entries in order.
  final List<MediaSpeakerQueueEntry> entries;

  /// Entry count.
  final int total;
}

// ── Settings ─────────────────────────────────────────────────────────────────

/// Project media settings (`model.MediaSettings`).
///
/// `simulcast_enabled` and `adaptive_bitrate_enabled` were removed in v0.4.0
/// (never implemented; the SFU is single-layer).
@immutable
class MediaSettings {
  /// Creates settings.
  const MediaSettings({
    required this.raw,
    this.id,
    this.projectId,
    this.enabled = false,
    this.maxSessions,
    this.maxPublishersPerSession,
    this.maxParticipantsPerSession,
    this.maxSessionDurationSec,
    this.connectionTimeoutSec,
    this.voiceRoomsEnabled = false,
    this.webrtcEnabled = false,
    this.stunUrls = const <String>[],
    this.turnEnabled = false,
    this.turnUrl,
    this.turnUsername,
    this.turnCredential,
    this.maxVideoBitrateKbps,
    this.maxAudioBitrateKbps,
    this.defaultResolution,
    this.defaultFps,
    this.noiseSuppression = false,
    this.echoCancellation = false,
    this.waitingRoomDefault = false,
    this.screenShareDefault = false,
    this.moderationEnabled = false,
    this.analyticsEnabled = false,
    this.auditEnabled = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes settings from JSON.
  factory MediaSettings.fromJson(Map<String, dynamic> json) => MediaSettings(
        raw: json,
        id: _str(json, 'id'),
        projectId: _str(json, 'project_id'),
        enabled: _bool(json, 'enabled'),
        maxSessions: _int(json, 'max_sessions'),
        maxPublishersPerSession: _int(json, 'max_publishers_per_session'),
        maxParticipantsPerSession: _int(json, 'max_participants_per_session'),
        maxSessionDurationSec: _int(json, 'max_session_duration_sec'),
        connectionTimeoutSec: _int(json, 'connection_timeout_sec'),
        voiceRoomsEnabled: _bool(json, 'voice_rooms_enabled'),
        webrtcEnabled: _bool(json, 'webrtc_enabled'),
        stunUrls: _strings(json['stun_urls']),
        turnEnabled: _bool(json, 'turn_enabled'),
        turnUrl: _str(json, 'turn_url'),
        turnUsername: _str(json, 'turn_username'),
        turnCredential: _str(json, 'turn_credential'),
        maxVideoBitrateKbps: _int(json, 'max_video_bitrate_kbps'),
        maxAudioBitrateKbps: _int(json, 'max_audio_bitrate_kbps'),
        defaultResolution: _str(json, 'default_resolution'),
        defaultFps: _int(json, 'default_fps'),
        noiseSuppression: _bool(json, 'noise_suppression'),
        echoCancellation: _bool(json, 'echo_cancellation'),
        waitingRoomDefault: _bool(json, 'waiting_room_default'),
        screenShareDefault: _bool(json, 'screen_share_default'),
        moderationEnabled: _bool(json, 'moderation_enabled'),
        analyticsEnabled: _bool(json, 'analytics_enabled'),
        auditEnabled: _bool(json, 'audit_enabled'),
        createdAt: _str(json, 'created_at'),
        updatedAt: _str(json, 'updated_at'),
      );

  /// Settings row identifier.
  final String? id;

  /// Owning project.
  final String? projectId;

  /// Whether Media is enabled (create/start/join refused otherwise).
  final bool enabled;

  /// Concurrent live sessions cap (0 = unlimited).
  final int? maxSessions;

  /// Publishers per session cap.
  final int? maxPublishersPerSession;

  /// Participants per session cap.
  final int? maxParticipantsPerSession;

  /// Maximum session duration in seconds (0 = unlimited).
  final int? maxSessionDurationSec;

  /// Signaling idle timeout in seconds.
  final int? connectionTimeoutSec;

  /// Whether voice rooms are enabled.
  final bool voiceRoomsEnabled;

  /// Whether WebRTC is enabled.
  final bool webrtcEnabled;

  /// STUN URLs.
  final List<String> stunUrls;

  /// Whether TURN is enabled.
  final bool turnEnabled;

  /// TURN URL.
  final String? turnUrl;

  /// TURN username.
  final String? turnUsername;

  /// TURN credential.
  final String? turnCredential;

  /// Max video bitrate hint (kbps).
  final int? maxVideoBitrateKbps;

  /// Max audio bitrate hint (kbps).
  final int? maxAudioBitrateKbps;

  /// Default resolution hint.
  final String? defaultResolution;

  /// Default FPS hint.
  final int? defaultFps;

  /// Noise-suppression hint.
  final bool noiseSuppression;

  /// Echo-cancellation hint.
  final bool echoCancellation;

  /// Default `waiting_room` for new sessions.
  final bool waitingRoomDefault;

  /// Default `screen_share_enabled` for new sessions.
  final bool screenShareDefault;

  /// Whether SDK host moderation is allowed (`MEDIA_MODERATION_DISABLED`
  /// otherwise).
  final bool moderationEnabled;

  /// Whether telemetry is stored.
  final bool analyticsEnabled;

  /// Whether audit logging is enabled.
  final bool auditEnabled;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;
}
