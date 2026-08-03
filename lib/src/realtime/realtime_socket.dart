/// The shared WebSocket transport used by the Realtime, Storage, and Media
/// modules.
///
/// The JavaScript SDK deliberately gives Storage its own small, self-contained
/// WebSocket client rather than importing the Realtime module, to keep module
/// boundaries clean. That reasoning does not carry over here: in Dart the
/// reconnect/heartbeat/backoff logic is substantial enough that duplicating it
/// three times would guarantee the copies drift. This one class is therefore
/// shared internally by all three modules, while each module still exposes its
/// own public surface — no module depends on another module's *public* API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../client/superso_http_client.dart';
import '../config/superso_config.dart';
import '../errors/superso_error.dart';

/// Connection lifecycle of a [RealtimeSocket].
enum RealtimeConnectionState {
  /// No connection, and none being attempted.
  disconnected,

  /// A connection attempt is in flight.
  connecting,

  /// Connected and ready to send and receive.
  connected,

  /// Waiting out a backoff delay before the next attempt.
  reconnecting,

  /// Permanently closed by [RealtimeSocket.dispose].
  closed,
}

/// Controls automatic reconnection after an unexpected disconnect.
@immutable
class ReconnectPolicy {
  /// Creates a reconnect policy.
  const ReconnectPolicy({
    this.enabled = true,
    this.maxAttempts = 10,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
  });

  /// A policy that never reconnects.
  static const ReconnectPolicy none = ReconnectPolicy(enabled: false);

  /// Whether to reconnect at all.
  final bool enabled;

  /// Maximum consecutive attempts before giving up. Zero means unlimited.
  final int maxAttempts;

  /// Delay before the first retry.
  final Duration initialDelay;

  /// Ceiling on any single delay.
  final Duration maxDelay;

  /// Growth factor applied after each failed attempt.
  final double multiplier;

  /// The delay before attempt number [attempt] (1-based).
  Duration delayFor(int attempt) {
    var micros = initialDelay.inMicroseconds.toDouble();
    for (var i = 1; i < attempt; i++) {
      micros *= multiplier;
      if (micros >= maxDelay.inMicroseconds) break;
    }
    return Duration(
      microseconds: micros.clamp(0, maxDelay.inMicroseconds.toDouble()).toInt(),
    );
  }
}

/// A managed WebSocket connection to the platform's realtime endpoint.
///
/// Handles connection, channel subscription, JSON framing, heartbeats,
/// exponential-backoff reconnection, and teardown. The connection opens lazily
/// on the first listener and closes when explicitly disposed.
///
/// Consumers receive decoded frames as `Map<String, dynamic>` and interpret
/// them themselves — this class is transport only and knows nothing about any
/// particular event vocabulary.
class RealtimeSocket {
  /// Creates a socket that subscribes to [channel] on connect.
  ///
  /// When [channel] is null the socket connects without sending any subscribe
  /// frame; callers then manage subscriptions themselves via [send].
  RealtimeSocket(
    this._client, {
    this.channel,
    this.path = '/realtime',
    this.reconnectPolicy = const ReconnectPolicy(),
    this.heartbeatInterval = const Duration(seconds: 30),
    Map<String, String>? queryParameters,
  }) : _extraQuery = queryParameters ?? const <String, String>{};

  final SupersoHttpClient _client;

  /// The channel subscribed to on every (re)connect, if any.
  final String? channel;

  /// The API path of the WebSocket endpoint, relative to the base URL.
  final String path;

  /// How reconnection is attempted after an unexpected close.
  final ReconnectPolicy reconnectPolicy;

  /// How often a ping frame is sent to keep the connection alive.
  ///
  /// [Duration.zero] disables heartbeats.
  final Duration heartbeatInterval;

  final Map<String, String> _extraQuery;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;
  bool _intentionalClose = false;

  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast(
    onListen: _noop,
  );
  final StreamController<RealtimeConnectionState> _states =
      StreamController<RealtimeConnectionState>.broadcast();

  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;

  static void _noop() {}

  /// Decoded frames received from the server.
  ///
  /// Listening triggers a lazy connect. The stream is a broadcast stream, so
  /// any number of subscribers may listen.
  Stream<Map<String, dynamic>> get messages {
    _connectLazily();
    return _messages.stream;
  }

  /// Decoded frames, without triggering a connection.
  ///
  /// Used for internal wiring — a module that attaches its own listener at
  /// construction time must not thereby open a socket, or simply building a
  /// `Superso` instance would dial the network. Consumer-facing APIs use
  /// [messages], which connects on demand.
  Stream<Map<String, dynamic>> get rawMessages => _messages.stream;

  /// Starts a connection attempt without surfacing failures to the caller.
  ///
  /// A lazy connect has no caller to throw to — the failure is logged and the
  /// reconnect policy takes over. Letting it escape would become an unhandled
  /// async error and, in a test, an unrelated failure.
  void _connectLazily() {
    if (_disposed ||
        _state == RealtimeConnectionState.connected ||
        _state == RealtimeConnectionState.connecting) {
      return;
    }
    unawaited(
      connect().catchError((Object error) {
        _client.config.log(
          SupersoLogLevel.warning,
          'Realtime: lazy connect failed',
          error,
        );
      }),
    );
  }

  /// Connection state transitions.
  Stream<RealtimeConnectionState> get connectionState => _states.stream;

  /// The current connection state.
  RealtimeConnectionState get state => _state;

  /// Whether the socket is currently connected.
  bool get isConnected => _state == RealtimeConnectionState.connected;

  /// Opens the connection if it is not already open or opening.
  ///
  /// Safe to call repeatedly; concurrent calls share one attempt.
  Future<void> connect() async {
    if (_disposed) {
      throw const SupersoError(
        message: 'Superso: this realtime socket has been disposed.',
        code: 'SOCKET_DISPOSED',
      );
    }
    if (_state == RealtimeConnectionState.connected ||
        _state == RealtimeConnectionState.connecting) {
      return;
    }

    _intentionalClose = false;
    _setState(RealtimeConnectionState.connecting);

    try {
      final uri = Uri.parse(_buildUrl());
      final socket = WebSocketChannel.connect(uri);
      _channel = socket;
      await socket.ready;

      _subscription = socket.stream.listen(
        _onFrame,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _attempt = 0;
      _setState(RealtimeConnectionState.connected);
      _client.config.log(SupersoLogLevel.debug, 'Realtime connected: $uri');

      final ch = channel;
      if (ch != null) {
        send(<String, dynamic>{'type': 'subscribe', 'channel': ch});
      }
      _startHeartbeat();
    } on Object catch (error) {
      _client.config
          .log(SupersoLogLevel.warning, 'Realtime connect failed', error);
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Sends [frame] as JSON.
  ///
  /// Throws a [SupersoError] if the socket is not currently connected — the
  /// caller should await [connect] first, or listen to [connectionState].
  void send(Map<String, dynamic> frame) {
    final socket = _channel;
    if (socket == null || _state != RealtimeConnectionState.connected) {
      throw const SupersoError(
        message: 'Superso: cannot send on a realtime socket that is not '
            'connected. Await connect() first.',
        code: 'SOCKET_NOT_CONNECTED',
      );
    }
    socket.sink.add(jsonEncode(frame));
  }

  /// Closes the connection without disposing the socket.
  ///
  /// Suppresses automatic reconnection; a later [connect] reopens it.
  Future<void> disconnect() async {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setState(RealtimeConnectionState.disconnected);
  }

  /// Permanently closes the socket and releases its stream controllers.
  ///
  /// Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    _setState(RealtimeConnectionState.closed);
    await _messages.close();
    await _states.close();
  }

  // ── internals ───────────────────────────────────────────────────────────

  String _buildUrl() {
    final httpUrl = _client.resolveUrl(path);
    final wsUrl = httpUrl.replaceFirst(RegExp('^http'), 'ws');

    final apiKey = _client.getApiKey();
    // Resolved on every connect, not captured at construction, so a token
    // acquired or refreshed later is always the one actually used.
    final accessToken = _client.getAccessToken();

    final params = <String, String>{
      // The platform's WebSocket endpoints accept the API key as a query
      // parameter because browsers cannot set custom headers on a WebSocket
      // handshake. Named `api_key` to match the Realtime and Media endpoints.
      if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
      // The end-user JWT, when present, is what lets the backend record a real
      // identity rather than a guest.
      if (accessToken != null && accessToken.isNotEmpty) 'token': accessToken,
      ..._extraQuery,
    };
    if (params.isEmpty) return wsUrl;

    final query = params.entries
        .map(
          (e) => '${Uri.encodeQueryComponent(e.key)}'
              '=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$wsUrl?$query';
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      _client.config.log(
        SupersoLogLevel.warning,
        'Realtime: discarded a non-JSON frame',
      );
      return;
    }
    if (decoded is Map<String, dynamic> && !_messages.isClosed) {
      _messages.add(decoded);
    }
  }

  void _onError(Object error) {
    _client.config.log(SupersoLogLevel.warning, 'Realtime socket error', error);
  }

  void _onDone() {
    _stopHeartbeat();
    _channel = null;
    if (_disposed || _intentionalClose) return;
    _setState(RealtimeConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _intentionalClose || !reconnectPolicy.enabled) return;
    if (reconnectPolicy.maxAttempts > 0 &&
        _attempt >= reconnectPolicy.maxAttempts) {
      _client.config.log(
        SupersoLogLevel.warning,
        'Realtime: giving up after ${reconnectPolicy.maxAttempts} '
        'reconnect attempts',
      );
      return;
    }

    _attempt++;
    final delay = reconnectPolicy.delayFor(_attempt);
    _setState(RealtimeConnectionState.reconnecting);
    _client.config.log(
      SupersoLogLevel.debug,
      'Realtime: reconnecting in ${delay.inMilliseconds}ms '
      '(attempt $_attempt)',
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      connect().catchError((Object _) {
        // _scheduleReconnect already ran inside connect()'s failure path.
      });
    });
  }

  void _startHeartbeat() {
    if (heartbeatInterval == Duration.zero) return;
    _stopHeartbeat();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (_state != RealtimeConnectionState.connected) return;
      try {
        send(<String, dynamic>{'type': 'ping'});
      } on SupersoError {
        // The connection dropped between the state check and the send; the
        // onDone handler will take it from here.
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _setState(RealtimeConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}
