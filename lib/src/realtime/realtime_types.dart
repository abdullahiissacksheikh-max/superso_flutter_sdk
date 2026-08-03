/// Domain models and wire-protocol frames for the Realtime module, mirrored
/// from `docs/realtime.md`.
///
/// Dart port of `supersosdk/src/realtime/{types,protocol}.ts`.
library;

import 'package:meta/meta.dart';

/// A participant's availability on a presence channel.
enum PresenceStatus {
  /// Actively present.
  online('online'),

  /// Present but idle.
  away('away'),

  /// Present but not to be disturbed.
  busy('busy'),

  /// Connected but hidden from other participants.
  invisible('invisible');

  const PresenceStatus(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [online] for anything unrecognized.
  static PresenceStatus fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => PresenceStatus.online,
      );
}

/// The category of a channel, inferred from its name.
enum RealtimeChannelType {
  /// A `database:` channel bridging document and collection events.
  database,

  /// A `presence/` channel tracking who is present.
  broadcast,

  /// A `broadcast/` channel carrying application messages.
  presence,

  /// Any other channel name.
  custom,
}

/// Infers a channel's type from its name, per the prefix rules in
/// `docs/realtime.md` §8.
///
/// `database:` maps to [RealtimeChannelType.database], `presence/` to
/// [RealtimeChannelType.presence], `broadcast/` to
/// [RealtimeChannelType.broadcast], and anything else to
/// [RealtimeChannelType.custom].
RealtimeChannelType inferChannelType(String channel) {
  if (channel.startsWith('database:')) return RealtimeChannelType.database;
  if (channel.startsWith('presence/')) return RealtimeChannelType.presence;
  if (channel.startsWith('broadcast/')) return RealtimeChannelType.broadcast;
  return RealtimeChannelType.custom;
}

/// The server's realtime configuration, communicated on every connect so the
/// client can drive heartbeat and reconnect timing.
@immutable
class RealtimeSettings {
  /// Creates a settings snapshot.
  const RealtimeSettings({
    required this.heartbeatIntervalSec,
    required this.reconnectEnabled,
    required this.reconnectIntervalSec,
    required this.reconnectMaxAttempts,
    required this.maxMessageSizeKb,
    required this.offlineQueueEnabled,
  });

  /// Decodes settings from JSON.
  factory RealtimeSettings.fromJson(Map<String, dynamic> json) =>
      RealtimeSettings(
        heartbeatIntervalSec:
            (json['heartbeat_interval_sec'] as num?)?.toInt() ?? 30,
        reconnectEnabled: json['reconnect_enabled'] as bool? ?? true,
        reconnectIntervalSec:
            (json['reconnect_interval_sec'] as num?)?.toInt() ?? 1,
        reconnectMaxAttempts:
            (json['reconnect_max_attempts'] as num?)?.toInt() ?? 10,
        maxMessageSizeKb: (json['max_message_size_kb'] as num?)?.toInt() ?? 64,
        offlineQueueEnabled: json['offline_queue_enabled'] as bool? ?? false,
      );

  /// How often the client should ping, in seconds.
  final int heartbeatIntervalSec;

  /// Whether the server expects clients to reconnect automatically.
  final bool reconnectEnabled;

  /// Base reconnect delay, in seconds.
  final int reconnectIntervalSec;

  /// Maximum reconnect attempts.
  final int reconnectMaxAttempts;

  /// Largest accepted frame, in kilobytes.
  final int maxMessageSizeKb;

  /// Whether the server queues messages for briefly-disconnected clients.
  final bool offlineQueueEnabled;
}

/// The payload of the `connected` frame — who the server thinks you are.
@immutable
class RealtimeClientInfo {
  /// Creates client info.
  const RealtimeClientInfo({
    required this.clientId,
    required this.projectId,
    required this.authenticated,
    required this.settings,
    this.userId,
  });

  /// Decodes client info from JSON.
  factory RealtimeClientInfo.fromJson(Map<String, dynamic> json) =>
      RealtimeClientInfo(
        clientId: json['client_id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        authenticated: json['authenticated'] as bool? ?? false,
        settings: RealtimeSettings.fromJson(
          json['settings'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
        ),
        userId: json['user_id'] as String?,
      );

  /// This connection's server-assigned identifier.
  final String clientId;

  /// The project this connection belongs to.
  final String projectId;

  /// Whether an end-user token was accepted.
  ///
  /// When false the connection is a guest — a very common cause is
  /// connecting before `auth.login()` has stored an access token.
  final bool authenticated;

  /// The authenticated user, when [authenticated] is true.
  final String? userId;

  /// The server's realtime configuration.
  final RealtimeSettings settings;

  @override
  String toString() =>
      'RealtimeClientInfo(clientId: $clientId, authenticated: $authenticated, '
      'userId: $userId)';
}

/// A single presence entry.
@immutable
class RealtimePresence {
  /// Creates a presence entry.
  const RealtimePresence({
    required this.userId,
    required this.status,
    this.channel,
    this.metadata,
    this.updatedAt,
  });

  /// Decodes a presence entry from JSON.
  factory RealtimePresence.fromJson(Map<String, dynamic> json) =>
      RealtimePresence(
        userId: json['user_id'] as String? ?? '',
        status: PresenceStatus.fromWire(json['status'] as String?),
        channel: json['channel'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        updatedAt: json['updated_at'] as String?,
      );

  /// The present user.
  final String userId;

  /// The channel they are present on.
  final String? channel;

  /// Their availability.
  final PresenceStatus status;

  /// Arbitrary metadata they published alongside their status.
  final Map<String, dynamic>? metadata;

  /// ISO-8601 timestamp of the last update.
  final String? updatedAt;

  @override
  String toString() => 'RealtimePresence($userId, ${status.wireValue})';
}

/// The payload of `GET /v1/realtime/presence/:channel`.
@immutable
class RealtimePresenceListResult {
  /// Creates a presence list.
  const RealtimePresenceListResult({
    required this.channel,
    required this.presence,
    required this.total,
  });

  /// Decodes a presence list from JSON.
  factory RealtimePresenceListResult.fromJson(Map<String, dynamic> json) =>
      RealtimePresenceListResult(
        channel: json['channel'] as String? ?? '',
        presence: (json['presence'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RealtimePresence.fromJson)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  /// The channel queried.
  final String channel;

  /// Everyone currently present.
  final List<RealtimePresence> presence;

  /// Total present users.
  final int total;

  @override
  String toString() => 'RealtimePresenceListResult($channel, $total present)';
}

/// The payload of `POST /v1/realtime/publish` and `/broadcast`.
@immutable
class RealtimePublishResult {
  /// Creates a publish result.
  const RealtimePublishResult({required this.channel, required this.event});

  /// Decodes a publish result from JSON.
  factory RealtimePublishResult.fromJson(Map<String, dynamic> json) =>
      RealtimePublishResult(
        channel: json['channel'] as String? ?? '',
        event: json['event'] as String? ?? '',
      );

  /// The channel published to.
  final String channel;

  /// The event name published.
  final String event;
}

/// Every database bridge event name.
abstract final class DatabaseEventName {
  /// A document was created.
  static const String documentCreated = 'database.document.created';

  /// A document was replaced.
  static const String documentUpdated = 'database.document.updated';

  /// A document was merged into.
  static const String documentPatched = 'database.document.patched';

  /// A document was soft-deleted.
  static const String documentDeleted = 'database.document.deleted';

  /// A soft-deleted document was restored.
  static const String documentRestored = 'database.document.restored';

  /// A collection was created.
  static const String collectionCreated = 'database.collection.created';

  /// A collection was deleted.
  static const String collectionDeleted = 'database.collection.deleted';
}

/// The payload of a `database.document.*` event.
@immutable
class DatabaseEventPayload {
  /// Creates a document event payload.
  const DatabaseEventPayload({
    required this.docId,
    required this.collection,
    required this.data,
    required this.version,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a document event payload from JSON.
  factory DatabaseEventPayload.fromJson(Map<String, dynamic> json) =>
      DatabaseEventPayload(
        docId: json['doc_id'] as String? ?? '',
        collection: json['collection'] as String? ?? '',
        data:
            json['data'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        version: (json['version'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// The affected document's developer-facing ID.
  final String docId;

  /// The containing collection.
  final String collection;

  /// The document's data at the time of the event.
  final Map<String, dynamic> data;

  /// The document's version after the change.
  final int version;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  @override
  String toString() => 'DatabaseEventPayload($collection/$docId, v$version)';
}

/// The payload of a `database.collection.*` event.
///
/// A distinct shape from [DatabaseEventPayload] because no single document is
/// involved. [name], [parentPath], and [documentCount] appear only on
/// `database.collection.created` — by the time a deletion fires, the
/// collection is already gone and only [path] is known.
@immutable
class DatabaseCollectionEventPayload {
  /// Creates a collection event payload.
  const DatabaseCollectionEventPayload({
    required this.path,
    this.name,
    this.parentPath,
    this.documentCount,
  });

  /// Decodes a collection event payload from JSON.
  factory DatabaseCollectionEventPayload.fromJson(Map<String, dynamic> json) =>
      DatabaseCollectionEventPayload(
        path: json['path'] as String? ?? '',
        name: json['name'] as String?,
        parentPath: json['parent_path'] as String?,
        documentCount: (json['document_count'] as num?)?.toInt(),
      );

  /// The collection's path.
  final String path;

  /// Its display name, on creation only.
  final String? name;

  /// Its parent path, on creation only.
  final String? parentPath;

  /// Its document count at creation, on creation only.
  final int? documentCount;

  @override
  String toString() => 'DatabaseCollectionEventPayload($path)';
}

/// A decoded server-to-client frame.
///
/// The realtime protocol multiplexes several frame shapes over one socket;
/// this is the parsed union. Inspect [type] to know which fields are set.
@immutable
class RealtimeFrame {
  /// Creates a frame.
  const RealtimeFrame({
    required this.type,
    required this.raw,
    this.channel,
    this.event,
    this.data,
    this.id,
    this.code,
    this.message,
    this.timestamp,
  });

  /// Decodes a frame from a JSON map.
  factory RealtimeFrame.fromJson(Map<String, dynamic> json) => RealtimeFrame(
        type: json['type'] as String? ?? '',
        raw: json,
        channel: json['channel'] as String?,
        event: json['event'] as String?,
        data: json['data'],
        id: json['id'] as String?,
        code: json['code'] as String?,
        message: json['message'] as String?,
        timestamp: (json['timestamp'] as num?)?.toInt(),
      );

  /// The frame type: `connected`, `subscribed`, `unsubscribed`, `published`,
  /// `presence_set`, `presence`, `event`, `pong`, or `error`.
  final String type;

  /// The complete decoded frame, for fields this class does not surface.
  final Map<String, dynamic> raw;

  /// The channel this frame concerns, when applicable.
  final String? channel;

  /// The event name, on `event` and `presence` frames.
  final String? event;

  /// The payload, on `connected`, `event`, and `presence` frames.
  final Object? data;

  /// The client-generated request ID, echoed on acknowledgement frames.
  final String? id;

  /// The machine-readable error code, on `error` frames.
  final String? code;

  /// The human-readable error message, on `error` frames.
  final String? message;

  /// Server timestamp, in milliseconds since the epoch.
  final int? timestamp;

  /// The payload as a JSON map, or an empty map when it is not one.
  ///
  /// Written as a block rather than a conditional expression because
  /// `x is Map<K, V> ? a : b` is ambiguous to the Dart parser — it reads
  /// `Map<K, V>?` as a nullable type and then fails on the rest.
  Map<String, dynamic> get dataAsMap {
    final payload = data;
    return payload is Map<String, dynamic>
        ? payload
        : const <String, dynamic>{};
  }

  @override
  String toString() =>
      'RealtimeFrame(type: $type, channel: $channel, event: $event)';
}
