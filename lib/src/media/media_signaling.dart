/// Raw WebRTC signaling transport for the Media module (docs/media.md §24
/// "WebSocket Events", `GET /v1/media/signal`).
///
/// Dart port of `supersosdk/src/media/{signaling,connection,websocket}.ts`.
///
/// This class owns the documented signaling transport ONLY — exactly like
/// the JS SDK (see `connection.ts`'s own doc comment), it does not bundle a
/// WebRTC media-capture engine. No such dependency is present in this
/// package: the host Flutter application supplies its own WebRTC plugin
/// (e.g. `flutter_webrtc`) and wires its `RTCPeerConnection`'s
/// offer/answer/ICE-candidate calls through the connection this class
/// exposes, exactly as a browser application wires its native
/// `RTCPeerConnection` through the JS SDK's `MediaConnection`.
///
/// This class is built on the same shared [RealtimeSocket] transport the
/// Realtime, Storage, and Media-events modules already use (see
/// `realtime_socket.dart`'s own doc comment on why it is shared) — it needs
/// exactly the same connect/reconnect/backoff/heartbeat machinery, just
/// without the Realtime protocol's `subscribe` framing, since the signaling
/// wire format (docs/media.md §24.1) is its own fixed vocabulary of
/// `ready`/`offer`/`answer`/`ice_candidate`/`ping`/`pong`/`error` frames.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../client/superso_http_client.dart';
import '../config/superso_config.dart';
import '../errors/superso_error.dart';
import '../realtime/realtime_socket.dart';

/// `publisher` or `subscriber` — see docs/media.md §12/§13.
enum SignalingRole {
  /// Sends media tracks; may also receive.
  publisher('publisher'),

  /// Receives every active publisher's tracks.
  subscriber('subscriber');

  const SignalingRole(this.wireValue);

  /// The value sent as the `role` query parameter.
  final String wireValue;
}

/// docs/media.md §24.1 — an ICE server descriptor sent by the server in the
/// `ready` message. The application's WebRTC peer connection must be
/// configured with these before creating (publisher) or answering
/// (subscriber) an offer.
@immutable
class IceServerConfig {
  /// Creates an ICE server descriptor.
  const IceServerConfig({required this.urls, this.username, this.credential});

  /// Decodes an ICE server descriptor from JSON.
  factory IceServerConfig.fromJson(Map<String, dynamic> json) =>
      IceServerConfig(
        urls: (json['urls'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
        username: json['username'] as String?,
        credential: json['credential'] as String?,
      );

  /// STUN/TURN server URLs, e.g. `stun:stun.l.google.com:19302`.
  final List<String> urls;

  /// TURN username, when [urls] includes a TURN server.
  final String? username;

  /// TURN credential, when [urls] includes a TURN server.
  final String? credential;
}

/// docs/media.md §24.1 — the `ready` message payload, sent immediately after
/// connect, before any SDP exchange.
@immutable
class MediaSignalingReady {
  /// Creates a ready event.
  const MediaSignalingReady({this.role, required this.iceServers});

  /// The role the server confirmed for this connection.
  final SignalingRole? role;

  /// ICE servers the peer connection must be configured with.
  final List<IceServerConfig> iceServers;
}

/// A trickle ICE candidate exchanged over the signaling channel.
@immutable
class IceCandidatePayload {
  /// Creates an ICE candidate payload.
  const IceCandidatePayload({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  /// Decodes an ICE candidate from its wire shape (`docs/media.md` §24.1:
  /// `{ candidate, sdpMid, sdpMLineIndex }`).
  factory IceCandidatePayload.fromJson(Map<String, dynamic> json) =>
      IceCandidatePayload(
        candidate: json['candidate'] as String? ?? '',
        sdpMid: json['sdpMid'] as String?,
        sdpMLineIndex: (json['sdpMLineIndex'] as num?)?.toInt(),
      );

  /// Encodes this candidate for the `ice_candidate` client→server frame.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };

  /// The candidate string, as produced by the local WebRTC stack.
  final String candidate;

  /// The media stream identification tag.
  final String? sdpMid;

  /// The index (starting at 0) of the m-line this candidate belongs to.
  final int? sdpMLineIndex;
}

/// A session description (offer/answer) exchanged over the signaling
/// channel.
@immutable
class SessionDescriptionPayload {
  /// Creates a session description payload.
  const SessionDescriptionPayload({required this.type, required this.sdp});

  /// `offer` or `answer`.
  final String type;

  /// The SDP string.
  final String sdp;
}

/// A protocol or auth error sent by the signaling server.
@immutable
class MediaSignalingError {
  /// Creates a signaling error.
  const MediaSignalingError({required this.code, required this.message});

  /// The machine-readable error code, e.g. `SDP_ERROR`.
  final String code;

  /// A human-readable description.
  final String message;

  @override
  String toString() => 'MediaSignalingError($code: $message)';
}

/// Snapshot of a [MediaSignalingConnection]'s current state, session, and
/// role.
@immutable
class MediaSignalingInfo {
  /// Creates a connection info snapshot.
  const MediaSignalingInfo({
    required this.state,
    this.sessionId,
    this.role,
    required this.reconnectAttempts,
  });

  /// The current connection state.
  final RealtimeConnectionState state;

  /// The session this connection is scoped to, once [MediaSignalingConnection.connect] has been called.
  final String? sessionId;

  /// The role this connection was opened with.
  final SignalingRole? role;

  /// How many reconnect attempts have been made since the last successful
  /// connection.
  final int reconnectAttempts;
}

/// Owns the single raw WebRTC signaling socket for a session
/// (`GET /v1/media/signal?session_id=&role=`): exchanges
/// ready/offer/answer/ice_candidate/ping frames, and reconnects
/// automatically with the documented exponential backoff
/// (100ms→200ms→400ms→800ms→1600ms→...→30s cap) after an unexpected close.
///
/// Exposed at `superso.media.websocket`, and returned scoped to a role by
/// `superso.media.publishers.join()` / `superso.media.subscribers.join()`.
class MediaSignalingConnection {
  /// Creates a signaling connection bound to [client].
  MediaSignalingConnection(this._client);

  final SupersoHttpClient _client;

  RealtimeSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _sessionId;
  SignalingRole? _role;

  final StreamController<MediaSignalingReady> _readyCtrl =
      StreamController<MediaSignalingReady>.broadcast();
  final StreamController<SessionDescriptionPayload> _offerCtrl =
      StreamController<SessionDescriptionPayload>.broadcast();
  final StreamController<SessionDescriptionPayload> _answerCtrl =
      StreamController<SessionDescriptionPayload>.broadcast();
  final StreamController<IceCandidatePayload> _iceCandidateCtrl =
      StreamController<IceCandidatePayload>.broadcast();
  final StreamController<Map<String, dynamic>> _participantJoinedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _participantLeftCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>?> _sessionEndedCtrl =
      StreamController<Map<String, dynamic>?>.broadcast();
  final StreamController<MediaSignalingError> _errorCtrl =
      StreamController<MediaSignalingError>.broadcast();
  final StreamController<void> _authMissingCtrl =
      StreamController<void>.broadcast();

  /// Sent immediately after connect, before any SDP exchange. `iceServers`
  /// MUST be used to configure the peer connection before it creates an
  /// offer (publisher) or waits for one (subscriber) — see §12/§13.
  Stream<MediaSignalingReady> get onReady => _readyCtrl.stream;

  /// An SDP offer from the server (subscriber role).
  Stream<SessionDescriptionPayload> get onOffer => _offerCtrl.stream;

  /// An SDP answer from the server (publisher role).
  Stream<SessionDescriptionPayload> get onAnswer => _answerCtrl.stream;

  /// A trickle ICE candidate from the server.
  Stream<IceCandidatePayload> get onIceCandidate => _iceCandidateCtrl.stream;

  /// Another participant joined the session.
  Stream<Map<String, dynamic>> get onParticipantJoined =>
      _participantJoinedCtrl.stream;

  /// Another participant disconnected.
  Stream<Map<String, dynamic>> get onParticipantLeft =>
      _participantLeftCtrl.stream;

  /// The session ended.
  Stream<Map<String, dynamic>?> get onSessionEnded => _sessionEndedCtrl.stream;

  /// A protocol or auth error was sent by the server.
  Stream<MediaSignalingError> get onError => _errorCtrl.stream;

  /// Fired on connect (and on every reconnect) when no end-user access token
  /// is set — the backend will record this participant as a Guest. Never
  /// fired when a token is present. Mirrors `auth_missing` on the JS SDK's
  /// `MediaConnection`.
  Stream<void> get onAuthMissing => _authMissingCtrl.stream;

  /// The current connection state.
  RealtimeConnectionState get state =>
      _socket?.state ?? RealtimeConnectionState.disconnected;

  /// Connection state transitions.
  Stream<RealtimeConnectionState> get connectionState =>
      _socket?.connectionState ?? const Stream<RealtimeConnectionState>.empty();

  /// Whether the socket is currently connected.
  bool get isConnected => _socket?.isConnected ?? false;

  /// Snapshot of the connection's current state, session, role, and
  /// reconnect-attempt count.
  MediaSignalingInfo info() => MediaSignalingInfo(
        state: state,
        sessionId: _sessionId,
        role: _role,
        reconnectAttempts: _socket?.reconnectAttempts ?? 0,
      );

  /// Opens the signaling socket for [sessionId] in [role], resolving once
  /// the connection is open.
  Future<void> connect(String sessionId, SignalingRole role) async {
    _sessionId = sessionId;
    _role = role;
    await _open();
  }

  /// Closes the connection. No automatic reconnect follows an explicit
  /// disconnect.
  Future<void> disconnect() async {
    await _socket?.disconnect();
  }

  /// Requests an ICE restart. This transport has no ICE state of its own
  /// (that lives on the application's peer connection); this forces a fresh
  /// signaling socket so the application can immediately follow up with a
  /// new offer (ICE restart) over the reconnected channel.
  Future<void> restartIce() async {
    if (_sessionId == null || _role == null) {
      throw const SupersoError(
        message:
            'Superso: cannot restart ICE before connect() has been called.',
        code: 'SOCKET_NOT_CONNECTED',
      );
    }
    await _socket?.disconnect();
    await _open();
  }

  /// Sends an SDP offer (publisher role).
  void sendOffer(String sdp) => _send(<String, dynamic>{'type': 'offer', 'sdp': sdp});

  /// Sends an SDP answer (subscriber role).
  void sendAnswer(String sdp) =>
      _send(<String, dynamic>{'type': 'answer', 'sdp': sdp});

  /// Sends a trickle ICE candidate.
  void sendIceCandidate(IceCandidatePayload candidate) => _send(
        <String, dynamic>{
          'type': 'ice_candidate',
          'candidate': candidate.toJson(),
        },
      );

  /// Permanently closes the socket and releases its stream controllers.
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _socket?.dispose();
    await _readyCtrl.close();
    await _offerCtrl.close();
    await _answerCtrl.close();
    await _iceCandidateCtrl.close();
    await _participantJoinedCtrl.close();
    await _participantLeftCtrl.close();
    await _sessionEndedCtrl.close();
    await _errorCtrl.close();
    await _authMissingCtrl.close();
  }

  Future<void> _open() async {
    if (_client.getAccessToken() == null || _client.getAccessToken()!.isEmpty) {
      // The SDK cannot invent an identity, but it must not fail silently
      // either: joining as a Guest when the application believed the user
      // was signed in is the single most confusing failure mode here.
      _authMissingCtrl.add(null);
      _client.config.log(
        SupersoLogLevel.warning,
        'Media: connecting WITHOUT an end-user token — this participant '
        'will be recorded as a Guest. Sign in first (auth.login/register '
        'store the token automatically), or call '
        'auth.tokens.setAccessToken(<jwt>) if you manage tokens yourself.',
      );
    }

    await _subscription?.cancel();
    final socket = RealtimeSocket(
      _client,
      path: '/media/signal',
      // Docs' documented sequence: 100ms → 200ms → 400ms → 800ms → 1600ms →
      // ... with no explicit cap — 30s mirrors the Realtime module's own
      // cap and the JS SDK's MAX_RECONNECT_DELAY_MS.
      reconnectPolicy: const ReconnectPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 30),
        multiplier: 2,
      ),
      heartbeatInterval: const Duration(seconds: 15),
      queryParameters: <String, String>{
        'session_id': _sessionId!,
        'role': _role!.wireValue,
      },
    );
    _socket = socket;
    _subscription = socket.rawMessages.listen(_handleFrame);
    await socket.connect();
  }

  void _handleFrame(Map<String, dynamic> frame) {
    switch (frame['type'] as String?) {
      case 'ready':
        final rawServers = frame['ice_servers'] as List<dynamic>? ??
            const <dynamic>[];
        final role = frame['role'] as String?;
        _readyCtrl.add(
          MediaSignalingReady(
            role: role == 'publisher'
                ? SignalingRole.publisher
                : role == 'subscriber'
                    ? SignalingRole.subscriber
                    : null,
            iceServers: rawServers
                .whereType<Map<String, dynamic>>()
                .map(IceServerConfig.fromJson)
                .toList(growable: false),
          ),
        );
        break;
      case 'offer':
        _offerCtrl.add(
          SessionDescriptionPayload(
            type: 'offer',
            sdp: frame['sdp'] as String? ?? '',
          ),
        );
        break;
      case 'answer':
        _answerCtrl.add(
          SessionDescriptionPayload(
            type: 'answer',
            sdp: frame['sdp'] as String? ?? '',
          ),
        );
        break;
      case 'ice_candidate':
        final candidate = frame['candidate'];
        if (candidate is Map<String, dynamic>) {
          _iceCandidateCtrl.add(IceCandidatePayload.fromJson(candidate));
        }
        break;
      case 'participant_joined':
        _participantJoinedCtrl.add(frame);
        break;
      case 'participant_left':
        _participantLeftCtrl.add(frame);
        break;
      case 'session_ended':
        _sessionEndedCtrl.add(frame);
        break;
      case 'error':
        _errorCtrl.add(
          MediaSignalingError(
            code: frame['code'] as String? ?? 'SIGNALING_ERROR',
            message: frame['error'] as String? ?? 'Media: signaling error.',
          ),
        );
        break;
      case 'pong':
        // Keep-alive acknowledgement only — nothing to dispatch.
        break;
    }
  }

  void _send(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null) {
      throw const SupersoError(
        message: 'Superso: cannot send a signaling message before '
            'connect() has been called.',
        code: 'SOCKET_NOT_CONNECTED',
      );
    }
    socket.send(frame);
  }
}
