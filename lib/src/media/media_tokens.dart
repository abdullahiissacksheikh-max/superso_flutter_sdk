/// Participant-token storage for the Media module.
///
/// `POST /sessions/:sessionId/join` (and the signaling `ready` frame) issue a
/// participant token: an HMAC-signed credential that proves "I am participant
/// X of session Y" (contract §2). It is the only way a guest can prove who
/// they are, and it lets any client resume the same participant row. The SDK
/// stores it here automatically and attaches it as the
/// `X-Media-Participant-Token` header on self-service REST calls and as the
/// `participant_token` query parameter on the signaling socket.
library;

import 'package:meta/meta.dart';

/// The REST header carrying a participant token.
const String mediaParticipantTokenHeader = 'X-Media-Participant-Token';

/// One stored participant credential.
@immutable
class MediaParticipantCredential {
  /// Creates a credential.
  const MediaParticipantCredential({
    required this.sessionId,
    required this.participantId,
    required this.token,
    this.expiresAt,
  });

  /// The session the token is scoped to.
  final String sessionId;

  /// The participant the token proves.
  final String participantId;

  /// The token itself.
  final String token;

  /// ISO-8601 expiry, when known.
  final String? expiresAt;
}

/// In-memory store of participant tokens, shared by every Media sub-module.
///
/// Exposed at `superso.media.tokens`. Tokens live for the lifetime of the
/// `Superso` instance; persist [MediaParticipantCredential.token] yourself if
/// you want to resume a participant after an app restart, and put it back
/// with [store].
class MediaParticipantTokens {
  final Map<String, MediaParticipantCredential> _byParticipant =
      <String, MediaParticipantCredential>{};
  final Map<String, String> _participantBySession = <String, String>{};

  /// Stores (or replaces) the token of [participantId] in [sessionId]. The
  /// most recently stored participant becomes the session's default.
  void store({
    required String sessionId,
    required String participantId,
    required String token,
    String? expiresAt,
  }) {
    if (token.isEmpty) return;
    _byParticipant[participantId] = MediaParticipantCredential(
      sessionId: sessionId,
      participantId: participantId,
      token: token,
      expiresAt: expiresAt,
    );
    _participantBySession[sessionId] = participantId;
  }

  /// The token of [participantId], if stored.
  String? forParticipant(String participantId) =>
      _byParticipant[participantId]?.token;

  /// The default (most recently stored) token for [sessionId], if any.
  String? forSession(String sessionId) => credentialForSession(sessionId)?.token;

  /// The default credential for [sessionId], if any.
  MediaParticipantCredential? credentialForSession(String sessionId) {
    final participantId = _participantBySession[sessionId];
    return participantId == null ? null : _byParticipant[participantId];
  }

  /// Forgets every token of [sessionId].
  void clearSession(String sessionId) {
    _participantBySession.remove(sessionId);
    _byParticipant.removeWhere((_, c) => c.sessionId == sessionId);
  }

  /// Forgets the token of [participantId].
  void clearParticipant(String participantId) {
    final removed = _byParticipant.remove(participantId);
    if (removed != null &&
        _participantBySession[removed.sessionId] == participantId) {
      _participantBySession.remove(removed.sessionId);
    }
  }

  /// Forgets every token.
  void clear() {
    _byParticipant.clear();
    _participantBySession.clear();
  }
}
