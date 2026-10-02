/// Raw WebRTC signaling transport for the Media module
/// (`GET /v1/media/signal`, contract §6 and §14 "Signaling").
///
/// This class owns the signaling transport ONLY — it does not bundle a
/// WebRTC media-capture engine. The host Flutter application supplies its
/// own WebRTC plugin (e.g. `flutter_webrtc`) and wires its
/// `RTCPeerConnection`'s offer/answer/ICE-candidate calls through the
/// connection this class exposes.
///
/// Wire vocabulary:
///  - server → client: `ready`, `offer`, `answer`, `ice_candidate`, `pong`,
///    `error {code, error}`, `disconnect {code, reason}`;
///  - client → server: `offer`, `answer`, `ice_candidate`, `ping`,
///    `track_info {track_id, source}`.
///
/// Reconnect rules ([decideSignalingReconnect]): never after `MEDIA_KICKED`,
/// `MEDIA_BANNED`, `MEDIA_SESSION_ENDED` or `MEDIA_LEFT`; a publisher is not
/// reconnected after `MEDIA_PUBLISH_REVOKED`; `MEDIA_BREAKOUT_MOVED`
/// reconnects to the breakout room named by `reason`;
/// `MEDIA_BREAKOUT_CLOSED` reconnects to the main room; timeouts and network
/// drops reconnect with exponential backoff, resuming the same participant
/// with its participant token.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../client/superso_http_client.dart';
import '../config/superso_config.dart';
import '../errors/superso_error.dart';
import '../realtime/realtime_socket.dart';
import 'media_tokens.dart';
import 'media_types.dart';

/// `publisher` or `subscriber`.
enum SignalingRole {
  /// Sends media tracks.
  publisher('publisher'),

  /// Receives every active publisher's tracks.
  subscriber('subscriber');

  const SignalingRole(this.wireValue);

  /// The value sent as the `role` query parameter.
  final String wireValue;
}

/// Server-initiated close codes sent in the `disconnect` frame (and as the
/// WebSocket close reason, close code 4000).
abstract final class MediaDisconnectCodes {
  /// The participant was kicked.
  static const String kicked = 'MEDIA_KICKED';

  /// The participant was banned.
  static const String banned = 'MEDIA_BANNED';

  /// The session ended, was cancelled or purged.
  static const String sessionEnded = 'MEDIA_SESSION_ENDED';

  /// Moved to a breakout room; `reason` is the target room id.
  static const String breakoutMoved = 'MEDIA_BREAKOUT_MOVED';

  /// The breakout room closed; reconnect to the main room.
  static const String breakoutClosed = 'MEDIA_BREAKOUT_CLOSED';

  /// The participant lost the right to publish.
  static const String publishRevoked = 'MEDIA_PUBLISH_REVOKED';

  /// The participant left explicitly (`POST .../leave`).
  static const String left = 'MEDIA_LEFT';

  /// No frame within `connection_timeout_sec`.
  static const String connectionTimeout = 'MEDIA_CONNECTION_TIMEOUT';
}

/// What to do after the signaling socket closed.
enum SignalingReconnectAction {
  /// Do not reconnect.
  none,

  /// Reconnect to the same room with exponential backoff.
  reconnect,

  /// Reconnect immediately to the breakout room in
  /// [SignalingReconnectDecision.breakoutRoomId].
  reconnectToBreakout,

  /// Reconnect immediately to the main room (no `breakout_room_id`).
  reconnectToMain,
}

/// The outcome of [decideSignalingReconnect].
@immutable
class SignalingReconnectDecision {
  /// Creates a decision.
  const SignalingReconnectDecision(this.action, {this.breakoutRoomId});

  /// What to do.
  final SignalingReconnectAction action;

  /// The breakout room to reconnect to (for
  /// [SignalingReconnectAction.reconnectToBreakout]).
  final String? breakoutRoomId;

  /// Whether any reconnect should happen.
  bool get shouldReconnect => action != SignalingReconnectAction.none;

  @override
  String toString() => 'SignalingReconnectDecision($action'
      '${breakoutRoomId == null ? '' : ', $breakoutRoomId'})';
}

/// Decides whether (and where) to reconnect after the socket closed.
///
/// [disconnectCode]/[reason] come from the server's last `disconnect` frame;
/// both are `null` for a network drop.
SignalingReconnectDecision decideSignalingReconnect({
  required SignalingRole role,
  String? disconnectCode,
  String? reason,
}) {
  switch (disconnectCode) {
    case MediaDisconnectCodes.kicked:
    case MediaDisconnectCodes.banned:
    case MediaDisconnectCodes.sessionEnded:
    case MediaDisconnectCodes.left:
      return const SignalingReconnectDecision(SignalingReconnectAction.none);
    case MediaDisconnectCodes.publishRevoked:
      return role == SignalingRole.publisher
          ? const SignalingReconnectDecision(SignalingReconnectAction.none)
          : const SignalingReconnectDecision(
              SignalingReconnectAction.reconnect,
            );
    case MediaDisconnectCodes.breakoutMoved:
      if (reason == null || reason.isEmpty) {
        return const SignalingReconnectDecision(
          SignalingReconnectAction.reconnect,
        );
      }
      return SignalingReconnectDecision(
        SignalingReconnectAction.reconnectToBreakout,
        breakoutRoomId: reason,
      );
    case MediaDisconnectCodes.breakoutClosed:
      return const SignalingReconnectDecision(
        SignalingReconnectAction.reconnectToMain,
      );
    default:
      // MEDIA_CONNECTION_TIMEOUT, a network drop (no frame), or a code this
      // SDK does not know yet: back off and resume with the token.
      return const SignalingReconnectDecision(
        SignalingReconnectAction.reconnect,
      );
  }
}

/// The `ready` frame, sent immediately after connect.
@immutable
class MediaSignalingReady {
  /// Creates a ready event.
  const MediaSignalingReady({
    required this.iceServers,
    this.role,
    this.sessionId,
    this.participantId,
    this.participantToken,
    this.breakoutRoomId,
    this.mediaConstraints,
  });

  /// Decodes a `ready` frame.
  factory MediaSignalingReady.fromFrame(Map<String, dynamic> frame) {
    final role = frame['role'];
    final constraints = frame['media_constraints'];
    String? str(String key) {
      final value = frame[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return MediaSignalingReady(
      role: role == 'publisher'
          ? SignalingRole.publisher
          : role == 'subscriber'
              ? SignalingRole.subscriber
              : null,
      iceServers: IceServerConfig.listFromJson(frame['ice_servers']),
      sessionId: str('session_id'),
      participantId: str('participant_id'),
      participantToken: str('participant_token'),
      breakoutRoomId: str('breakout_room_id'),
      mediaConstraints: (constraints is Map<String, dynamic>)
          ? MediaConstraints.fromJson(constraints)
          : null,
    );
  }

  /// The role the server confirmed.
  final SignalingRole? role;

  /// ICE servers the peer connection must be configured with.
  final List<IceServerConfig> iceServers;

  /// The session.
  final String? sessionId;

  /// This connection's participant.
  final String? participantId;

  /// The participant token (stored automatically for reconnects).
  final String? participantToken;

  /// The breakout room this connection is in, if any.
  final String? breakoutRoomId;

  /// Client capture hints.
  final MediaConstraints? mediaConstraints;
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

  /// Decodes `{candidate, sdpMid, sdpMLineIndex}`.
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

  /// The candidate string.
  final String candidate;

  /// The media stream identification tag.
  final String? sdpMid;

  /// The m-line index.
  final int? sdpMLineIndex;
}

/// A session description (offer/answer).
@immutable
class SessionDescriptionPayload {
  /// Creates a session description payload.
  const SessionDescriptionPayload({required this.type, required this.sdp});

  /// `offer` or `answer`.
  final String type;

  /// The SDP string.
  final String sdp;
}

/// A protocol error sent by the signaling server (`error {code, error}`).
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

/// A server-initiated close (`disconnect {code, reason}`).
@immutable
class MediaSignalingDisconnect {
  /// Creates a disconnect notice.
  const MediaSignalingDisconnect({required this.code, this.reason});

  /// One of [MediaDisconnectCodes].
  final String code;

  /// Free-text reason (for `MEDIA_BREAKOUT_MOVED`: the target room id).
  final String? reason;

  @override
  String toString() => 'MediaSignalingDisconnect($code, $reason)';
}

/// Snapshot of a [MediaSignalingConnection].
@immutable
class MediaSignalingInfo {
  /// Creates a connection info snapshot.
  const MediaSignalingInfo({
    required this.state,
    required this.reconnectAttempts,
    this.sessionId,
    this.role,
    this.participantId,
    this.breakoutRoomId,
  });

  /// The current connection state.
  final RealtimeConnectionState state;

  /// The session this connection is scoped to.
  final String? sessionId;

  /// The role this connection was opened with.
  final SignalingRole? role;

  /// The participant confirmed by the last `ready` frame.
  final String? participantId;

  /// The breakout room the connection targets, if any.
  final String? breakoutRoomId;

  /// Reconnect attempts since the last `ready`.
  final int reconnectAttempts;
}

/// Owns one signaling socket for a session and role.
///
/// Exposed at `superso.media.websocket`, and returned by
/// `superso.media.publishers.join()` / `superso.media.subscribers.join()`.
class MediaSignalingConnection {
  /// Creates a signaling connection bound to [client]. Pass the shared
  /// [tokens] store so tokens issued by `join` are reused automatically.
  MediaSignalingConnection(
    this._client, {
    MediaParticipantTokens? tokens,
    this.reconnectPolicy = const ReconnectPolicy(
      initialDelay: Duration(milliseconds: 100),
      maxDelay: Duration(seconds: 30),
      multiplier: 2,
    ),
  }) : _tokens = tokens ?? MediaParticipantTokens();

  final SupersoHttpClient _client;
  final MediaParticipantTokens _tokens;

  /// Backoff used after network drops and timeouts.
  final ReconnectPolicy reconnectPolicy;

  RealtimeSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _frameSub;
  StreamSubscription<RealtimeConnectionState>? _stateSub;
  Timer? _reconnectTimer;

  String? _sessionId;
  SignalingRole? _role;
  String? _participantToken;
  String? _participantId;
  String? _breakoutRoomId;
  String? _displayName;
  String? _platform;
  String? _sdkVersion;
  String? _appVersion;
  String? _networkType;

  MediaSignalingDisconnect? _lastDisconnect;
  bool _wasConnected = false;
  bool _closedByUser = false;
  bool _disposed = false;
  int _attempt = 0;
  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;

  final StreamController<MediaSignalingReady> _readyCtrl =
      StreamController<MediaSignalingReady>.broadcast();
  final StreamController<SessionDescriptionPayload> _offerCtrl =
      StreamController<SessionDescriptionPayload>.broadcast();
  final StreamController<SessionDescriptionPayload> _answerCtrl =
      StreamController<SessionDescriptionPayload>.broadcast();
  final StreamController<IceCandidatePayload> _iceCandidateCtrl =
      StreamController<IceCandidatePayload>.broadcast();
  final StreamController<MediaSignalingDisconnect> _disconnectCtrl =
      StreamController<MediaSignalingDisconnect>.broadcast();
  final StreamController<Map<String, dynamic>?> _sessionEndedCtrl =
      StreamController<Map<String, dynamic>?>.broadcast();
  final StreamController<MediaSignalingError> _errorCtrl =
      StreamController<MediaSignalingError>.broadcast();
  final StreamController<void> _authMissingCtrl =
      StreamController<void>.broadcast();
  final StreamController<RealtimeConnectionState> _stateCtrl =
      StreamController<RealtimeConnectionState>.broadcast();

  /// The `ready` frame (on every connect and reconnect).
  Stream<MediaSignalingReady> get onReady => _readyCtrl.stream;

  /// An SDP offer from the server (subscriber role).
  Stream<SessionDescriptionPayload> get onOffer => _offerCtrl.stream;

  /// An SDP answer from the server (publisher role).
  Stream<SessionDescriptionPayload> get onAnswer => _answerCtrl.stream;

  /// A trickle ICE candidate from the server.
  Stream<IceCandidatePayload> get onIceCandidate => _iceCandidateCtrl.stream;

  /// A server-initiated close (`disconnect` frame).
  Stream<MediaSignalingDisconnect> get onDisconnect => _disconnectCtrl.stream;

  /// The session ended (a `disconnect` frame with `MEDIA_SESSION_ENDED`).
  Stream<Map<String, dynamic>?> get onSessionEnded => _sessionEndedCtrl.stream;

  /// A protocol error sent by the server.
  Stream<MediaSignalingError> get onError => _errorCtrl.stream;

  /// Fired on connect when neither an end-user access token nor a
  /// participant token is available — the backend will admit a new guest.
  Stream<void> get onAuthMissing => _authMissingCtrl.stream;

  /// The current connection state.
  RealtimeConnectionState get state => _state;

  /// Connection state transitions (stable across reconnects).
  Stream<RealtimeConnectionState> get connectionState => _stateCtrl.stream;

  /// Whether the socket is currently connected.
  bool get isConnected => _state == RealtimeConnectionState.connected;

  /// The participant token used on the next (re)connect.
  String? get participantToken => _participantToken;

  /// The breakout room targeted by the next (re)connect.
  String? get breakoutRoomId => _breakoutRoomId;

  /// The last server-initiated close, if any.
  MediaSignalingDisconnect? get lastDisconnect => _lastDisconnect;

  /// Snapshot of the connection.
  MediaSignalingInfo info() => MediaSignalingInfo(
        state: _state,
        sessionId: _sessionId,
        role: _role,
        participantId: _participantId,
        breakoutRoomId: _breakoutRoomId,
        reconnectAttempts: _attempt,
      );

  /// Opens the signaling socket for [sessionId] in [role].
  ///
  /// [participantToken] defaults to the token stored by `sessions.join()`
  /// for this session. [breakoutRoomId] defaults to `null` (main room); pass
  /// `MediaJoinResult.breakoutRoomId` when the participant is assigned to a
  /// breakout room (`MEDIA_IN_BREAKOUT` otherwise).
  Future<void> connect(
    String sessionId,
    SignalingRole role, {
    String? participantToken,
    String? breakoutRoomId,
    String? displayName,
    String? platform,
    String? sdkVersion,
    String? appVersion,
    String? networkType,
  }) async {
    _assertNotDisposed();
    _sessionId = sessionId;
    _role = role;
    _participantToken = participantToken ?? _tokens.forSession(sessionId);
    _breakoutRoomId = breakoutRoomId;
    _displayName = displayName;
    _platform = platform;
    _sdkVersion = sdkVersion;
    _appVersion = appVersion;
    _networkType = networkType;
    _closedByUser = false;
    _attempt = 0;
    _reconnectTimer?.cancel();
    await _open();
  }

  /// Closes the connection. No automatic reconnect follows.
  Future<void> disconnect() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownSocket();
    _setState(RealtimeConnectionState.disconnected);
  }

  /// Forces a fresh signaling socket (same session, role, token and room)
  /// so the application can follow up with an ICE-restart offer.
  Future<void> restartIce() async {
    if (_sessionId == null || _role == null) {
      throw const SupersoError(
        message:
            'Superso: cannot restart ICE before connect() has been called.',
        code: 'SOCKET_NOT_CONNECTED',
      );
    }
    _closedByUser = false;
    _reconnectTimer?.cancel();
    await _open();
  }

  /// Sends an SDP offer (publisher role).
  void sendOffer(String sdp) =>
      _send(<String, dynamic>{'type': 'offer', 'sdp': sdp});

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

  /// Labels a published track (publisher role) so the SFU applies the right
  /// server policy (camera vs screen permission).
  void sendTrackInfo(String trackId, MediaTrackSource source) => _send(
        <String, dynamic>{
          'type': 'track_info',
          'track_id': trackId,
          'source': source.wireValue,
        },
      );

  /// Permanently closes the socket and releases its stream controllers.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _closedByUser = true;
    _reconnectTimer?.cancel();
    await _teardownSocket();
    _setState(RealtimeConnectionState.closed);
    await _readyCtrl.close();
    await _offerCtrl.close();
    await _answerCtrl.close();
    await _iceCandidateCtrl.close();
    await _disconnectCtrl.close();
    await _sessionEndedCtrl.close();
    await _errorCtrl.close();
    await _authMissingCtrl.close();
    await _stateCtrl.close();
  }

  /// The query parameters of the next connect (without `api_key`/`token`,
  /// which the shared socket adds itself).
  @visibleForTesting
  Map<String, String> signalingQuery() {
    final params = <String, String>{
      'session_id': _sessionId ?? '',
      'role': (_role ?? SignalingRole.subscriber).wireValue,
    };
    void put(String key, String? value) {
      if (value != null && value.isNotEmpty) params[key] = value;
    }

    put('participant_token', _participantToken);
    put('breakout_room_id', _breakoutRoomId);
    put('display_name', _displayName);
    put('platform', _platform);
    put('sdk_version', _sdkVersion);
    put('app_version', _appVersion);
    put('network_type', _networkType);
    return params;
  }

  // ── internals ──────────────────────────────────────────────────────────

  void _assertNotDisposed() {
    if (_disposed) {
      throw const SupersoError(
        message: 'Superso: this signaling connection has been disposed.',
        code: 'SOCKET_DISPOSED',
      );
    }
  }

  Future<void> _teardownSocket() async {
    final frameSub = _frameSub;
    final stateSub = _stateSub;
    final socket = _socket;
    _frameSub = null;
    _stateSub = null;
    _socket = null;
    _wasConnected = false;
    await frameSub?.cancel();
    await stateSub?.cancel();
    await socket?.dispose();
  }

  Future<void> _open() async {
    final token = _client.getAccessToken();
    if ((token == null || token.isEmpty) &&
        (_participantToken == null || _participantToken!.isEmpty)) {
      _authMissingCtrl.add(null);
      _client.config.log(
        SupersoLogLevel.warning,
        'Media: connecting WITHOUT an end-user token or participant token — '
        'the backend will admit this connection as a new guest. Sign in, or '
        'call media.sessions.join() first.',
      );
    }

    await _teardownSocket();
    _lastDisconnect = null;
    final socket = RealtimeSocket(
      _client,
      path: '/media/signal',
      // Reconnects are driven by this class (see decideSignalingReconnect),
      // never by the shared socket, so every reconnect can carry a fresh
      // participant token / breakout room.
      reconnectPolicy: ReconnectPolicy.none,
      // Contract §6: SDKs ping every 15s (server idle timeout >= 15s).
      heartbeatInterval: const Duration(seconds: 15),
      queryParameters: signalingQuery(),
    );
    _socket = socket;
    _frameSub = socket.rawMessages.listen(_handleFrame);
    _stateSub = socket.connectionState.listen(_onSocketState);
    await socket.connect();
  }

  void _onSocketState(RealtimeConnectionState next) {
    switch (next) {
      case RealtimeConnectionState.connected:
        _wasConnected = true;
        _setState(next);
        return;
      case RealtimeConnectionState.connecting:
        _setState(next);
        return;
      case RealtimeConnectionState.disconnected:
        // A failed connect attempt never reached `connected`; its caller
        // (connect()/the reconnect timer) handles the failure.
        final dropped = _wasConnected;
        _wasConnected = false;
        _setState(RealtimeConnectionState.disconnected);
        if (!dropped || _closedByUser || _disposed) return;
        // Let the `disconnect` frame (delivered just before the close) land
        // first: Timer.run fires after every pending microtask.
        Timer.run(_handleDrop);
        return;
      case RealtimeConnectionState.reconnecting:
      case RealtimeConnectionState.closed:
        return;
    }
  }

  void _handleDrop() {
    if (_closedByUser || _disposed || _role == null) return;
    final decision = decideSignalingReconnect(
      role: _role!,
      disconnectCode: _lastDisconnect?.code,
      reason: _lastDisconnect?.reason,
    );
    _client.config.log(
      SupersoLogLevel.debug,
      'Media signaling closed ($_lastDisconnect): $decision',
    );
    switch (decision.action) {
      case SignalingReconnectAction.none:
        return;
      case SignalingReconnectAction.reconnectToBreakout:
        _breakoutRoomId = decision.breakoutRoomId;
        _scheduleReconnect(immediate: true);
        return;
      case SignalingReconnectAction.reconnectToMain:
        _breakoutRoomId = null;
        _scheduleReconnect(immediate: true);
        return;
      case SignalingReconnectAction.reconnect:
        _scheduleReconnect(immediate: false);
        return;
    }
  }

  void _scheduleReconnect({required bool immediate}) {
    if (_closedByUser || _disposed) return;
    var delay = Duration.zero;
    if (!immediate) {
      if (!reconnectPolicy.enabled) return;
      if (reconnectPolicy.maxAttempts > 0 &&
          _attempt >= reconnectPolicy.maxAttempts) {
        _client.config.log(
          SupersoLogLevel.warning,
          'Media signaling: giving up after ${reconnectPolicy.maxAttempts} '
          'reconnect attempts',
        );
        return;
      }
      _attempt++;
      delay = reconnectPolicy.delayFor(_attempt);
    }
    _setState(RealtimeConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      unawaited(
        _open().catchError((Object error) {
          _client.config.log(
            SupersoLogLevel.warning,
            'Media signaling: reconnect failed',
            error,
          );
          _scheduleReconnect(immediate: false);
        }),
      );
    });
  }

  void _handleFrame(Map<String, dynamic> frame) {
    switch (frame['type'] as String?) {
      case 'ready':
        final ready = MediaSignalingReady.fromFrame(frame);
        _attempt = 0;
        if (ready.participantToken != null) {
          _participantToken = ready.participantToken;
        }
        if (ready.participantId != null) _participantId = ready.participantId;
        _breakoutRoomId = ready.breakoutRoomId;
        final sessionId = ready.sessionId ?? _sessionId;
        if (sessionId != null &&
            ready.participantId != null &&
            ready.participantToken != null) {
          _tokens.store(
            sessionId: sessionId,
            participantId: ready.participantId!,
            token: ready.participantToken!,
          );
        }
        _readyCtrl.add(ready);
        break;
      case 'offer':
        _offerCtrl.add(
          SessionDescriptionPayload(type: 'offer', sdp: _sdpOf(frame)),
        );
        break;
      case 'answer':
        _answerCtrl.add(
          SessionDescriptionPayload(type: 'answer', sdp: _sdpOf(frame)),
        );
        break;
      case 'ice_candidate':
        final candidate = frame['candidate'];
        final data = frame['data'];
        if (candidate is Map<String, dynamic>) {
          _iceCandidateCtrl.add(IceCandidatePayload.fromJson(candidate));
        } else if (data is Map<String, dynamic>) {
          _iceCandidateCtrl.add(IceCandidatePayload.fromJson(data));
        }
        break;
      case 'disconnect':
        final notice = MediaSignalingDisconnect(
          code: frame['code'] as String? ?? '',
          reason: frame['reason'] as String?,
        );
        _lastDisconnect = notice;
        _disconnectCtrl.add(notice);
        if (notice.code == MediaDisconnectCodes.sessionEnded) {
          _sessionEndedCtrl.add(frame);
        }
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
        // Keep-alive acknowledgement only.
        break;
    }
  }

  static String _sdpOf(Map<String, dynamic> frame) {
    final sdp = frame['sdp'];
    if (sdp is String && sdp.isNotEmpty) return sdp;
    final data = frame['data'];
    if (data is Map<String, dynamic> && data['sdp'] is String) {
      return data['sdp'] as String;
    }
    return '';
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

  void _setState(RealtimeConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(next);
  }
}
