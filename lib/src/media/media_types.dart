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
        hostLeaveTimeoutSec:
            (json['host_leave_timeout_sec'] as num?)?.toInt(),
        lastActivityAt: json['last_activity_at'] as String?,
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
    this.cameraEnabled,
    this.screenSharing,
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
        handRaised: json['hand_raised'] as bool?,
        cameraEnabled: json['camera_enabled'] as bool?,
        screenSharing: json['screen_sharing'] as bool?,
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

  /// Whether their hand is raised.
  final bool? handRaised;

  /// Whether their camera is on.
  final bool? cameraEnabled;

  /// Whether they are sharing a screen.
  final bool? screenSharing;

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
      classroomRole?.isPrivileged ??
      (role == MediaParticipantRole.moderator);

  @override
  String toString() =>
      'MediaParticipant(id: $id, ${displayName ?? userId ?? 'guest'}, '
      '${role.wireValue})';
}

/// A generic media resource decoded verbatim.
///
/// The Media module surfaces many small, evolving resources — voice rooms,
/// breakout rooms, waiting-room entries, lobby messages, invitations, links,
/// tracks, timeline events, polls, chat messages, speaker-queue entries,
/// attendance records, whiteboard actions, and analytics.
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

/// A whiteboard, as returned by the whiteboard lifecycle endpoints.
@immutable
class WhiteboardSession {
  /// Creates a whiteboard.
  const WhiteboardSession({
    required this.id,
    required this.sessionId,
    required this.allowParticipantDraw,
    required this.raw,
    this.projectId,
    this.title,
    this.status,
    this.createdBy,
    this.background,
    this.startedAt,
    this.updatedAt,
  });

  /// Decodes a whiteboard from JSON.
  factory WhiteboardSession.fromJson(Map<String, dynamic> json) =>
      WhiteboardSession(
        id: json['id'] as String? ?? '',
        sessionId: json['session_id'] as String? ?? '',
        allowParticipantDraw:
            json['allow_participant_draw'] as bool? ?? false,
        raw: json,
        projectId: json['project_id'] as String?,
        title: json['title'] as String?,
        status: json['status'] as String?,
        createdBy: json['created_by'] as String?,
        background: json['background'] as String?,
        startedAt: json['started_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// Whiteboard identifier.
  ///
  /// Each `start` creates a new whiteboard with a new ID; an ID from a
  /// previous board permanently 404s once superseded.
  final String id;

  /// The session this whiteboard belongs to.
  final String sessionId;

  /// Whether non-privileged participants may draw.
  final bool allowParticipantDraw;

  /// Owning project.
  final String? projectId;

  /// Display title.
  final String? title;

  /// `active` or `ended`.
  final String? status;

  /// The participant who opened it.
  final String? createdBy;

  /// Background style.
  final String? background;

  /// ISO-8601 start timestamp.
  final String? startedAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'WhiteboardSession(id: $id, draw: $allowParticipantDraw)';
}

/// One entry in a whiteboard's replay log.
@immutable
class WhiteboardAction {
  /// Creates a whiteboard action.
  const WhiteboardAction({
    required this.id,
    required this.whiteboardId,
    required this.actionType,
    required this.raw,
    this.participantId,
    this.seq,
    this.objectId,
    this.color,
    this.strokeWidth,
    this.payload,
    this.reverted,
    this.createdAt,
  });

  /// Decodes an action from JSON.
  factory WhiteboardAction.fromJson(Map<String, dynamic> json) =>
      WhiteboardAction(
        id: json['id'] as String? ?? '',
        whiteboardId: json['whiteboard_id'] as String? ?? '',
        actionType: json['action_type'] as String? ?? '',
        raw: json,
        participantId: json['participant_id'] as String?,
        seq: (json['seq'] as num?)?.toInt(),
        objectId: json['object_id'] as String?,
        color: json['color'] as String?,
        strokeWidth: (json['stroke_width'] as num?)?.toDouble(),
        payload: json['payload'],
        reverted: json['reverted'] as bool?,
        createdAt: json['created_at'] as String?,
      );

  /// Action identifier.
  final String id;

  /// The whiteboard this action belongs to.
  final String whiteboardId;

  /// `draw`, `shape`, `text`, `erase`, `clear`, `undo`, or `redo`.
  final String actionType;

  /// The participant who performed it.
  final String? participantId;

  /// Monotonic sequence number. Replay in ascending order.
  final int? seq;

  /// The client-supplied stable object identifier.
  final String? objectId;

  /// Stroke or fill colour.
  final String? color;

  /// Stroke width.
  final double? strokeWidth;

  /// Geometry or text content, opaque to the backend.
  final Object? payload;

  /// Whether this action has been undone.
  final bool? reverted;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'WhiteboardAction(seq: $seq, $actionType, object: $objectId)';
}

/// The full replay log for a whiteboard.
@immutable
class WhiteboardActionLog {
  /// Creates a replay log.
  const WhiteboardActionLog({
    required this.whiteboardId,
    required this.actions,
    required this.total,
  });

  /// Decodes a replay log from JSON.
  factory WhiteboardActionLog.fromJson(Map<String, dynamic> json) =>
      WhiteboardActionLog(
        whiteboardId: json['whiteboard_id'] as String? ?? '',
        actions: (json['actions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(WhiteboardAction.fromJson)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  /// The whiteboard this log belongs to.
  final String whiteboardId;

  /// Every current action, in replay order.
  final List<WhiteboardAction> actions;

  /// How many actions there are.
  final int total;

  @override
  String toString() =>
      'WhiteboardActionLog($whiteboardId, ${actions.length} actions)';
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
  String toString() =>
      'MediaSessionList(${sessions.length} of $total)';
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
  String toString() =>
      'MediaParticipantList(${participants.length} of $total)';
}
