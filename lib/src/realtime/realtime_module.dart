/// The Realtime module: connection, channels, presence, broadcast, and the
/// database event bridge.
///
/// Dart port of `supersosdk/src/realtime/{connection,channels,subscriptions,
/// presence,broadcast,client,messages,events,realtime}.ts`.
library;

import 'dart:async';

import '../client/superso_http_client.dart';
import '../interfaces/sdk_module.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'realtime_errors.dart';
import 'realtime_socket.dart';
import 'realtime_types.dart';

/// Correlates request frames with their acknowledgements.
///
/// Every `subscribe`, `unsubscribe`, `publish`, and `presence` frame carries a
/// client-generated `id` that the server echoes on its acknowledgement or on
/// an `error` frame. This is the single place that bookkeeping happens.
class _Correlator {
  final Map<String, Completer<RealtimeFrame>> _pending =
      <String, Completer<RealtimeFrame>>{};
  int _counter = 0;

  String nextId([String prefix = 'req']) {
    _counter++;
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$_counter';
  }

  Future<RealtimeFrame> register(String id, Duration timeout) {
    final completer = Completer<RealtimeFrame>();
    _pending[id] = completer;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw RealtimeTimeoutError(
          'Realtime request "$id" timed out after '
          '${timeout.inMilliseconds}ms waiting for a server response.',
        );
      },
    );
  }

  void handle(RealtimeFrame frame) {
    final id = frame.id;
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (frame.type == 'error') {
      completer.completeError(mapRealtimeErrorFrame(frame));
    } else {
      completer.complete(frame);
    }
  }

  /// Fails every outstanding request, so no caller hangs after a disconnect.
  void rejectAll(Object reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(reason);
    }
    _pending.clear();
  }
}

/// REST alternatives to the WebSocket connection, for clients that cannot hold
/// a persistent socket.
///
/// Exposed at `superso.realtime.rest`.
class RealtimeRestClient {
  /// Creates a REST client bound to [client].
  const RealtimeRestClient(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/realtime/publish`
  Future<ApiResponse<RealtimePublishResult>> publish({
    required String channel,
    required String event,
    Object? data,
  }) {
    return withRealtimeRestErrors(
      () => _client.post<RealtimePublishResult>(
        '/realtime/publish',
        body: <String, dynamic>{
          'channel': channel,
          'event': event,
          if (data != null) 'data': data,
        },
        decoder: _publishResult,
      ),
    );
  }

  /// `POST /v1/realtime/broadcast` — a documented identical alias of
  /// [publish].
  Future<ApiResponse<RealtimePublishResult>> broadcast({
    required String channel,
    required String event,
    Object? data,
  }) {
    return withRealtimeRestErrors(
      () => _client.post<RealtimePublishResult>(
        '/realtime/broadcast',
        body: <String, dynamic>{
          'channel': channel,
          'event': event,
          if (data != null) 'data': data,
        },
        decoder: _publishResult,
      ),
    );
  }

  /// `GET /v1/realtime/presence/:channel`
  Future<ApiResponse<RealtimePresenceListResult>> presence(String channel) {
    return withRealtimeRestErrors(
      () => _client.get<RealtimePresenceListResult>(
        '/realtime/presence/${encodeSegment(channel)}',
        decoder: (data) => RealtimePresenceListResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  static RealtimePublishResult _publishResult(Object? data) =>
      RealtimePublishResult.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );
}

/// A channel handle scoped to a database collection or a single document.
///
/// Obtain one from [RealtimeModule.databaseCollection] or
/// [RealtimeModule.databaseDocument] so channel names are never hand-built.
class DatabaseChannelHandle {
  /// Creates a handle for [channel].
  DatabaseChannelHandle(this._module, this.channel);

  final RealtimeModule _module;

  /// The underlying channel name, e.g. `database:users`.
  final String channel;

  /// Subscribes to this channel.
  Future<void> subscribe() => _module.subscribe(channel);

  /// Unsubscribes from this channel.
  Future<void> unsubscribe() => _module.unsubscribe(channel);

  Stream<DatabaseEventPayload> _documentEvents(String eventName) =>
      _module.events
          .where((f) => f.channel == channel && f.event == eventName)
          .map((f) => DatabaseEventPayload.fromJson(f.dataAsMap));

  Stream<DatabaseCollectionEventPayload> _collectionEvents(String eventName) =>
      _module.events
          .where((f) => f.channel == channel && f.event == eventName)
          .map((f) => DatabaseCollectionEventPayload.fromJson(f.dataAsMap));

  /// Documents created in this scope.
  Stream<DatabaseEventPayload> get onDocumentCreated =>
      _documentEvents(DatabaseEventName.documentCreated);

  /// Documents replaced in this scope.
  Stream<DatabaseEventPayload> get onDocumentUpdated =>
      _documentEvents(DatabaseEventName.documentUpdated);

  /// Documents merged into in this scope.
  Stream<DatabaseEventPayload> get onDocumentPatched =>
      _documentEvents(DatabaseEventName.documentPatched);

  /// Documents soft-deleted in this scope.
  Stream<DatabaseEventPayload> get onDocumentDeleted =>
      _documentEvents(DatabaseEventName.documentDeleted);

  /// Documents restored in this scope.
  Stream<DatabaseEventPayload> get onDocumentRestored =>
      _documentEvents(DatabaseEventName.documentRestored);

  /// Collection-creation events.
  ///
  /// Only ever fires on a collection-scoped handle — the backend publishes
  /// collection lifecycle events on the collection channel, since there is no
  /// single document to scope them to. On a document handle the event name
  /// simply never matches, so the stream stays silent.
  Stream<DatabaseCollectionEventPayload> get onCollectionCreated =>
      _collectionEvents(DatabaseEventName.collectionCreated);

  /// Collection-deletion events. See [onCollectionCreated] for scoping.
  Stream<DatabaseCollectionEventPayload> get onCollectionDeleted =>
      _collectionEvents(DatabaseEventName.collectionDeleted);
}

/// The composition root for `docs/realtime.md`.
///
/// Exposes a single flat API so applications never construct a WebSocket, a
/// `ws://` URL, or a raw protocol frame:
///
/// ```dart
/// await superso.realtime.connect();
/// await superso.realtime.subscribe('database:users');
///
/// superso.realtime.events.listen((frame) {
///   print('${frame.channel}: ${frame.event}');
/// });
///
/// await superso.realtime.publish(
///   channel: 'broadcast/chat',
///   event: 'message.sent',
///   data: {'text': 'hello'},
/// );
///
/// await superso.realtime.setPresence('presence/lobby', PresenceStatus.online);
/// ```
///
/// Where the JavaScript SDK uses `on(event, handler)` with an emitter, this
/// exposes typed `Stream`s. A `StreamSubscription` already provides
/// cancellation and integrates with `StreamBuilder`, so an emitter would be
/// both redundant and less idiomatic.
class RealtimeModule implements SdkModule, Disposable {
  /// Creates the realtime module bound to [client].
  RealtimeModule(this.client)
      : rest = RealtimeRestClient(client),
        _socket = RealtimeSocket(client) {
    _frameSubscription = _socket.messages.listen(_onFrame);
    _stateSubscription = _socket.connectionState.listen((state) {
      if (state == RealtimeConnectionState.disconnected) {
        _correlator.rejectAll(
          const ConnectionError(
            'The realtime connection dropped before the server replied.',
          ),
        );
      }
    });
  }

  @override
  final SupersoHttpClient client;

  /// REST-only publish, broadcast, and presence reads.
  final RealtimeRestClient rest;

  final RealtimeSocket _socket;
  final _Correlator _correlator = _Correlator();
  final Set<String> _subscriptions = <String>{};
  final StreamController<RealtimeFrame> _frames =
      StreamController<RealtimeFrame>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _frameSubscription;
  StreamSubscription<RealtimeConnectionState>? _stateSubscription;
  RealtimeClientInfo? _clientInfo;

  /// How long a correlated request waits for its acknowledgement.
  static const Duration requestTimeout = Duration(seconds: 10);

  // ── Connection lifecycle ────────────────────────────────────────────────

  /// Opens the connection.
  Future<void> connect() => _socket.connect();

  /// Closes the connection and clears local subscription bookkeeping.
  Future<void> disconnect() async {
    _subscriptions.clear();
    await _socket.disconnect();
  }

  /// Closes and reopens the connection.
  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }

  /// Whether the socket is currently connected.
  bool get isConnected => _socket.isConnected;

  /// The current connection state.
  RealtimeConnectionState get connectionState => _socket.state;

  /// Connection state transitions.
  Stream<RealtimeConnectionState> get onConnectionStateChanged =>
      _socket.connectionState;

  /// Who the server thinks this connection is, from the `connected` frame.
  ///
  /// `null` until the first successful connect. Check
  /// [RealtimeClientInfo.authenticated] to confirm an end-user token was
  /// accepted — a `false` here is the usual explanation for events that arrive
  /// as a guest.
  RealtimeClientInfo? get clientInfo => _clientInfo;

  /// Completes once the connection is open, or throws on timeout.
  Future<void> waitUntilConnected({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (isConnected) return;
    await connect();
    if (isConnected) return;
    await _socket.connectionState
        .firstWhere((s) => s == RealtimeConnectionState.connected)
        .timeout(
      timeout,
      onTimeout: () {
        throw RealtimeTimeoutError(
          'Timed out after ${timeout.inMilliseconds}ms waiting for the '
          'realtime connection to open.',
        );
      },
    );
  }

  /// Sends an application-level ping and completes when the `pong` arrives.
  Future<void> ping({Duration timeout = requestTimeout}) async {
    await _sendAndAwait(
      <String, dynamic>{'type': 'ping'},
      timeout: timeout,
      prefix: 'ping',
    );
  }

  // ── Channels ────────────────────────────────────────────────────────────

  /// Every decoded frame from the server, of every type.
  Stream<RealtimeFrame> get frames => _frames.stream;

  /// Only `event` frames — database bridge events and custom broadcasts.
  Stream<RealtimeFrame> get events =>
      _frames.stream.where((f) => f.type == 'event');

  /// Only `presence` push frames.
  Stream<RealtimeFrame> get presenceEvents =>
      _frames.stream.where((f) => f.type == 'presence');

  /// Server-sent `error` frames that were not tied to a specific request.
  ///
  /// Errors that answer a correlated request are thrown from that request's
  /// future instead, so they never appear here.
  Stream<SupersoError> get errors => _frames.stream
      .where((f) => f.type == 'error' && f.id == null)
      .map(mapRealtimeErrorFrame);

  /// Events on one specific channel.
  Stream<RealtimeFrame> channel(String channel) =>
      events.where((f) => f.channel == channel);

  /// Subscribes to [channel] and completes when the server acknowledges.
  Future<void> subscribe(String channel) async {
    await _sendAndAwait(
      <String, dynamic>{'type': 'subscribe', 'channel': channel},
      prefix: 'sub',
    );
    _subscriptions.add(channel);
  }

  /// Unsubscribes from [channel] and completes when the server acknowledges.
  Future<void> unsubscribe(String channel) async {
    await _sendAndAwait(
      <String, dynamic>{'type': 'unsubscribe', 'channel': channel},
      prefix: 'unsub',
    );
    _subscriptions.remove(channel);
  }

  /// Every channel currently subscribed to.
  Set<String> get subscriptions => Set<String>.unmodifiable(_subscriptions);

  /// Whether [channel] is currently subscribed.
  bool isSubscribed(String channel) => _subscriptions.contains(channel);

  /// The category of [channel], inferred from its name.
  RealtimeChannelType channelType(String channel) => inferChannelType(channel);

  // ── Broadcast ───────────────────────────────────────────────────────────

  /// Publishes [data] as [event] on [channel] over the WebSocket.
  Future<void> publish({
    required String channel,
    required String event,
    Object? data,
  }) async {
    await _sendAndAwait(
      <String, dynamic>{
        'type': 'publish',
        'channel': channel,
        'event': event,
        if (data != null) 'data': data,
      },
      prefix: 'pub',
    );
  }

  /// An alias of [publish]. The platform documents `/broadcast` as identical
  /// to `/publish`, and that aliasing is mirrored here rather than
  /// implemented as a second code path.
  Future<void> broadcast({
    required String channel,
    required String event,
    Object? data,
  }) =>
      publish(channel: channel, event: event, data: data);

  // ── Presence ────────────────────────────────────────────────────────────

  /// Sets this client's presence on [channel].
  Future<void> setPresence(
    String channel,
    PresenceStatus status, {
    Map<String, dynamic>? metadata,
  }) async {
    await _sendAndAwait(
      <String, dynamic>{
        'type': 'presence',
        'channel': channel,
        'status': status.wireValue,
        if (metadata != null) 'data': metadata,
      },
      prefix: 'pres',
    );
  }

  /// Marks this client online on [channel].
  Future<void> online(String channel, {Map<String, dynamic>? metadata}) =>
      setPresence(channel, PresenceStatus.online, metadata: metadata);

  /// Marks this client away on [channel].
  Future<void> away(String channel, {Map<String, dynamic>? metadata}) =>
      setPresence(channel, PresenceStatus.away, metadata: metadata);

  /// Marks this client busy on [channel].
  Future<void> busy(String channel, {Map<String, dynamic>? metadata}) =>
      setPresence(channel, PresenceStatus.busy, metadata: metadata);

  /// Marks this client invisible on [channel].
  Future<void> invisible(String channel, {Map<String, dynamic>? metadata}) =>
      setPresence(channel, PresenceStatus.invisible, metadata: metadata);

  /// Reads everyone currently present on [channel].
  ///
  /// There is no WebSocket equivalent — this is documented only as
  /// `GET /v1/realtime/presence/:channel`, so it goes over REST.
  Future<ApiResponse<RealtimePresenceListResult>> getPresence(String channel) =>
      rest.presence(channel);

  // ── Database bridge ─────────────────────────────────────────────────────

  /// A handle scoped to `database:<collection>` — every document event in the
  /// collection, plus the collection's own lifecycle events.
  DatabaseChannelHandle databaseCollection(String name) =>
      DatabaseChannelHandle(this, 'database:$name');

  /// A handle scoped to `database:<collection>/<docId>` — events for one
  /// document only.
  DatabaseChannelHandle databaseDocument(String collection, String docId) =>
      DatabaseChannelHandle(this, 'database:$collection/$docId');

  // ── internals ───────────────────────────────────────────────────────────

  Future<RealtimeFrame> _sendAndAwait(
    Map<String, dynamic> frame, {
    Duration timeout = requestTimeout,
    String prefix = 'req',
  }) async {
    await waitUntilConnected();
    final id = _correlator.nextId(prefix);
    final future = _correlator.register(id, timeout);
    _socket.send(<String, dynamic>{...frame, 'id': id});
    return future;
  }

  void _onFrame(Map<String, dynamic> raw) {
    final frame = RealtimeFrame.fromJson(raw);
    if (frame.type == 'connected') {
      _clientInfo = RealtimeClientInfo.fromJson(frame.dataAsMap);
    }
    _correlator.handle(frame);
    if (!_frames.isClosed) _frames.add(frame);
  }

  @override
  Future<void> dispose() async {
    await _frameSubscription?.cancel();
    await _stateSubscription?.cancel();
    _correlator.rejectAll(
      const ConnectionError('The realtime module was disposed.'),
    );
    await _socket.dispose();
    if (!_frames.isClosed) await _frames.close();
  }
}
