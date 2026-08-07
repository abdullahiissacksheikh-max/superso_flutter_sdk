/// The Notification module: send, broadcast, trigger, inbox, templates,
/// schedules, queue, devices, preferences, providers, logs, and analytics.
///
/// Dart port of `supersosdk/src/notification/*`.
library;

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'notification_types.dart';

/// Base class for every Notification-domain error.
class NotificationError extends SupersoError {
  /// Creates a notification error.
  const NotificationError(
    String message, {
    int? status,
    String? code,
    Object? details,
  }) : super(message: message, status: status, code: code, details: details);
}

/// A delivery provider is missing, disabled, or misconfigured.
class ProviderError extends NotificationError {
  /// Creates a provider error.
  const ProviderError(
    String message, [
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'PROVIDER_ERROR', details: details);
}

/// A template could not be found or rendered.
class TemplateError extends NotificationError {
  /// Creates a template error.
  const TemplateError(
    String message, [
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'TEMPLATE_ERROR', details: details);
}

/// An event operation failed — event not found, a mapped template slug
/// doesn't resolve, a duplicate/mismatched channel mapping, or (specific to
/// this domain) HTTP 422 `event_no_templates` surfaced by `trigger()` for an
/// event with zero channel mappings.
class EventError extends NotificationError {
  /// Creates an event error.
  const EventError(
    String message, [
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'EVENT_ERROR', details: details);
}

/// Wraps a Notification call, normalizing failures into this hierarchy.
///
/// Shared errors whose meaning does not depend on the module pass through.
Future<T> withNotificationErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on AuthenticationError {
    rethrow;
  } on PermissionError {
    rethrow;
  } on RateLimitError {
    rethrow;
  } on NetworkError {
    rethrow;
  } on CancelledError {
    rethrow;
  } on SupersoError catch (error) {
    throw NotificationError(
      error.message,
      status: error.status,
      code: error.code,
      details: error.details,
    );
  } on Object catch (error) {
    throw NotificationError('$error');
  }
}

/// The in-app inbox (`docs/notification.md` — In-App Inbox).
///
/// Exposed at `superso.notification.inbox`.
class InboxModule {
  /// Creates an inbox module bound to [client].
  const InboxModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/inbox` — a recipient's items.
  Future<ApiResponse<InboxList>> list({
    String? userId,
    int? limit,
    int? offset,
    bool? unread,
    bool? archived,
    bool? starred,
    String? category,
    String? search,
    InboxSort? sort,
    String? createdAfter,
    String? createdBefore,
  }) {
    return withNotificationErrors(
      () => _client.get<InboxList>(
        '/notifications/inbox',
        options: RequestOptions(
          query: <String, Object?>{
            'user_id': userId,
            'limit': limit,
            'offset': offset,
            'unread': unread,
            'archived': archived,
            'starred': starred,
            'category': category,
            'search': search,
            'sort': sort?.wireValue,
            'created_after': createdAfter,
            'created_before': createdBefore,
          },
        ),
        decoder: _inboxList,
      ),
    );
  }

  /// `GET /notifications/inbox/all` — every item in the project.
  Future<ApiResponse<InboxList>> listAll({
    int? limit,
    int? offset,
    bool? unread,
    bool? archived,
    bool? starred,
    String? category,
    String? search,
    InboxSort? sort,
  }) {
    return withNotificationErrors(
      () => _client.get<InboxList>(
        '/notifications/inbox/all',
        options: RequestOptions(
          query: <String, Object?>{
            'limit': limit,
            'offset': offset,
            'unread': unread,
            'archived': archived,
            'starred': starred,
            'category': category,
            'search': search,
            'sort': sort?.wireValue,
          },
        ),
        decoder: _inboxList,
      ),
    );
  }

  /// `GET /notifications/inbox/:id`
  Future<ApiResponse<InboxItem>> get(String id) => _item('GET', id, '');

  /// `PATCH /notifications/inbox/:id/read`
  Future<ApiResponse<InboxItem>> read(String id) => _item('PATCH', id, '/read');

  /// `PATCH /notifications/inbox/:id/unread`
  Future<ApiResponse<InboxItem>> unread(String id) =>
      _item('PATCH', id, '/unread');

  /// `PATCH /notifications/inbox/:id/archive`
  Future<ApiResponse<InboxItem>> archive(String id) =>
      _item('PATCH', id, '/archive');

  /// `PATCH /notifications/inbox/:id/restore`
  Future<ApiResponse<InboxItem>> restore(String id) =>
      _item('PATCH', id, '/restore');

  /// `PATCH /notifications/inbox/:id/star`
  Future<ApiResponse<InboxItem>> star(String id) => _item('PATCH', id, '/star');

  /// `PATCH /notifications/inbox/:id/unstar`
  Future<ApiResponse<InboxItem>> unstar(String id) =>
      _item('PATCH', id, '/unstar');

  /// `PATCH /notifications/inbox/:id/click` — records a tap.
  Future<ApiResponse<InboxItem>> click(String id) =>
      _item('PATCH', id, '/click');

  /// `PATCH /notifications/inbox/read-all` — marks every item read.
  Future<ApiResponse<void>> readAll(String userId) {
    return withNotificationErrors(
      () => _client.patch<void>(
        '/notifications/inbox/read-all',
        body: <String, dynamic>{'user_id': userId},
        decoder: (_) {},
      ),
    );
  }

  /// `PATCH /notifications/inbox/archive-all` — archives every item.
  Future<ApiResponse<void>> archiveAll(String userId) {
    return withNotificationErrors(
      () => _client.patch<void>(
        '/notifications/inbox/archive-all',
        body: <String, dynamic>{'user_id': userId},
        decoder: (_) {},
      ),
    );
  }

  /// `DELETE /notifications/inbox/:id` — soft-delete.
  Future<ApiResponse<void>> delete(String id) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/inbox/${encodeSegment(id)}',
        decoder: (_) {},
      ),
    );
  }

  /// `DELETE /notifications/inbox/:id/permanent` — irreversible delete.
  Future<ApiResponse<void>> deletePermanent(String id) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/inbox/${encodeSegment(id)}/permanent',
        decoder: (_) {},
      ),
    );
  }

  /// `DELETE /notifications/inbox/delete-all` — deletes every item.
  Future<ApiResponse<void>> deleteAll(String userId) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/inbox/delete-all',
        body: <String, dynamic>{'user_id': userId},
        decoder: (_) {},
      ),
    );
  }

  /// `GET /notifications/inbox/count` — unread and total counts.
  Future<ApiResponse<InboxCounts>> count({String? userId}) {
    return withNotificationErrors(
      () => _client.get<InboxCounts>(
        '/notifications/inbox/count',
        options: RequestOptions(query: <String, Object?>{'user_id': userId}),
        decoder: (data) => InboxCounts.fromJson(data as Map<String, dynamic>?),
      ),
    );
  }

  /// `GET /notifications/inbox/categories` — distinct categories in use.
  Future<ApiResponse<List<String>>> categories({String? userId}) {
    return withNotificationErrors(
      () => _client.get<List<String>>(
        '/notifications/inbox/categories',
        options: RequestOptions(query: <String, Object?>{'user_id': userId}),
        decoder: (data) {
          if (data is List<dynamic>) {
            return data.whereType<String>().toList(growable: false);
          }
          if (data is Map<String, dynamic>) {
            return (data['categories'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false);
          }
          return const <String>[];
        },
      ),
    );
  }

  /// `GET /notifications/inbox/history` — delivered items, including deleted.
  Future<ApiResponse<InboxList>> history({
    String? userId,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<InboxList>(
        '/notifications/inbox/history',
        options: RequestOptions(
          query: <String, Object?>{
            'user_id': userId,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: _inboxList,
      ),
    );
  }

  /// `GET /notifications/inbox/search` — full-text search.
  Future<ApiResponse<InboxList>> search(
    String query, {
    String? userId,
    int? limit,
    int? offset,
  }) {
    if (query.trim().isEmpty) {
      throw const ValidationError(
        'Superso: a non-empty search query is required.',
      );
    }
    return withNotificationErrors(
      () => _client.get<InboxList>(
        '/notifications/inbox/search',
        options: RequestOptions(
          query: <String, Object?>{
            'q': query,
            'user_id': userId,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: _inboxList,
      ),
    );
  }

  Future<ApiResponse<InboxItem>> _item(
    String method,
    String id,
    String suffix,
  ) {
    final path = '/notifications/inbox/${encodeSegment(id)}$suffix';
    return withNotificationErrors(
      () => method == 'GET'
          ? _client.get<InboxItem>(path, decoder: _inboxItem)
          : _client.patch<InboxItem>(path, decoder: _inboxItem),
    );
  }

  static InboxList _inboxList(Object? data) =>
      InboxList.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{});

  static InboxItem _inboxItem(Object? data) =>
      InboxItem.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{});
}

/// Template management.
///
/// Exposed at `superso.notification.templates`.
class TemplatesModule {
  /// Creates a templates module bound to [client].
  const TemplatesModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/templates`
  Future<ApiResponse<NotificationPage<NotificationTemplate>>> list({
    NotificationChannel? channel,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<NotificationPage<NotificationTemplate>>(
        '/notifications/templates',
        options: RequestOptions(
          query: <String, Object?>{
            'channel': channel?.wireValue,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => NotificationPage<NotificationTemplate>.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
          NotificationTemplate.fromJson,
        ),
      ),
    );
  }

  /// `GET /notifications/templates/:id`
  Future<ApiResponse<NotificationTemplate>> get(String id) {
    return withNotificationErrors(
      () => _client.get<NotificationTemplate>(
        '/notifications/templates/${encodeSegment(id)}',
        decoder: _template,
      ),
    );
  }

  /// `POST /notifications/templates`
  Future<ApiResponse<NotificationTemplate>> create({
    required String name,
    required String slug,
    required NotificationChannel channel,
    required String body,
    String? subject,
    List<TemplateVariable>? variables,
    bool? isActive,
  }) {
    return withNotificationErrors(
      () => _client.post<NotificationTemplate>(
        '/notifications/templates',
        body: <String, dynamic>{
          'name': name,
          'slug': slug,
          'channel': channel.wireValue,
          'body': body,
          if (subject != null) 'subject': subject,
          if (variables != null)
            'variables':
                variables.map((v) => v.toJson()).toList(growable: false),
          if (isActive != null) 'is_active': isActive,
        },
        decoder: _template,
      ),
    );
  }

  /// `PUT /notifications/templates/:id` — every field optional.
  Future<ApiResponse<NotificationTemplate>> update(
    String id, {
    String? name,
    String? slug,
    NotificationChannel? channel,
    String? subject,
    String? body,
    List<TemplateVariable>? variables,
    bool? isActive,
  }) {
    return withNotificationErrors(
      () => _client.put<NotificationTemplate>(
        '/notifications/templates/${encodeSegment(id)}',
        body: <String, dynamic>{
          if (name != null) 'name': name,
          if (slug != null) 'slug': slug,
          if (channel != null) 'channel': channel.wireValue,
          if (subject != null) 'subject': subject,
          if (body != null) 'body': body,
          if (variables != null)
            'variables':
                variables.map((v) => v.toJson()).toList(growable: false),
          if (isActive != null) 'is_active': isActive,
        },
        decoder: _template,
      ),
    );
  }

  /// `DELETE /notifications/templates/:id`
  Future<ApiResponse<void>> delete(String id) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/templates/${encodeSegment(id)}',
        decoder: (_) {},
      ),
    );
  }

  static NotificationTemplate _template(Object? data) =>
      NotificationTemplate.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{});
}

/// Event management — docs/notification.md "Events".
///
/// Two supported creation workflows, both via [create]:
///   - Workflow A: `create(eventKey: ..., name: ...)` — no `templates`. The
///     event is created successfully with zero mappings; attach channels
///     later with [mapTemplates].
///   - Workflow B: `create(eventKey: ..., name: ..., templates: [...])` —
///     mapped at creation time.
/// `templates` is never required by this module or the backend — only
/// [NotificationModule.trigger] requires at least one mapping to exist, and
/// throws an [EventError] (HTTP 422, `event_no_templates`) if none do.
///
/// Not exposed as `superso.notification.events` — mirroring how [trigger],
/// [NotificationModule.send], and [NotificationModule.broadcast] are flat
/// top-level methods rather than submodule properties, every method here is
/// re-exposed as a flat, Event-suffixed method on [NotificationModule]
/// (`createEvent()`, `updateEvent()`, etc.) per docs/notification.md's
/// documented SDK surface — matching the JS SDK's `NotificationEventsModule`
/// exactly.
class EventsModule {
  /// Creates an events module bound to [client].
  const EventsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/events`
  Future<ApiResponse<NotificationEventPage>> list({
    bool? isActive,
    String? category,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<NotificationEventPage>(
        '/notifications/events',
        options: RequestOptions(
          query: <String, Object?>{
            'is_active': isActive,
            'category': category,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => NotificationEventPage.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
          NotificationEvent.fromJson,
        ),
      ),
    );
  }

  /// `GET /notifications/events/:id`
  Future<ApiResponse<NotificationEvent>> get(String id) {
    return withNotificationErrors(
      () => _client.get<NotificationEvent>(
        '/notifications/events/${encodeSegment(id)}',
        decoder: _event,
      ),
    );
  }

  /// `POST /notifications/events`
  ///
  /// [templates] is optional (Workflow A/B — see class doc comment above);
  /// only [eventKey] and [name] are required.
  Future<ApiResponse<NotificationEvent>> create({
    required String eventKey,
    required String name,
    String? description,
    String? category,
    bool? isActive,
    List<EventTemplateMapping>? templates,
  }) {
    return withNotificationErrors(
      () => _client.post<NotificationEvent>(
        '/notifications/events',
        body: <String, dynamic>{
          'event_key': eventKey,
          'name': name,
          if (description != null) 'description': description,
          if (category != null) 'category': category,
          if (isActive != null) 'is_active': isActive,
          if (templates != null)
            'templates': templates.map((t) => t.toJson()).toList(growable: false),
        },
        decoder: _event,
      ),
    );
  }

  /// `PATCH /notifications/events/:id` — every field optional. The backend
  /// also accepts `PUT` on the same path (identical handler); this client
  /// uses `PATCH` since every field here is partial. Supplying an empty
  /// [templates] list is valid — it clears all mappings without deactivating
  /// the event (see Workflow A).
  Future<ApiResponse<NotificationEvent>> update(
    String id, {
    String? name,
    String? description,
    String? category,
    bool? isActive,
    List<EventTemplateMapping>? templates,
  }) {
    return withNotificationErrors(
      () => _client.patch<NotificationEvent>(
        '/notifications/events/${encodeSegment(id)}',
        body: <String, dynamic>{
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (category != null) 'category': category,
          if (isActive != null) 'is_active': isActive,
          if (templates != null)
            'templates': templates.map((t) => t.toJson()).toList(growable: false),
        },
        decoder: _event,
      ),
    );
  }

  /// `DELETE /notifications/events/:id`
  Future<ApiResponse<void>> delete(String id) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/events/${encodeSegment(id)}',
        decoder: (_) {},
      ),
    );
  }

  /// `PATCH /notifications/events/:id/templates` — fully **replaces** the
  /// mapping set (set semantics — the backend also accepts `PUT` on the same
  /// path with identical behavior). Pass an empty list to clear all mappings.
  Future<ApiResponse<List<EventTemplateMapping>>> mapTemplates(
    String id,
    List<EventTemplateMapping> templates,
  ) {
    return withNotificationErrors(
      () => _client.patch<List<EventTemplateMapping>>(
        '/notifications/events/${encodeSegment(id)}/templates',
        body: <String, dynamic>{
          'templates': templates.map((t) => t.toJson()).toList(growable: false),
        },
        decoder: (data) {
          final map = data as Map<String, dynamic>? ?? const <String, dynamic>{};
          final items = map['items'] as List<dynamic>? ?? const <dynamic>[];
          return items
              .whereType<Map<String, dynamic>>()
              .map(EventTemplateMapping.fromJson)
              .toList(growable: false);
        },
      ),
    );
  }

  /// `PATCH /notifications/events/:id/status` — activates/deactivates
  /// without touching name, description, category, or template mappings.
  /// Prefer this over `update(id, isActive: ...)` when that's the only
  /// change you're making.
  Future<ApiResponse<NotificationEvent>> updateStatus(String id, bool active) {
    return withNotificationErrors(
      () => _client.patch<NotificationEvent>(
        '/notifications/events/${encodeSegment(id)}/status',
        body: <String, dynamic>{'active': active},
        decoder: _event,
      ),
    );
  }

  /// `GET /notifications/events/:id/history` — new in v0.3.1. Returns the
  /// event plus every delivery attempt recorded against it (one entry per
  /// channel per trigger call), backed by the same records `trigger()`
  /// itself writes — never a separate, potentially-stale history table.
  Future<ApiResponse<EventHistoryResult>> getHistory(
    String id, {
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<EventHistoryResult>(
        '/notifications/events/${encodeSegment(id)}/history',
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => EventHistoryResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  static NotificationEvent _event(Object? data) =>
      NotificationEvent.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{});
}

/// Schedule management.
///
/// Exposed at `superso.notification.schedules`.
class SchedulesModule {
  /// Creates a schedules module bound to [client].
  const SchedulesModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/schedules`
  Future<ApiResponse<NotificationPage<NotificationSchedule>>> list({
    ScheduleStatus? status,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<NotificationPage<NotificationSchedule>>(
        '/notifications/schedules',
        options: RequestOptions(
          query: <String, Object?>{
            'status': status?.wireValue,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => NotificationPage<NotificationSchedule>.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
          NotificationSchedule.fromJson,
        ),
      ),
    );
  }

  /// `GET /notifications/schedules/:id`
  Future<ApiResponse<NotificationSchedule>> get(String id) {
    return withNotificationErrors(
      () => _client.get<NotificationSchedule>(
        '/notifications/schedules/${encodeSegment(id)}',
        decoder: _schedule,
      ),
    );
  }

  /// `POST /notifications/schedules`
  Future<ApiResponse<NotificationSchedule>> create({
    required String name,
    required NotificationChannel channel,
    required ScheduleRecipientType recipientType,
    required ScheduleType scheduleType,
    String? templateId,
    String? recipientRef,
    String? cronExpression,
    String? runAt,
    String? timezone,
    int? maxRuns,
    Map<String, dynamic>? variables,
    Map<String, dynamic>? context,
  }) {
    return withNotificationErrors(
      () => _client.post<NotificationSchedule>(
        '/notifications/schedules',
        body: <String, dynamic>{
          'name': name,
          'channel': channel.wireValue,
          'recipient_type': recipientType.wireValue,
          'schedule_type': scheduleType.wireValue,
          if (templateId != null) 'template_id': templateId,
          if (recipientRef != null) 'recipient_ref': recipientRef,
          if (cronExpression != null) 'cron_expression': cronExpression,
          if (runAt != null) 'run_at': runAt,
          if (timezone != null) 'timezone': timezone,
          if (maxRuns != null) 'max_runs': maxRuns,
          if (variables != null) 'variables': variables,
          if (context != null) 'context': context,
        },
        decoder: _schedule,
      ),
    );
  }

  /// `PATCH /notifications/schedules/:id` — updatable fields only.
  ///
  /// [status] accepts only `active`, `paused`, or `cancelled`; the other
  /// [ScheduleStatus] values are server-assigned and rejected here before a
  /// round trip.
  Future<ApiResponse<NotificationSchedule>> update(
    String id, {
    String? name,
    String? cronExpression,
    ScheduleStatus? status,
    int? maxRuns,
    Map<String, dynamic>? variables,
  }) {
    if (status == ScheduleStatus.completed) {
      throw const ValidationError(
        'Superso: `completed` is set by the server when a schedule reaches '
        'its run limit; it cannot be assigned. Use active, paused, or '
        'cancelled.',
      );
    }
    return withNotificationErrors(
      () => _client.patch<NotificationSchedule>(
        '/notifications/schedules/${encodeSegment(id)}',
        body: <String, dynamic>{
          if (name != null) 'name': name,
          if (cronExpression != null) 'cron_expression': cronExpression,
          if (status != null) 'status': status.wireValue,
          if (maxRuns != null) 'max_runs': maxRuns,
          if (variables != null) 'variables': variables,
        },
        decoder: _schedule,
      ),
    );
  }

  /// Pauses a schedule — shorthand for `update(id, status: paused)`.
  Future<ApiResponse<NotificationSchedule>> pause(String id) =>
      update(id, status: ScheduleStatus.paused);

  /// Resumes a schedule — shorthand for `update(id, status: active)`.
  Future<ApiResponse<NotificationSchedule>> resume(String id) =>
      update(id, status: ScheduleStatus.active);

  /// `DELETE /notifications/schedules/:id`
  Future<ApiResponse<void>> delete(String id) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/schedules/${encodeSegment(id)}',
        decoder: (_) {},
      ),
    );
  }

  static NotificationSchedule _schedule(Object? data) =>
      NotificationSchedule.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{});
}

/// Delivery queue inspection.
///
/// Exposed at `superso.notification.queue`.
class QueueModule {
  /// Creates a queue module bound to [client].
  const QueueModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/queue` — pending and in-flight items.
  Future<ApiResponse<NotificationPage<QueueItem>>> list({
    QueueStatus? status,
    NotificationChannel? channel,
    NotificationSource? source,
    NotificationProviderName? provider,
    String? templateId,
    String? search,
    String? dateFrom,
    String? dateTo,
    QueueSortBy? sortBy,
    SortDirection? sortDir,
    int? limit,
    int? offset,
  }) =>
      _list('/notifications/queue',
          status: status,
          channel: channel,
          source: source,
          provider: provider,
          templateId: templateId,
          search: search,
          dateFrom: dateFrom,
          dateTo: dateTo,
          sortBy: sortBy,
          sortDir: sortDir,
          limit: limit,
          offset: offset);

  /// `GET /notifications/queue/history` — completed and failed items.
  Future<ApiResponse<NotificationPage<QueueItem>>> history({
    QueueStatus? status,
    NotificationChannel? channel,
    NotificationSource? source,
    NotificationProviderName? provider,
    String? templateId,
    String? search,
    String? dateFrom,
    String? dateTo,
    QueueSortBy? sortBy,
    SortDirection? sortDir,
    int? limit,
    int? offset,
  }) =>
      _list('/notifications/queue/history',
          status: status,
          channel: channel,
          source: source,
          provider: provider,
          templateId: templateId,
          search: search,
          dateFrom: dateFrom,
          dateTo: dateTo,
          sortBy: sortBy,
          sortDir: sortDir,
          limit: limit,
          offset: offset);

  /// `GET /notifications/queue/:id`
  Future<ApiResponse<QueueItem>> get(String id) {
    return withNotificationErrors(
      () => _client.get<QueueItem>(
        '/notifications/queue/${encodeSegment(id)}',
        decoder: (data) =>
            QueueItem.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
    );
  }

  /// `GET /notifications/queue/statistics` — aggregate counts by status.
  Future<ApiResponse<Map<String, dynamic>>> statistics() {
    return withNotificationErrors(
      () => _client.get<Map<String, dynamic>>(
        '/notifications/queue/statistics',
        decoder: _map,
      ),
    );
  }

  /// `GET /notifications/queue/worker` — worker health and throughput.
  Future<ApiResponse<Map<String, dynamic>>> worker() {
    return withNotificationErrors(
      () => _client.get<Map<String, dynamic>>(
        '/notifications/queue/worker',
        decoder: _map,
      ),
    );
  }

  /// `DELETE /notifications/queue/:id` — cancels a pending item.
  Future<ApiResponse<void>> cancel(String id) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/queue/${encodeSegment(id)}',
        decoder: (_) {},
      ),
    );
  }

  Future<ApiResponse<NotificationPage<QueueItem>>> _list(
    String path, {
    QueueStatus? status,
    NotificationChannel? channel,
    NotificationSource? source,
    NotificationProviderName? provider,
    String? templateId,
    String? search,
    String? dateFrom,
    String? dateTo,
    QueueSortBy? sortBy,
    SortDirection? sortDir,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<NotificationPage<QueueItem>>(
        path,
        options: RequestOptions(
          query: <String, Object?>{
            'status': status?.wireValue,
            'channel': channel?.wireValue,
            'source': source?.wireValue,
            'provider': provider?.wireValue,
            'template_id': templateId,
            'search': search,
            'date_from': dateFrom,
            'date_to': dateTo,
            'sort_by': sortBy?.wireValue,
            'sort_dir': sortDir?.wireValue,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => NotificationPage<QueueItem>.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
          QueueItem.fromJson,
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(Object? data) =>
      data as Map<String, dynamic>? ?? const <String, dynamic>{};
}

/// Push device registration.
///
/// Exposed at `superso.notification.devices`.
class DevicesModule {
  /// Creates a devices module bound to [client].
  const DevicesModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /notifications/devices` — registers a push token.
  ///
  /// Call this after obtaining a token from `firebase_messaging` or an APNs
  /// plugin, and again whenever the token rotates.
  Future<ApiResponse<NotificationDevice>> register({
    required String userId,
    required String deviceToken,
    required DevicePlatform platform,
    DeviceProviderName? provider,
    String? appVersion,
    String? deviceModel,
  }) {
    if (deviceToken.trim().isEmpty) {
      throw const ValidationError(
        'Superso: a non-empty device token is required to register a device.',
      );
    }
    return withNotificationErrors(
      () => _client.post<NotificationDevice>(
        '/notifications/devices',
        body: <String, dynamic>{
          'user_id': userId,
          'device_token': deviceToken,
          'platform': platform.wireValue,
          if (provider != null) 'provider': provider.wireValue,
          if (appVersion != null) 'app_version': appVersion,
          if (deviceModel != null) 'device_model': deviceModel,
        },
        decoder: _device,
      ),
    );
  }

  /// `GET /notifications/devices`
  Future<ApiResponse<NotificationPage<NotificationDevice>>> list({
    String? userId,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<NotificationPage<NotificationDevice>>(
        '/notifications/devices',
        options: RequestOptions(
          query: <String, Object?>{
            'user_id': userId,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => NotificationPage<NotificationDevice>.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
          NotificationDevice.fromJson,
        ),
      ),
    );
  }

  /// `PATCH /notifications/devices/:deviceId`
  Future<ApiResponse<NotificationDevice>> update(
    String deviceId, {
    String? deviceToken,
    String? appVersion,
    String? deviceModel,
  }) {
    return withNotificationErrors(
      () => _client.patch<NotificationDevice>(
        '/notifications/devices/${encodeSegment(deviceId)}',
        body: <String, dynamic>{
          if (deviceToken != null) 'device_token': deviceToken,
          if (appVersion != null) 'app_version': appVersion,
          if (deviceModel != null) 'device_model': deviceModel,
        },
        decoder: _device,
      ),
    );
  }

  /// `DELETE /notifications/devices/:deviceId` — stops pushes to this device.
  Future<ApiResponse<void>> unregister(String deviceId) {
    return withNotificationErrors(
      () => _client.delete<void>(
        '/notifications/devices/${encodeSegment(deviceId)}',
        decoder: (_) {},
      ),
    );
  }

  static NotificationDevice _device(Object? data) =>
      NotificationDevice.fromJson(data as Map<String, dynamic>? ?? const <String, dynamic>{});
}

/// Per-user notification preferences.
///
/// Exposed at `superso.notification.preferences`.
class PreferencesModule {
  /// Creates a preferences module bound to [client].
  const PreferencesModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/preferences/all` — every user's preferences.
  Future<ApiResponse<NotificationPage<NotificationPreference>>> listAll({
    String? search,
    NotificationChannel? channel,
    bool? enabled,
    int? limit,
    int? offset,
  }) =>
      _list('/notifications/preferences/all',
          search: search,
          channel: channel,
          enabled: enabled,
          limit: limit,
          offset: offset);

  /// `GET /notifications/preferences` — project-wide preferences.
  Future<ApiResponse<NotificationPage<NotificationPreference>>> list({
    String? search,
    NotificationChannel? channel,
    bool? enabled,
    int? limit,
    int? offset,
  }) =>
      _list('/notifications/preferences',
          search: search,
          channel: channel,
          enabled: enabled,
          limit: limit,
          offset: offset);

  /// `GET /notifications/preferences?user_id=` — one user's preferences.
  Future<ApiResponse<NotificationPreference>> get(String userId) {
    return withNotificationErrors(
      () => _client.get<NotificationPreference>(
        '/notifications/preferences',
        options: RequestOptions(query: <String, Object?>{'user_id': userId}),
        decoder: _preference,
      ),
    );
  }

  /// `PATCH /notifications/preferences` — updates one user's preferences.
  Future<ApiResponse<NotificationPreference>> update({
    required String userId,
    bool? receiveNotifications,
    bool? inappEnabled,
    bool? pushEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    String? timezone,
    DeliveryFrequency? deliveryFrequency,
    SoundSetting? soundSettings,
    bool? badgeEnabled,
  }) {
    return withNotificationErrors(
      () => _client.patch<NotificationPreference>(
        '/notifications/preferences',
        body: <String, dynamic>{
          'user_id': userId,
          if (receiveNotifications != null)
            'receive_notifications': receiveNotifications,
          if (inappEnabled != null) 'inapp_enabled': inappEnabled,
          if (pushEnabled != null) 'push_enabled': pushEnabled,
          if (emailEnabled != null) 'email_enabled': emailEnabled,
          if (smsEnabled != null) 'sms_enabled': smsEnabled,
          if (quietHoursEnabled != null)
            'quiet_hours_enabled': quietHoursEnabled,
          if (quietHoursStart != null) 'quiet_hours_start': quietHoursStart,
          if (quietHoursEnd != null) 'quiet_hours_end': quietHoursEnd,
          if (timezone != null) 'timezone': timezone,
          if (deliveryFrequency != null)
            'delivery_frequency': deliveryFrequency.wireValue,
          if (soundSettings != null) 'sound_settings': soundSettings.wireValue,
          if (badgeEnabled != null) 'badge_enabled': badgeEnabled,
        },
        decoder: _preference,
      ),
    );
  }

  /// `POST /notifications/preferences/reset` — restores project defaults.
  Future<ApiResponse<NotificationPreference>> reset(String userId) {
    return withNotificationErrors(
      () => _client.post<NotificationPreference>(
        '/notifications/preferences/reset',
        body: <String, dynamic>{'user_id': userId},
        decoder: _preference,
      ),
    );
  }

  /// `GET /notifications/preferences/defaults` — the project's defaults.
  Future<ApiResponse<Map<String, dynamic>>> defaults() {
    return withNotificationErrors(
      () => _client.get<Map<String, dynamic>>(
        '/notifications/preferences/defaults',
        decoder: _map,
      ),
    );
  }

  /// `GET /notifications/preferences/timezones` — accepted timezone values.
  Future<ApiResponse<List<String>>> timezones() {
    return withNotificationErrors(
      () => _client.get<List<String>>(
        '/notifications/preferences/timezones',
        decoder: _stringList,
      ),
    );
  }

  /// `GET /notifications/preferences/frequencies` — accepted digest cadences.
  Future<ApiResponse<List<String>>> frequencies() {
    return withNotificationErrors(
      () => _client.get<List<String>>(
        '/notifications/preferences/frequencies',
        decoder: _stringList,
      ),
    );
  }

  Future<ApiResponse<NotificationPage<NotificationPreference>>> _list(
    String path, {
    String? search,
    NotificationChannel? channel,
    bool? enabled,
    int? limit,
    int? offset,
  }) {
    return withNotificationErrors(
      () => _client.get<NotificationPage<NotificationPreference>>(
        path,
        options: RequestOptions(
          query: <String, Object?>{
            'search': search,
            'channel': channel?.wireValue,
            'enabled': enabled,
            'limit': limit,
            'offset': offset,
          },
        ),
        decoder: (data) => NotificationPage<NotificationPreference>.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
          NotificationPreference.fromJson,
        ),
      ),
    );
  }

  static NotificationPreference _preference(Object? data) =>
      NotificationPreference.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );

  static Map<String, dynamic> _map(Object? data) =>
      data as Map<String, dynamic>? ?? const <String, dynamic>{};

  /// Normalizes the several shapes these reference endpoints return.
  ///
  /// The documented responses are inconsistent — some send a bare array, some
  /// wrap it under `items`, and some wrap it under a name specific to the
  /// endpoint. Rather than hard-code each key, fall back to the first list
  /// value in the object.
  static List<String> _stringList(Object? data) {
    if (data is List<dynamic>) {
      return data.whereType<String>().toList(growable: false);
    }
    if (data is Map<String, dynamic>) {
      var items = data['items'];
      if (items is! List<dynamic>) {
        for (final value in data.values) {
          if (value is List<dynamic>) {
            items = value;
            break;
          }
        }
      }
      if (items is List<dynamic>) {
        return items.whereType<String>().toList(growable: false);
      }
    }
    return const <String>[];
  }
}

/// Delivery provider status.
///
/// Exposed at `superso.notification.providers`.
class ProvidersModule {
  /// Creates a providers module bound to [client].
  const ProvidersModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /notifications/providers` — configured providers.
  Future<ApiResponse<List<NotificationProvider>>> list() {
    return withNotificationErrors(
      () => _client.get<List<NotificationProvider>>(
        '/notifications/providers',
        decoder: (data) {
          final list = data is List<dynamic>
              ? data
              : (data as Map<String, dynamic>?)?['providers']
                      as List<dynamic>? ??
                  const <dynamic>[];
          return list
              .whereType<Map<String, dynamic>>()
              .map(NotificationProvider.fromJson)
              .toList(growable: false);
        },
      ),
    );
  }

  /// `GET /notifications/providers/status` — per-provider health.
  Future<ApiResponse<Map<String, dynamic>>> status() {
    return withNotificationErrors(
      () => _client.get<Map<String, dynamic>>(
        '/notifications/providers/status',
        decoder: (data) =>
            data as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

/// The composition root for the Notification module.
///
/// ```dart
/// // Register this device for push
/// await superso.notification.devices.register(
///   userId: user.id,
///   deviceToken: fcmToken,
///   platform: DevicePlatform.android,
/// );
///
/// // Send one notification
/// await superso.notification.send(
///   channel: NotificationChannel.push,
///   recipientId: user.id,
///   title: 'Order shipped',
///   body: 'Your order is on its way.',
/// );
///
/// // Read the in-app inbox
/// final inbox = await superso.notification.inbox.list(userId: user.id);
/// print('${inbox.data.unreadCount} unread');
/// ```
///
/// Event management is exposed as flat, Event-suffixed methods (matching
/// [trigger]/[send]/[broadcast] rather than an `.events` submodule property):
/// [createEvent], [updateEvent], [deleteEvent], [listEvents], [getEvent],
/// [getEventHistory], [mapTemplates], [updateStatus], and [triggerEvent]
/// (an alias of [trigger]).
class NotificationModule implements SdkModule {
  /// Creates the notification module bound to [client].
  NotificationModule(this.client)
      : inbox = InboxModule(client),
        templates = TemplatesModule(client),
        _events = EventsModule(client),
        schedules = SchedulesModule(client),
        queue = QueueModule(client),
        devices = DevicesModule(client),
        preferences = PreferencesModule(client),
        providers = ProvidersModule(client);

  @override
  final SupersoHttpClient client;

  /// The in-app inbox.
  final InboxModule inbox;

  /// Template management.
  final TemplatesModule templates;

  // Not exposed as a public `events` property — mirroring the JS SDK, where
  // `trigger()`, `send()`, and `broadcast()` are flat top-level methods
  // rather than submodule properties, every EventsModule method is
  // re-exposed below as a flat, Event-suffixed method (`createEvent()`,
  // `updateEvent()`, etc.) instead.
  final EventsModule _events;

  /// Schedule management.
  final SchedulesModule schedules;

  /// Delivery queue inspection.
  final QueueModule queue;

  /// Push device registration.
  final DevicesModule devices;

  /// Per-user preferences.
  final PreferencesModule preferences;

  /// Delivery provider status.
  final ProvidersModule providers;

  /// `POST /notifications/send` — sends one notification to one recipient.
  ///
  /// Supply either [templateId] (rendered server-side with [variables]) or an
  /// explicit [title] and [body]. A [ValidationError] is thrown if neither is
  /// present, since the backend would otherwise reject the request after a
  /// round trip.
  Future<ApiResponse<NotificationSendResult>> send({
    required NotificationChannel channel,
    required String recipientId,
    String? recipientRef,
    String? templateId,
    String? title,
    String? body,
    Map<String, dynamic>? variables,
    Map<String, dynamic>? context,
    String? actionUrl,
    String? imageUrl,
    String? icon,
    String? category,
    String? scheduledFor,
    Map<String, dynamic>? metadata,
  }) {
    if (templateId == null && (body == null || body.isEmpty)) {
      throw const ValidationError(
        'Superso: a notification needs either a templateId or a body.',
      );
    }
    return withNotificationErrors(
      () => client.post<NotificationSendResult>(
        '/notifications/send',
        body: <String, dynamic>{
          'channel': channel.wireValue,
          'recipient_id': recipientId,
          if (recipientRef != null) 'recipient_ref': recipientRef,
          if (templateId != null) 'template_id': templateId,
          if (title != null) 'subject': title,
          if (body != null) 'body': body,
          if (variables != null) 'variables': variables,
          if (context != null) 'context': context,
          if (actionUrl != null) 'action_url': actionUrl,
          if (imageUrl != null) 'image_url': imageUrl,
          if (icon != null) 'icon': icon,
          if (category != null) 'category': category,
          if (scheduledFor != null) 'scheduled_for': scheduledFor,
          if (metadata != null) 'metadata': metadata,
        },
        decoder: _sendResult,
      ),
    );
  }

  /// `POST /notifications/broadcast` — sends to many recipients at once.
  ///
  /// [targetMode] selects how recipients are resolved. When it is
  /// [BroadcastTargetMode.selectedUsers], [recipientIds] must be non-empty.
  Future<ApiResponse<NotificationSendResult>> broadcast({
    required NotificationChannel channel,
    BroadcastTargetMode? targetMode,
    List<String>? recipientIds,
    String? templateId,
    String? title,
    String? body,
    Map<String, dynamic>? variables,
    Map<String, dynamic>? metadata,
  }) {
    if (targetMode == BroadcastTargetMode.selectedUsers &&
        (recipientIds == null || recipientIds.isEmpty)) {
      throw const ValidationError(
        'Superso: targetMode `selected_users` requires a non-empty '
        'recipientIds list.',
      );
    }
    if (templateId == null && (body == null || body.isEmpty)) {
      throw const ValidationError(
        'Superso: a broadcast needs either a templateId or a body.',
      );
    }
    return withNotificationErrors(
      () => client.post<NotificationSendResult>(
        '/notifications/broadcast',
        body: <String, dynamic>{
          'channel': channel.wireValue,
          if (targetMode != null) 'target_mode': targetMode.wireValue,
          if (recipientIds != null) 'recipient_ids': recipientIds,
          if (templateId != null) 'template_id': templateId,
          if (title != null) 'subject': title,
          if (body != null) 'body': body,
          if (variables != null) 'variables': variables,
          if (metadata != null) 'metadata': metadata,
        },
        decoder: _sendResult,
      ),
    );
  }

  /// `POST /notifications/trigger` — fires a configured event.
  ///
  /// Set [dryRun] to resolve recipients and render templates without
  /// delivering anything — useful for verifying an event's configuration.
  Future<ApiResponse<NotificationSendResult>> trigger({
    required String eventKey,
    required String recipientId,
    String? recipientRef,
    Map<String, dynamic>? context,
    bool? dryRun,
    List<NotificationChannel>? channels,
  }) {
    return withNotificationErrors(
      () => client.post<NotificationSendResult>(
        '/notifications/trigger',
        body: <String, dynamic>{
          'event_key': eventKey,
          'recipient_id': recipientId,
          if (recipientRef != null) 'recipient_ref': recipientRef,
          if (context != null) 'context': context,
          if (dryRun != null) 'dry_run': dryRun,
          if (channels != null)
            'channels':
                channels.map((c) => c.wireValue).toList(growable: false),
        },
        decoder: _sendResult,
      ),
    );
  }

  /// Alias of [trigger] — same endpoint, same behavior. Named to match the
  /// other Event-suffixed methods below.
  Future<ApiResponse<NotificationSendResult>> triggerEvent({
    required String eventKey,
    required String recipientId,
    String? recipientRef,
    Map<String, dynamic>? context,
    bool? dryRun,
    List<NotificationChannel>? channels,
  }) =>
      trigger(
        eventKey: eventKey,
        recipientId: recipientId,
        recipientRef: recipientRef,
        context: context,
        dryRun: dryRun,
        channels: channels,
      );

  /// `GET /notifications/events` — docs/notification.md "List Events".
  Future<ApiResponse<NotificationEventPage>> listEvents({
    bool? isActive,
    String? category,
    int? limit,
    int? offset,
  }) =>
      _events.list(
        isActive: isActive,
        category: category,
        limit: limit,
        offset: offset,
      );

  /// `GET /notifications/events/:id` — docs/notification.md "Get Event".
  Future<ApiResponse<NotificationEvent>> getEvent(String id) => _events.get(id);

  /// `POST /notifications/events` — docs/notification.md "Create Event".
  ///
  /// [templates] is optional: omit it (or pass an empty list) to create the
  /// event without any channel mapped yet, and map channels later with
  /// [mapTemplates] — the backend stores this as a valid event either way.
  /// It just can't be triggered until at least one channel is mapped.
  Future<ApiResponse<NotificationEvent>> createEvent({
    required String eventKey,
    required String name,
    String? description,
    String? category,
    bool? isActive,
    List<EventTemplateMapping>? templates,
  }) =>
      _events.create(
        eventKey: eventKey,
        name: name,
        description: description,
        category: category,
        isActive: isActive,
        templates: templates,
      );

  /// `PATCH` (or `PUT`) `/notifications/events/:id` — docs/notification.md
  /// "Update Event".
  Future<ApiResponse<NotificationEvent>> updateEvent(
    String id, {
    String? name,
    String? description,
    String? category,
    bool? isActive,
    List<EventTemplateMapping>? templates,
  }) =>
      _events.update(
        id,
        name: name,
        description: description,
        category: category,
        isActive: isActive,
        templates: templates,
      );

  /// `DELETE /notifications/events/:id` — docs/notification.md "Delete Event".
  Future<ApiResponse<void>> deleteEvent(String id) => _events.delete(id);

  /// `PATCH` (or `PUT`) `/notifications/events/:id/templates` —
  /// docs/notification.md "Update Event Templates". Fully replaces the
  /// mapping set (set semantics, not a partial merge).
  Future<ApiResponse<List<EventTemplateMapping>>> mapTemplates(
    String id,
    List<EventTemplateMapping> templates,
  ) =>
      _events.mapTemplates(id, templates);

  /// `PATCH /notifications/events/:id/status` — docs/notification.md
  /// "Update Event Status". Activates/deactivates only — leaves every other
  /// field untouched.
  Future<ApiResponse<NotificationEvent>> updateStatus(String id, bool active) =>
      _events.updateStatus(id, active);

  /// `GET /notifications/events/:id/history` — docs/notification.md "Event
  /// History". New in v0.3.1.
  Future<ApiResponse<EventHistoryResult>> getEventHistory(
    String id, {
    int? limit,
    int? offset,
  }) =>
      _events.getHistory(id, limit: limit, offset: offset);

  /// `GET /notifications/queue/history` — the delivery log.
  ///
  /// The platform exposes delivery history through the queue history endpoint;
  /// this is a named alias so callers looking for "logs" find it.
  Future<ApiResponse<NotificationPage<QueueItem>>> logs({
    QueueStatus? status,
    NotificationChannel? channel,
    int? limit,
    int? offset,
  }) =>
      queue.history(
        status: status,
        channel: channel,
        limit: limit,
        offset: offset,
      );

  /// `GET /notifications/analytics` — aggregated delivery analytics.
  ///
  /// [channel] accepts a specific channel or `null` for all channels.
  Future<ApiResponse<NotificationAnalytics>> analytics({
    int? days,
    NotificationChannel? channel,
  }) {
    return withNotificationErrors(
      () => client.get<NotificationAnalytics>(
        '/notifications/analytics',
        options: RequestOptions(
          query: <String, Object?>{
            'days': days,
            'channel': channel?.wireValue ?? 'all',
          },
        ),
        decoder: (data) => NotificationAnalytics.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  static NotificationSendResult _sendResult(Object? data) =>
      NotificationSendResult.fromJson(data as Map<String, dynamic>?);
}
