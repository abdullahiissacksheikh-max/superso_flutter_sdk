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

  /// A participant's record changed.
  static const String updated = 'participant_updated';

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
abstract final class MediaClassroomEvents {
  /// A reaction was sent.
  static const String reaction = 'classroom.reaction';

  /// A poll was created.
  static const String pollCreated = 'classroom.poll_created';

  /// A poll was activated.
  static const String pollActivated = 'classroom.poll_activated';

  /// A poll ended.
  static const String pollEnded = 'classroom.poll_ended';

  /// Poll results were published.
  static const String pollResults = 'classroom.poll_results';

  /// A vote was received.
  static const String pollVoteReceived = 'classroom.poll_vote_received';

  /// Attendance was recorded on join.
  static const String attendanceJoined = 'classroom.attendance_joined';

  /// Attendance was recorded on leave.
  static const String attendanceLeft = 'classroom.attendance_left';

  /// A chat message was sent.
  static const String chatMessage = 'classroom.chat_message';

  /// A chat message was pinned.
  static const String chatMessagePinned = 'classroom.chat_message_pinned';

  /// A chat message was unpinned.
  static const String chatMessageUnpinned = 'classroom.chat_message_unpinned';

  /// A chat message was deleted.
  static const String chatMessageDeleted = 'classroom.chat_message_deleted';

  /// A reaction was added to a chat message.
  static const String chatMessageReaction = 'classroom.chat_message_reaction';

  /// A speaker was promoted from the queue.
  static const String speakerPromoted = 'classroom.speaker_promoted';

  /// A speaker's turn ended.
  static const String speakerDone = 'classroom.speaker_done';

  /// The speaker queue changed.
  static const String speakerQueueUpdated = 'classroom.speaker_queue_updated';

  /// A participant's classroom role changed.
  static const String roleChanged = 'classroom.role_changed';

  /// A hand was raised.
  static const String handRaised = 'classroom.hand_raised';

  /// A hand was lowered.
  static const String handLowered = 'classroom.hand_lowered';

  /// A participant was force-muted.
  static const String forceMuted = 'classroom.force_muted';

  /// A force-mute was cleared.
  static const String forceMuteCleared = 'classroom.force_mute_cleared';

  /// The stage was locked.
  static const String stageLocked = 'classroom.stage_locked';

  /// The stage was unlocked.
  static const String stageUnlocked = 'classroom.stage_unlocked';
}

/// Whiteboard event names.
abstract final class MediaWhiteboardEvents {
  /// A whiteboard was opened.
  static const String started = 'classroom.whiteboard_started';

  /// A whiteboard was closed.
  static const String ended = 'classroom.whiteboard_ended';

  /// Draw permissions changed.
  static const String permissionsUpdated =
      'classroom.whiteboard_permissions_updated';

  /// A freehand stroke was added.
  static const String stroke = 'classroom.whiteboard_stroke';

  /// A shape or text object was added.
  static const String objectAdded = 'classroom.whiteboard_object_added';

  /// An object was erased.
  static const String objectRemoved = 'classroom.whiteboard_object_removed';

  /// The canvas was cleared.
  static const String cleared = 'classroom.whiteboard_cleared';

  /// An action was undone.
  static const String undo = 'classroom.whiteboard_undo';

  /// An action was redone.
  static const String redo = 'classroom.whiteboard_redo';

  /// A cursor position was broadcast. Not persisted.
  static const String pointer = 'classroom.whiteboard_pointer';
}

/// Breakout-room, waiting-room, and lobby event names.
abstract final class MediaRoomEvents {
  /// A breakout room was created.
  static const String breakoutCreated = 'breakout.created';

  /// A breakout room was renamed.
  static const String breakoutUpdated = 'breakout.updated';

  /// A breakout room was closed.
  static const String breakoutClosed = 'breakout.closed';

  /// A participant joined a breakout room.
  static const String breakoutParticipantJoined =
      'breakout.participant_joined';

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

  /// A lobby chat message was sent.
  static const String lobbyMessage = 'lobby.message';

  /// A lobby chat message was deleted.
  static const String lobbyDeleted = 'lobby.deleted';

  /// Lobby chat was cleared.
  static const String lobbyCleared = 'lobby.cleared';
}
