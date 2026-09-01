/// The realtime event catalogue for the Media module.
///
/// Dart port of `supersosdk/src/media/events.ts`.
///
/// Every name here was verified against the literal strings the backend
/// actually broadcasts — not against documentation, and not against the
/// JavaScript SDK's earlier revisions, several of which listed events that no
/// backend code ever emitted. Notably the real camera-grant event is
/// `camera_permission_granted`, not `camera_granted`, and there is no
/// `active_speaker` event at all; speaker changes arrive as
/// `voice.speaker_promoted` / `voice.speaker_removed`.
library;

/// Session lifecycle event names.
abstract final class MediaSessionEvents {
  /// The session transitioned to live.
  static const String started = 'session_started';

  /// The session ended.
  static const String ended = 'session_ended';

  /// The session was archived.
  static const String archived = 'session_archived';

  /// The last participant left.
  static const String roomEmpty = 'room_empty';

  /// The host disconnected; the grace period started.
  static const String hostLeft = 'host_left';

  /// The host reconnected before the grace period elapsed.
  static const String hostReturned = 'host_returned';
}

/// Participant lifecycle and state event names.
abstract final class MediaParticipantEvents {
  /// A participant joined.
  static const String joined = 'participant_joined';

  /// A participant left.
  static const String left = 'participant_left';

  /// A participant reconnected within the grace window.
  static const String reconnected = 'participant_reconnected';

  // NOTE: there is no generic `participant_updated` event. It was removed
  // from here in the v0.3.1 Moderation + Waiting Room audit after checking
  // every `broadcastMedia`/`permEvent`/`stageEvent` call site in the Go
  // backend and finding none that emit it — it had slipped in as a
  // plausible-looking but fictitious name, the same class of bug this
  // catalogue's own header comment already warns about. Each moderation
  // action emits its own specifically-named event instead — see [muted],
  // [pinned], [videoHidden], [kicked], etc. below.

  /// A publisher joined.
  static const String publisherJoined = 'publisher_joined';

  /// A subscriber joined.
  static const String subscriberJoined = 'subscriber_joined';

  /// A participant's video tile was hidden.
  static const String videoHidden = 'participant_video_hidden';

  /// A participant's video tile was restored.
  static const String videoVisible = 'participant_video_visible';

  /// A participant was muted.
  static const String muted = 'participant_muted';

  /// A participant was unmuted.
  static const String unmuted = 'participant_unmuted';

  /// A participant was pinned.
  static const String pinned = 'participant_pinned';

  /// A participant was unpinned.
  static const String unpinned = 'participant_unpinned';

  /// A participant was spotlighted.
  static const String spotlighted = 'participant_spotlighted';

  /// A participant's spotlight was removed.
  static const String unspotlighted = 'participant_unspotlighted';

  /// A host (Admin or SDK) kicked a participant from the session.
  ///
  /// Added in v0.3.1: `MediaServices.KickParticipant` previously updated
  /// state and tore down the SFU connection without broadcasting anything —
  /// this name was already documented but not yet actually dispatched. It
  /// now is, alongside every sibling moderation event in this class.
  static const String kicked = 'participant_kicked';

  /// A participant was promoted to publisher.
  static const String promoted = 'participant_promoted';

  /// A participant was demoted to viewer.
  static const String demoted = 'participant_demoted';
}

/// Permission request and decision event names.
abstract final class MediaPermissionEvents {
  /// A participant requested camera access.
  static const String cameraRequested = 'camera_requested';

  /// Camera access was granted.
  static const String cameraGranted = 'camera_permission_granted';

  /// Camera access was revoked.
  static const String cameraRevoked = 'camera_permission_revoked';

  /// A camera request was rejected.
  static const String cameraRejected = 'camera_permission_rejected';

  /// A participant requested microphone access.
  static const String microphoneRequested = 'microphone_requested';

  /// Microphone access was granted.
  static const String microphoneGranted = 'microphone_permission_granted';

  /// Microphone access was revoked.
  static const String microphoneRevoked = 'microphone_permission_revoked';

  /// A microphone request was rejected.
  static const String microphoneRejected = 'microphone_permission_rejected';

  /// A participant requested screen-share access.
  static const String screenRequested = 'screen_requested';

  /// Screen-share access was granted.
  static const String screenGranted = 'screen_permission_granted';

  /// Screen-share access was revoked.
  static const String screenRevoked = 'screen_permission_revoked';

  /// A screen-share request was rejected.
  static const String screenRejected = 'screen_permission_rejected';

  /// A screen share started.
  static const String screenShareStarted = 'screen_share_started';

  /// A screen share stopped.
  static const String screenShareStopped = 'screen_share_stopped';

  /// A participant's permissions changed.
  static const String permissionsUpdated = 'permissions_updated';
}

/// Stage management event names.
abstract final class MediaStageEvents {
  /// A participant requested the stage.
  static const String requested = 'participant_requested_stage';

  /// A participant cancelled their request.
  static const String cancelled = 'participant_cancelled_request';

  /// A stage request was approved.
  static const String approved = 'participant_stage_approved';

  /// A stage request was rejected.
  static const String rejected = 'participant_stage_rejected';

  /// A participant was removed from the stage.
  static const String removed = 'participant_removed_stage';

  /// A participant raised their hand.
  static const String handRaised = 'stage.hand_raised';

  /// A participant lowered their hand.
  ///
  /// Added in v0.3.1 — this catalogue previously had no counterpart to
  /// [handRaised], but the backend does dispatch this real event from
  /// `MediaServices.StageLowerHand`, the self-service `lower-hand` route
  /// behind `lowerHand()`.
  static const String handLowered = 'stage.hand_lowered';

  /// A participant accepted the host's stage invitation.
  ///
  /// Added in v0.3.1. Dispatched by `MediaServices.AcceptStageInvite`, the
  /// self-service route behind `acceptStageInvite()`.
  static const String inviteAccepted = 'stage.invite_accepted';

  /// A participant declined the host's stage invitation.
  ///
  /// Added in v0.3.1. Dispatched by `MediaServices.DeclineStageInvite`, the
  /// self-service route behind `declineStageInvite()`.
  static const String inviteDeclined = 'stage.invite_declined';

  // Screen-share self-service (StageService in service/media_services.go).
  // Distinct from [MediaPermissionEvents.screenShareStarted]/
  // [MediaPermissionEvents.screenShareStopped] below — these two event
  // families come from different subsystems that both happen to touch
  // screen sharing; neither supersedes the other.

  /// A participant signalled intent to share their screen.
  static const String screenShareRequested = 'stage.screen_share_requested';

  /// A host approved a screen-share request.
  static const String screenShareApproved = 'stage.screen_share_approved';

  /// A host rejected a screen-share request.
  static const String screenShareRejected = 'stage.screen_share_rejected';

  /// A host revoked an active screen share.
  static const String screenShareRevoked = 'stage.screen_share_revoked';

  /// A participant stopped their own screen share.
  static const String screenShareStopped = 'stage.screen_share_stopped';
}

/// Voice-room event names.
abstract final class MediaVoiceEvents {
  /// A participant joined the voice room.
  static const String participantJoined = 'voice.participant_joined';

  /// A hand was raised.
  static const String handRaised = 'voice.hand_raised';

  /// A hand was lowered.
  static const String handLowered = 'voice.hand_lowered';

  /// A participant became an active speaker.
  ///
  /// This, with [speakerRemoved], is the real speaker-change signal. There is
  /// no `active_speaker` event.
  static const String speakerPromoted = 'voice.speaker_promoted';

  /// A participant stopped being an active speaker.
  static const String speakerRemoved = 'voice.speaker_removed';

  /// A participant was muted.
  static const String muted = 'voice.muted';

  /// A participant was unmuted.
  static const String unmuted = 'voice.unmuted';

  /// The host changed.
  static const String hostChanged = 'voice.host_changed';

  /// A moderator was added.
  static const String moderatorAdded = 'voice.moderator_added';

  /// A moderator was removed.
  static const String moderatorRemoved = 'voice.moderator_removed';

  /// The voice room started.
  static const String roomStarted = 'voice_room.started';
}

/// Classroom-engine event names.
///
/// This class originally also carried Reactions/Polls/Classroom Hand Raise
/// event names (`classroom.reaction`, `classroom.poll_*`,
/// `classroom.hand_raised`, `classroom.hand_lowered`, `classroom.stage_locked`,
/// `classroom.stage_unlocked`). Those six features (Classroom, Polls,
/// Whiteboard, Reactions, Chat, Webhooks) were removed from Media Core — see
/// docs/media.md. Attendance, Speaker Queue, and Classroom role
/// assignment/force-mute are separate, still-supported features that
/// happened to share this class name; it is kept as-is (not renamed).
abstract final class MediaClassroomEvents {
  /// Attendance was recorded on join.
  static const String attendanceJoined = 'classroom.attendance_joined';

  /// Attendance was recorded on leave.
  static const String attendanceLeft = 'classroom.attendance_left';

  /// A speaker was promoted from the queue.
  static const String speakerPromoted = 'classroom.speaker_promoted';

  /// A speaker's turn ended.
  static const String speakerDone = 'classroom.speaker_done';

  /// The speaker queue changed.
  static const String speakerQueueUpdated = 'classroom.speaker_queue_updated';

  /// A participant's classroom role changed.
  static const String roleChanged = 'classroom.role_changed';

  /// A participant was force-muted.
  static const String forceMuted = 'classroom.force_muted';

  /// A force-mute was cleared.
  static const String forceMuteCleared = 'classroom.force_mute_cleared';
}

/// Breakout-room and waiting-room event names.
abstract final class MediaRoomEvents {
  /// A breakout room was created.
  static const String breakoutCreated = 'breakout.created';

  /// A breakout room was renamed.
  static const String breakoutUpdated = 'breakout.updated';

  /// A breakout room was closed.
  static const String breakoutClosed = 'breakout.closed';

  /// A participant joined a breakout room.
  static const String breakoutParticipantJoined = 'breakout.participant_joined';

  /// A participant left a breakout room.
  static const String breakoutParticipantLeft = 'breakout.participant_left';

  /// A participant entered the waiting room.
  static const String waitingJoined = 'waiting.participant_joined';

  /// A waiting participant was admitted.
  static const String waitingAdmitted = 'waiting.admitted';

  /// A waiting participant was rejected.
  static const String waitingRejected = 'waiting.rejected';

  /// A waiting participant was banned.
  static const String waitingBanned = 'waiting.banned';
}
