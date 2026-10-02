/// The realtime event catalogue for the Media module (channel
/// `media.<sessionId>`).
///
/// Source of truth: `backend/internal/modules/media/service/events.go`.
/// [MediaEvents.all] is exactly the backend's `AllEvents` list (77 names),
/// including the nine permission-decision names (`camera_permission_granted`,
/// ...), which are also grouped in [MediaEvents.permissionDecisions].
///
/// Removed in v0.4.0 (never emitted by the rebuilt backend): every `stage.*`
/// and `classroom.*` name, `publisher_joined`, `subscriber_joined`,
/// `permissions_updated`, `participant_permission_updated`.
library;

/// Session lifecycle event names.
abstract final class MediaSessionEvents {
  /// The session transitioned to live.
  static const String started = 'session_started';

  /// The session configuration changed (`{session}`).
  static const String updated = 'session_updated';

  /// The session ended (`{ended_reason}`).
  static const String ended = 'session_ended';

  /// The session was archived.
  static const String archived = 'session_archived';

  /// The last participant left.
  static const String roomEmpty = 'room_empty';

  /// The last privileged participant left (`{host_left_at, timeout_sec}`).
  static const String hostLeft = 'host_left';

  /// A privileged participant came back before the timeout.
  static const String hostReturned = 'host_returned';
}

/// Participant lifecycle, state and host-moderation event names.
abstract final class MediaParticipantEvents {
  /// A participant joined.
  static const String joined = 'participant_joined';

  /// A participant left (`{duration_sec}`).
  static const String left = 'participant_left';

  /// A participant reconnected within the grace window.
  static const String reconnected = 'participant_reconnected';

  /// A host kicked a participant.
  static const String kicked = 'participant_kicked';

  /// A host banned a participant.
  static const String banned = 'participant_banned';

  /// Camera / microphone / screen state changed.
  static const String mediaStateChanged = 'participant_media_state_changed';

  /// Speaking state changed
  /// (`{participant_id, is_speaking, audio_level, last_spoke_at}`).
  static const String speakingChanged = 'participant_speaking_changed';

  /// The participant's stage state changed.
  static const String stateChanged = 'participant_state_changed';

  /// The participant's classroom role changed (`{role}`).
  static const String roleChanged = 'participant_role_changed';

  /// A participant was promoted to publisher.
  static const String promoted = 'participant_promoted';

  /// A participant was demoted to viewer.
  static const String demoted = 'participant_demoted';

  /// A participant was muted.
  static const String muted = 'participant_muted';

  /// A participant was unmuted.
  static const String unmuted = 'participant_unmuted';

  /// A participant was force-muted.
  static const String forceMuted = 'participant_force_muted';

  /// A force-mute was cleared.
  static const String forceMuteCleared = 'participant_force_mute_cleared';

  /// A participant's video was hidden.
  static const String videoHidden = 'participant_video_hidden';

  /// A participant's video was restored.
  static const String videoVisible = 'participant_video_visible';

  /// A participant was pinned.
  static const String pinned = 'participant_pinned';

  /// A participant was unpinned.
  static const String unpinned = 'participant_unpinned';

  /// A participant was spotlighted.
  static const String spotlighted = 'participant_spotlighted';

  /// A participant's spotlight was removed.
  static const String unspotlighted = 'participant_unspotlighted';
}

/// Stage request / invitation event names.
abstract final class MediaStageEvents {
  /// A participant requested the stage.
  static const String requested = 'participant_requested_stage';

  /// A participant cancelled a pending request.
  static const String cancelled = 'participant_cancelled_request';

  /// A stage request was approved.
  static const String approved = 'participant_stage_approved';

  /// A stage request was rejected.
  static const String rejected = 'participant_stage_rejected';

  /// A host invited a participant onto the stage.
  static const String invited = 'participant_invited_to_stage';

  /// A participant accepted a stage invitation.
  static const String inviteAccepted = 'participant_invite_accepted';

  /// A participant declined a stage invitation.
  static const String inviteDeclined = 'participant_invite_declined';

  /// A participant was removed from the stage.
  static const String removed = 'participant_removed_stage';
}

/// Permission request / decision and screen-share event names.
abstract final class MediaPermissionEvents {
  /// A participant requested camera access.
  static const String cameraRequested = 'camera_requested';

  /// A participant requested microphone access.
  static const String microphoneRequested = 'microphone_requested';

  /// A participant requested screen-share access.
  static const String screenRequested = 'screen_requested';

  /// Camera access was granted.
  static const String cameraGranted = 'camera_permission_granted';

  /// Camera access was revoked.
  static const String cameraRevoked = 'camera_permission_revoked';

  /// A camera request was rejected.
  static const String cameraRejected = 'camera_permission_rejected';

  /// Microphone access was granted.
  static const String microphoneGranted = 'microphone_permission_granted';

  /// Microphone access was revoked.
  static const String microphoneRevoked = 'microphone_permission_revoked';

  /// A microphone request was rejected.
  static const String microphoneRejected = 'microphone_permission_rejected';

  /// Screen-share access was granted.
  static const String screenGranted = 'screen_permission_granted';

  /// Screen-share access was revoked.
  static const String screenRevoked = 'screen_permission_revoked';

  /// A screen-share request was rejected.
  static const String screenRejected = 'screen_permission_rejected';

  /// A screen share started (real labelled track).
  static const String screenShareStarted = 'screen_share_started';

  /// A screen share stopped.
  static const String screenShareStopped = 'screen_share_stopped';
}

/// Voice-room event names.
abstract final class MediaVoiceEvents {
  /// The voice room started.
  static const String roomStarted = 'voice_room.started';

  /// The voice room configuration changed (`{session}`).
  static const String roomUpdated = 'voice_room.updated';

  /// A participant joined the voice room.
  static const String participantJoined = 'voice.participant_joined';

  /// A hand was raised.
  static const String handRaised = 'voice.hand_raised';

  /// A hand was lowered.
  static const String handLowered = 'voice.hand_lowered';

  /// A participant was promoted to speaker.
  static const String speakerPromoted = 'voice.speaker_promoted';

  /// A speaker was moved back to listener.
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
}

/// Breakout-room and waiting-room event names.
abstract final class MediaRoomEvents {
  /// A breakout room was created (`{room}`).
  static const String breakoutCreated = 'breakout.created';

  /// A breakout room was renamed (`{room}`).
  static const String breakoutUpdated = 'breakout.updated';

  /// A breakout room was closed.
  static const String breakoutClosed = 'breakout.closed';

  /// A breakout room was deleted (`{room_id}`).
  static const String breakoutDeleted = 'breakout.deleted';

  /// A participant joined a breakout room (`{room_id}`).
  static const String breakoutParticipantJoined = 'breakout.participant_joined';

  /// A participant left a breakout room (`{room_id}`).
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

/// Attendance event names.
abstract final class MediaAttendanceEvents {
  /// Attendance recorded on join.
  static const String joined = 'attendance.joined';

  /// Attendance recorded on leave.
  static const String left = 'attendance.left';
}

/// Speaker-queue event names.
abstract final class MediaSpeakerQueueEvents {
  /// The queue changed (`{queue}`).
  static const String updated = 'speaker_queue.updated';

  /// A speaker was promoted from the queue.
  static const String promoted = 'speaker_queue.promoted';

  /// A speaker's turn ended.
  static const String done = 'speaker_queue.done';
}

/// The complete Media event catalogue.
abstract final class MediaEvents {
  /// Exactly the backend's `service.AllEvents` (77 names).
  static const Set<String> all = <String>{
    MediaSessionEvents.started,
    MediaSessionEvents.updated,
    MediaSessionEvents.ended,
    MediaSessionEvents.archived,
    MediaSessionEvents.roomEmpty,
    MediaSessionEvents.hostLeft,
    MediaSessionEvents.hostReturned,
    MediaParticipantEvents.joined,
    MediaParticipantEvents.left,
    MediaParticipantEvents.reconnected,
    MediaParticipantEvents.kicked,
    MediaParticipantEvents.banned,
    MediaParticipantEvents.mediaStateChanged,
    MediaParticipantEvents.speakingChanged,
    MediaParticipantEvents.stateChanged,
    MediaParticipantEvents.roleChanged,
    MediaParticipantEvents.promoted,
    MediaParticipantEvents.demoted,
    MediaParticipantEvents.muted,
    MediaParticipantEvents.unmuted,
    MediaParticipantEvents.forceMuted,
    MediaParticipantEvents.forceMuteCleared,
    MediaParticipantEvents.videoHidden,
    MediaParticipantEvents.videoVisible,
    MediaParticipantEvents.pinned,
    MediaParticipantEvents.unpinned,
    MediaParticipantEvents.spotlighted,
    MediaParticipantEvents.unspotlighted,
    MediaStageEvents.requested,
    MediaStageEvents.cancelled,
    MediaStageEvents.approved,
    MediaStageEvents.rejected,
    MediaStageEvents.invited,
    MediaStageEvents.inviteAccepted,
    MediaStageEvents.inviteDeclined,
    MediaStageEvents.removed,
    MediaPermissionEvents.cameraRequested,
    MediaPermissionEvents.microphoneRequested,
    MediaPermissionEvents.screenRequested,
    MediaPermissionEvents.cameraGranted,
    MediaPermissionEvents.cameraRevoked,
    MediaPermissionEvents.cameraRejected,
    MediaPermissionEvents.microphoneGranted,
    MediaPermissionEvents.microphoneRevoked,
    MediaPermissionEvents.microphoneRejected,
    MediaPermissionEvents.screenGranted,
    MediaPermissionEvents.screenRevoked,
    MediaPermissionEvents.screenRejected,
    MediaPermissionEvents.screenShareStarted,
    MediaPermissionEvents.screenShareStopped,
    MediaVoiceEvents.roomStarted,
    MediaVoiceEvents.roomUpdated,
    MediaVoiceEvents.participantJoined,
    MediaVoiceEvents.handRaised,
    MediaVoiceEvents.handLowered,
    MediaVoiceEvents.speakerPromoted,
    MediaVoiceEvents.speakerRemoved,
    MediaVoiceEvents.muted,
    MediaVoiceEvents.unmuted,
    MediaVoiceEvents.hostChanged,
    MediaVoiceEvents.moderatorAdded,
    MediaVoiceEvents.moderatorRemoved,
    MediaRoomEvents.breakoutCreated,
    MediaRoomEvents.breakoutUpdated,
    MediaRoomEvents.breakoutClosed,
    MediaRoomEvents.breakoutDeleted,
    MediaRoomEvents.breakoutParticipantJoined,
    MediaRoomEvents.breakoutParticipantLeft,
    MediaRoomEvents.waitingJoined,
    MediaRoomEvents.waitingAdmitted,
    MediaRoomEvents.waitingRejected,
    MediaRoomEvents.waitingBanned,
    MediaAttendanceEvents.joined,
    MediaAttendanceEvents.left,
    MediaSpeakerQueueEvents.updated,
    MediaSpeakerQueueEvents.promoted,
    MediaSpeakerQueueEvents.done,
  };

  /// The nine moderator permission decisions (grant / revoke / reject of
  /// camera, microphone and screen) — a subset of [all].
  static const Set<String> permissionDecisions = <String>{
    MediaPermissionEvents.cameraGranted,
    MediaPermissionEvents.cameraRevoked,
    MediaPermissionEvents.cameraRejected,
    MediaPermissionEvents.microphoneGranted,
    MediaPermissionEvents.microphoneRevoked,
    MediaPermissionEvents.microphoneRejected,
    MediaPermissionEvents.screenGranted,
    MediaPermissionEvents.screenRevoked,
    MediaPermissionEvents.screenRejected,
  };
}
