/// Domain models for the Media module, mirrored from `docs/media.md`.
///
/// Dart port of `supersosdk/src/media/{types,requests,responses,enums}.ts`.
library;

import 'package:meta/meta.dart';

/// Session lifecycle state.
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

/// Why a session ended.
enum MediaSessionEndedReason {
  /// The host ended it explicitly.
  hostEnded('host_ended'),

  /// The last participant left.
  roomEmpty('room_empty'),

  /// The host left and never returned within the grace period.
  hostLeaveTimeout('host_leave_timeout'),

  /// An operator ended it from the dashboard.
  dashboard('dashboard'),

  /// The server shut down.
  shutdown('shutdown');

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

/// A participant's role in a session.
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

/// A participant's classroom role, in ascending privilege order.
///
/// The roles carrying moderation authority are [owner], [teacher],
/// [assistantTeacher], [coHost], and [moderator] — see [isPrivileged].
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

  /// Created the session.
  owner('owner'),

  /// An unauthenticated attendee.
  guest('guest'),

  /// An attendee from outside the project.
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

  /// The roles assignable through `moderation.assignRole`.
  ///
  /// [owner] is bootstrap-only and the guest roles are assigned by the join
  /// flow, so neither can be granted by a moderator.
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

/// A live media session.
@immutable
class MediaSession {
  /// Creates a session.
  const MediaSession({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.raw,
    this.type,
    this.visibility,
    this.hostParticipantId,
    this.createdBy,
    this.joinToken,
    this.participantCount,
    this.endedReason,
    this.startedAt,
    this.endedAt,
    this.archivedAt,
    this.hostLeftAt,
    this.hostLeaveTimeoutSec,
    this.lastActivityAt,
    this.sessionMode,
    this.classroomMode,
    this.attendanceEnabled,
    this.reactionsEnabled,
    this.pollsEnabled,
    this.stageLocked,
    this.speakerTimerSeconds,
    this.allowSelfUnmute,
    this.topic,
    this.spatialAudioEnabled,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a session from JSON.
  factory MediaSession.fromJson(Map<String, dynamic> json) => MediaSession(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: MediaSessionStatus.fromWire(json['status'] as String?),
        raw: json,
        type: json['type'] as String?,
        visibility: json['visibility'] as String?,
        hostParticipantId: json['host_participant_id'] as String?,
        createdBy: json['created_by'] as String?,
        joinToken: json['join_token'] as String?,
        participantCount: (json['participant_count'] as num?)?.toInt(),
        endedReason:
            MediaSessionEndedReason.fromWire(json['ended_reason'] as String?),
        startedAt: json['started_at'] as String?,
        endedAt: json['ended_at'] as String?,
        archivedAt: json['archived_at'] as String?,
        hostLeftAt: json['host_left_at'] as String?,
        hostLeaveTimeoutSec: (json['host_leave_timeout_sec'] as num?)?.toInt(),
        lastActivityAt: json['last_activity_at'] as String?,
        // Enterprise v7 (migration 010) classroom configuration. Matches
        // supersosdk's MediaSession fields — see that file's changelog note:
        // the backend previously never returned these at all.
        sessionMode: json['session_mode'] as String?,
        classroomMode: json['classroom_mode'] as bool?,
        attendanceEnabled: json['attendance_enabled'] as bool?,
        reactionsEnabled: json['reactions_enabled'] as bool?,
        pollsEnabled: json['polls_enabled'] as bool?,
        stageLocked: json['stage_locked'] as bool?,
        speakerTimerSeconds: (json['speaker_timer_seconds'] as num?)?.toInt(),
        allowSelfUnmute: json['allow_self_unmute'] as bool?,
        topic: json['topic'] as String?,
        spatialAudioEnabled: json['spatial_audio_enabled'] as bool?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// Session identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// Display title.
  final String title;

  /// Lifecycle state.
  final MediaSessionStatus status;

  /// Session type, e.g. `conference`, `classroom`, `webinar`.
  final String? type;

  /// Visibility, e.g. `public` or `private`.
  final String? visibility;

  /// The participant designated as host.
  final String? hostParticipantId;

  /// The end user who created this session.
  ///
  /// Set from their access token at creation time; this is what lets that user
  /// bootstrap into the session's host on first join.
  final String? createdBy;

  /// Token that resolves this session without knowing its ID.
  final String? joinToken;

  /// Participants currently joined.
  final int? participantCount;

  /// Why the session ended.
  final MediaSessionEndedReason? endedReason;

  /// ISO-8601 start timestamp.
  final String? startedAt;

  /// ISO-8601 end timestamp.
  final String? endedAt;

  /// ISO-8601 archive timestamp.
  final String? archivedAt;

  /// ISO-8601 timestamp the host left, starting the grace period.
  final String? hostLeftAt;

  /// How long the session survives without a host, in seconds.
  final int? hostLeaveTimeoutSec;

  /// ISO-8601 timestamp of the last activity.
  final String? lastActivityAt;

  // ── Enterprise v7 (migration 010) classroom configuration ────────────────

  /// High-level mode: `conference`, `classroom`, `webinar`, or `voice`.
  final String? sessionMode;

  /// Whether the classroom feature set (attendance/polls/reactions/stage
  /// lock) is active for this session.
  final bool? classroomMode;

  /// Whether join/leave events are tracked for this session.
  final bool? attendanceEnabled;

  /// Whether emoji reactions are allowed during the session.
  final bool? reactionsEnabled;

  /// Whether the host may create and launch polls.
  final bool? pollsEnabled;

  /// Whether new stage requests / hand-raise approvals are currently
  /// blocked. Set by `classroom.lockStage`/`unlockStage` (host only).
  final bool? stageLocked;

  /// Per-speaker time limit in seconds; `0` means unlimited.
  final int? speakerTimerSeconds;

  /// When `false`, only the host/teacher can unmute a participant.
  final bool? allowSelfUnmute;

  /// Optional session topic / agenda.
  final String? topic;

  /// Placeholder for future spatial-audio support.
  final bool? spatialAudioEnabled;

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

/// A participant in a session or voice room.
@immutable
class MediaParticipant {
  /// Creates a participant.
  const MediaParticipant({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.raw,
    this.userId,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.email,
    this.classroomRole,
    this.voiceRole,
    this.isGuest,
    this.isMuted,
    this.isPinned,
    this.isSpotlighted,
    this.forceMuted,
    this.handRaised,
    this.handRaisedAt,
    this.cameraEnabled,
    this.screenSharing,
    this.isSpeaking,
    this.audioLevel,
    this.lastSpokeAt,
    this.totalSpokeSec,
    this.screenPermission,
    this.screenRequestedAt,
    this.screenStartedAt,
    this.status,
    this.joinedAt,
    this.leftAt,
  });

  /// Decodes a participant from JSON.
  factory MediaParticipant.fromJson(Map<String, dynamic> json) =>
      MediaParticipant(
        id: json['id'] as String? ?? '',
        sessionId: json['session_id'] as String? ?? '',
        role: MediaParticipantRole.fromWire(json['role'] as String?),
        raw: json,
        userId: json['user_id'] as String?,
        displayName: json['display_name'] as String?,
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        email: json['email'] as String?,
        classroomRole: json['classroom_role'] == null
            ? null
            : ClassroomRole.fromWire(json['classroom_role'] as String?),
        voiceRole: json['voice_role'] as String?,
        isGuest: json['is_guest'] as bool?,
        isMuted: json['is_muted'] as bool?,
        isPinned: json['is_pinned'] as bool?,
        isSpotlighted: json['is_spotlighted'] as bool?,
        forceMuted: json['force_muted'] as bool?,
        // The backend has no `hand_raised` boolean field — only
        // `hand_raised_at` (nullable timestamp, docs/media.md §14.7). This
        // derives the boolean from it instead of reading a key that never
        // appears in any real response.
        handRaised: json['hand_raised_at'] != null,
        handRaisedAt: json['hand_raised_at'] as String?,
        cameraEnabled: json['camera_enabled'] as bool?,
        // The backend's real field is `screen_share_active` (docs/media.md
        // §33's Go model, `screen_share_active`), not `screen_sharing`.
        screenSharing: json['screen_share_active'] as bool?,
        isSpeaking: json['is_speaking'] as bool?,
        audioLevel: (json['audio_level'] as num?)?.toDouble(),
        lastSpokeAt: json['last_spoke_at'] as String?,
        totalSpokeSec: (json['total_spoke_sec'] as num?)?.toInt(),
        screenPermission: json['screen_permission'] as bool?,
        screenRequestedAt: json['screen_requested_at'] as String?,
        screenStartedAt: json['screen_started_at'] as String?,
        status: json['status'] as String?,
        joinedAt: json['joined_at'] as String?,
        leftAt: json['left_at'] as String?,
      );

  /// Participant identifier. This is what every moderation call targets.
  final String id;

  /// The session this participation belongs to.
  final String sessionId;

  /// The participant's session role.
  final MediaParticipantRole role;

  /// The authenticated user, or `null` for a guest.
  final String? userId;

  /// Display name. Resolved from Auth for authenticated users.
  final String? displayName;

  /// Username. Resolved from Auth.
  final String? username;

  /// Avatar URL. Resolved from Auth.
  final String? avatarUrl;

  /// Email. Resolved from Auth.
  final String? email;

  /// Classroom role, when the session is in classroom mode.
  final ClassroomRole? classroomRole;

  /// Voice-room role, when the session is a voice room.
  final String? voiceRole;

  /// Whether this participant is unauthenticated.
  final bool? isGuest;

  /// Whether the microphone is muted.
  final bool? isMuted;

  /// Whether the participant is pinned in every viewer's layout.
  final bool? isPinned;

  /// Whether the participant is spotlighted.
  final bool? isSpotlighted;

  /// Whether a host has force-muted them, preventing self-unmute.
  final bool? forceMuted;

  /// Whether their hand is raised. Derived from [handRaisedAt].
  final bool? handRaised;

  /// ISO-8601 timestamp of when their hand was raised, or `null` if not
  /// currently raised (docs/media.md §14.7).
  final String? handRaisedAt;

  /// Whether their camera is on.
  final bool? cameraEnabled;

  /// Whether they are sharing a screen (`screen_share_active`).
  final bool? screenSharing;

  /// Whether they are currently producing audio (Voice Rooms).
  final bool? isSpeaking;

  /// Audio level, 0–100 (Voice Rooms).
  final double? audioLevel;

  /// ISO-8601 timestamp of their last audio activity (Voice Rooms).
  final String? lastSpokeAt;

  /// Cumulative speaking seconds (Voice Rooms).
  final int? totalSpokeSec;

  /// Whether the host has granted this participant screen-share permission.
  final bool? screenPermission;

  /// ISO-8601 timestamp of their last screen-share request.
  final String? screenRequestedAt;

  /// ISO-8601 timestamp their screen share was last approved/started.
  final String? screenStartedAt;

  /// Participation status, e.g. `joined`, `left`, `kicked`, `banned`.
  final String? status;

  /// ISO-8601 join timestamp.
  final String? joinedAt;

  /// ISO-8601 leave timestamp.
  final String? leftAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether this participant carries moderation authority.
  bool get isPrivileged =>
      classroomRole?.isPrivileged ?? (role == MediaParticipantRole.moderator);

  @override
  String toString() =>
      'MediaParticipant(id: $id, ${displayName ?? userId ?? 'guest'}, '
      '${role.wireValue})';
}

/// A generic media resource decoded verbatim.
///
/// The Media module surfaces many small, evolving resources — voice rooms,
/// breakout rooms, waiting-room entries, tracks, timeline events, polls,
/// speaker-queue entries, attendance records, and analytics.
///
/// Rather than freeze a partial typed model for each — which would silently
/// drop fields as the platform evolves, and force an SDK release for every
/// backend addition — these decode into this wrapper. The common fields are
/// surfaced as typed getters, and everything else stays reachable through
/// [raw] and [field].
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
  String? get id => raw['id'] as String?;

  /// The owning session, when present.
  String? get sessionId => raw['session_id'] as String?;

  /// The creation timestamp, when present.
  String? get createdAt => raw['created_at'] as String?;

  /// Reads an arbitrary field.
  Object? field(String key) => raw[key];

  /// Reads a string field, or `null` when absent or of another type.
  String? stringField(String key) => raw[key] as String?;

  /// Reads an integer field, or `null` when absent or of another type.
  int? intField(String key) => (raw[key] as num?)?.toInt();

  /// Reads a boolean field, or `null` when absent or of another type.
  bool? boolField(String key) => raw[key] as bool?;

  @override
  String toString() => 'MediaResource(${raw.keys.take(4).join(', ')})';
}

/// A page of sessions.
@immutable
class MediaSessionList {
  /// Creates a session list.
  const MediaSessionList({required this.sessions, required this.total});

  /// Decodes a session list from JSON.
  factory MediaSessionList.fromJson(Map<String, dynamic> json) =>
      MediaSessionList(
        sessions: (json['sessions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MediaSession.fromJson)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  /// The sessions on this page.
  final List<MediaSession> sessions;

  /// Total sessions matching the query.
  final int total;

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
  });

  /// Decodes a participant list from JSON.
  factory MediaParticipantList.fromJson(Map<String, dynamic> json) =>
      MediaParticipantList(
        participants:
            (json['participants'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .map(MediaParticipant.fromJson)
                .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  /// The participants on this page.
  final List<MediaParticipant> participants;

  /// Total participants.
  final int total;

  @override
  String toString() => 'MediaParticipantList(${participants.length} of $total)';
}

/// A pending, approved, denied, or cancelled permission request.
///
/// Returned by `MediaPermissionsModule.requestCamera()`/`requestMicrophone()`/
/// `requestScreen()` (`backend/internal/modules/media/dto/permission_dto.go`'s
/// `PermissionRequestResponse`, docs/media.md §39 "Unified Request System").
///
/// Added in v0.3.1: these three methods previously declared and decoded
/// their response as [MediaParticipant], but the backend actually returns
/// this differently-shaped object — a request record, not a participant.
/// Every field here mirrors the real JSON keys the backend serializes;
/// `reviewedBy`/`reviewedAt`/`expiresAt` are `omitempty` on the Go side and
/// so are nullable here too. `expiresAt` is part of the schema but not yet
/// enforced by any backend expiration sweep — see docs/media.md's "Unified
/// Request System" section, which documents `expired` as "TTL-based —
/// future implementation".
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
        id: json['id'] as String? ?? '',
        sessionId: json['session_id'] as String? ?? '',
        participantId: json['participant_id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        requestType: json['request_type'] as String? ?? '',
        status: json['status'] as String? ?? '',
        reason: json['reason'] as String?,
        reviewedBy: json['reviewed_by'] as String?,
        reviewedAt: json['reviewed_at'] as String?,
        expiresAt: json['expires_at'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );

  /// The request's unique identifier.
  final String id;

  /// The session this request belongs to.
  final String sessionId;

  /// The participant who created this request.
  final String participantId;

  /// The owning project.
  final String projectId;

  /// What is being requested: `camera`, `microphone`, `screen`, `stage`, or
  /// `speaking`.
  final String requestType;

  /// The request's current lifecycle state: `pending`, `approved`, `denied`,
  /// `cancelled`, or (schema-only; not yet produced by any backend sweep)
  /// `expired`.
  final String status;

  /// An optional free-text reason the participant supplied.
  final String? reason;

  /// The participant ID of the host/moderator who reviewed this request.
  /// Null until reviewed.
  final String? reviewedBy;

  /// When the request was reviewed. Null until reviewed.
  final String? reviewedAt;

  /// An optional expiry timestamp. Present in the schema but never
  /// currently set by any backend code path.
  final String? expiresAt;

  /// When the request was created.
  final String createdAt;

  /// When the request was last updated.
  final String updatedAt;

  @override
  String toString() => 'PermissionRequest($requestType, $status)';
}
