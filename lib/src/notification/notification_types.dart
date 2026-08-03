/// Domain models for the Notification module, mirrored from
/// `docs/notification.md`.
///
/// Names are prefixed with `Notification` where a bare noun would collide
/// with another module's export.
///
/// Dart port of `supersosdk/src/notification/{types,responses}.ts`.
library;

import 'package:meta/meta.dart';

/// Delivery channel. Every send, broadcast, trigger, template, schedule, and
/// queue endpoint accepts these four.
enum NotificationChannel {
  /// In-app inbox.
  inapp('inapp'),

  /// Mobile or web push.
  push('push'),

  /// Email.
  email('email'),

  /// SMS.
  sms('sms');

  const NotificationChannel(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [inapp] for anything unrecognized.
  static NotificationChannel fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => NotificationChannel.inapp,
      );
}

/// In-app inbox item priority.
enum NotificationPriority {
  /// Lowest priority.
  low('low'),

  /// Default priority.
  normal('normal'),

  /// Elevated priority.
  high('high'),

  /// Highest priority.
  urgent('urgent');

  const NotificationPriority(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [normal] for anything unrecognized.
  static NotificationPriority fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => NotificationPriority.normal,
      );
}

/// What created a queue item or log entry.
enum NotificationSource {
  /// Sent by hand from the dashboard.
  manual('manual'),

  /// Produced by an event trigger.
  event('event'),

  /// Produced by a schedule.
  schedule('schedule'),

  /// Produced by a broadcast.
  broadcast('broadcast'),

  /// Sent through an SDK.
  sdk('sdk'),

  /// Sent through the REST API.
  api('api'),

  /// Produced by the platform itself.
  system('system');

  const NotificationSource(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [system] for anything unrecognized.
  static NotificationSource fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => NotificationSource.system,
      );
}

/// Queue item lifecycle status.
enum QueueStatus {
  /// Waiting to be picked up.
  pending('pending'),

  /// Currently being delivered.
  processing('processing'),

  /// Delivered successfully.
  completed('completed'),

  /// Delivery failed after all retries.
  failed('failed'),

  /// Cancelled before delivery.
  cancelled('cancelled');

  const QueueStatus(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [pending] for anything unrecognized.
  static QueueStatus fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => QueueStatus.pending,
      );
}

/// The delivery provider behind a channel.
enum NotificationProviderName {
  /// Firebase Cloud Messaging.
  fcm('fcm'),

  /// Apple Push Notification service.
  apns('apns'),

  /// Resend, for email.
  resend('resend'),

  /// Africa's Talking, for SMS.
  africastalking('africastalking'),

  /// Hormuud, for SMS.
  hormuud('hormuud'),

  /// The in-app inbox itself.
  inapp('inapp');

  const NotificationProviderName(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [inapp] for anything unrecognized.
  static NotificationProviderName fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => NotificationProviderName.inapp,
      );
}

/// How a broadcast resolves its recipients.
enum BroadcastTargetMode {
  /// Every user with a registered push device.
  deviceUsers('device_users'),

  /// Every authenticated user in the project.
  authUsers('auth_users'),

  /// Only the explicitly supplied recipient IDs.
  selectedUsers('selected_users');

  const BroadcastTargetMode(this.wireValue);

  /// The value sent to the backend.
  final String wireValue;
}

/// How a schedule resolves its recipients.
enum ScheduleRecipientType {
  /// A single named user.
  user('user'),

  /// Every user with a registered push device.
  deviceUsers('device_users'),

  /// Every authenticated user in the project.
  authUsers('auth_users');

  const ScheduleRecipientType(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [user] for anything unrecognized.
  static ScheduleRecipientType fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => ScheduleRecipientType.user,
      );
}

/// Schedule cadence.
enum ScheduleType {
  /// Runs exactly once.
  once('once'),

  /// Runs on a cron expression.
  recurring('recurring');

  const ScheduleType(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [once] for anything unrecognized.
  static ScheduleType fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => ScheduleType.once,
      );
}

/// Schedule lifecycle status.
enum ScheduleStatus {
  /// Running on schedule.
  active('active'),

  /// Temporarily suspended.
  paused('paused'),

  /// Reached its run limit.
  completed('completed'),

  /// Cancelled permanently.
  cancelled('cancelled');

  const ScheduleStatus(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [active] for anything unrecognized.
  static ScheduleStatus fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => ScheduleStatus.active,
      );
}

/// How often a user receives batched notifications.
enum DeliveryFrequency {
  /// Delivered as they occur.
  immediately('immediately'),

  /// Batched hourly.
  hourlyDigest('hourly_digest'),

  /// Batched daily.
  dailyDigest('daily_digest'),

  /// Batched weekly.
  weeklyDigest('weekly_digest');

  const DeliveryFrequency(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [immediately] for anything
  /// unrecognized.
  static DeliveryFrequency fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => DeliveryFrequency.immediately,
      );
}

/// Notification sound mode.
enum SoundSetting {
  /// The platform default sound.
  defaultSound('default'),

  /// No sound.
  silent('silent'),

  /// An application-supplied sound.
  custom('custom');

  const SoundSetting(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [defaultSound] for anything
  /// unrecognized.
  static SoundSetting fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => SoundSetting.defaultSound,
      );
}

/// The platform a push device runs on.
enum DevicePlatform {
  /// Android.
  android('android'),

  /// iOS.
  ios('ios'),

  /// Web push.
  web('web');

  const DevicePlatform(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [android] for anything unrecognized.
  static DevicePlatform fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => DevicePlatform.android,
      );
}

/// The push provider a device is registered with.
enum DeviceProviderName {
  /// Firebase Cloud Messaging.
  fcm('fcm'),

  /// Apple Push Notification service.
  apns('apns');

  const DeviceProviderName(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [fcm] for anything unrecognized.
  static DeviceProviderName fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => DeviceProviderName.fcm,
      );
}

/// Sort order accepted by inbox list endpoints.
enum InboxSort {
  /// Newest first.
  createdAtDesc('created_at_desc'),

  /// Oldest first.
  createdAtAsc('created_at_asc'),

  /// Highest priority first.
  priorityDesc('priority_desc'),

  /// Lowest priority first.
  priorityAsc('priority_asc');

  const InboxSort(this.wireValue);

  /// The value sent to the backend.
  final String wireValue;
}

/// Sort column accepted by queue list endpoints.
enum QueueSortBy {
  /// When the item was enqueued.
  createdAt('created_at'),

  /// When delivery began.
  startedAt('started_at'),

  /// When delivery finished.
  completedAt('completed_at'),

  /// Lifecycle status.
  status('status'),

  /// Delivery attempt count.
  attempts('attempts'),

  /// Delivery channel.
  channel('channel');

  const QueueSortBy(this.wireValue);

  /// The value sent to the backend.
  final String wireValue;
}

/// Sort direction.
enum SortDirection {
  /// Ascending.
  asc('asc'),

  /// Descending.
  desc('desc');

  const SortDirection(this.wireValue);

  /// The value sent to the backend.
  final String wireValue;
}

/// The generic offset-paginated envelope shared by every Notification list
/// endpoint.
@immutable
class NotificationPage<T> {
  /// Creates a page.
  const NotificationPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// Decodes a page, mapping each item through [fromItem].
  factory NotificationPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) fromItem,
  ) =>
      NotificationPage<T>(
        items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(fromItem)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
        offset: (json['offset'] as num?)?.toInt() ?? 0,
      );

  /// The items on this page.
  final List<T> items;

  /// Total items matching the query.
  final int total;

  /// Page size used.
  final int limit;

  /// Offset used.
  final int offset;

  @override
  String toString() =>
      'NotificationPage(items: ${items.length}, total: $total)';
}

/// A single in-app inbox item.
///
/// The documentation describes two overlapping field sets for this resource —
/// one example uses `click_count` with no `clicked`/`clicked_at`, another uses
/// `clicked`/`clicked_at` plus `starred_at` and `icon` instead of `icon_url`.
/// Both are kept optional here so no documented field is dropped and none is
/// invented.
@immutable
class InboxItem {
  /// Creates an inbox item.
  const InboxItem({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.title,
    required this.body,
    required this.priority,
    required this.isRead,
    required this.isArchived,
    required this.isStarred,
    required this.createdAt,
    required this.updatedAt,
    this.logId,
    this.batchId,
    this.source,
    this.category,
    this.icon,
    this.iconUrl,
    this.imageUrl,
    this.actionUrl,
    this.metadata,
    this.isDeleted,
    this.clickCount,
    this.clicked,
    this.clickedAt,
    this.readAt,
    this.archivedAt,
    this.starredAt,
    this.deletedAt,
    this.expiresAt,
  });

  /// Decodes an inbox item from JSON.
  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        priority: NotificationPriority.fromWire(json['priority'] as String?),
        isRead: json['is_read'] as bool? ?? false,
        isArchived: json['is_archived'] as bool? ?? false,
        isStarred: json['is_starred'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        logId: json['log_id'] as String?,
        batchId: json['batch_id'] as String?,
        source: json['source'] == null
            ? null
            : NotificationSource.fromWire(json['source'] as String?),
        category: json['category'] as String?,
        icon: json['icon'] as String?,
        iconUrl: json['icon_url'] as String?,
        imageUrl: json['image_url'] as String?,
        actionUrl: json['action_url'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        isDeleted: json['is_deleted'] as bool?,
        clickCount: (json['click_count'] as num?)?.toInt(),
        clicked: json['clicked'] as bool?,
        clickedAt: json['clicked_at'] as String?,
        readAt: json['read_at'] as String?,
        archivedAt: json['archived_at'] as String?,
        starredAt: json['starred_at'] as String?,
        deletedAt: json['deleted_at'] as String?,
        expiresAt: json['expires_at'] as String?,
      );

  /// Item identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// The recipient.
  final String userId;

  /// The delivery log entry this item came from.
  final String? logId;

  /// The batch this item was part of, for broadcasts.
  final String? batchId;

  /// What produced this item.
  final NotificationSource? source;

  /// Item title.
  final String title;

  /// Item body.
  final String body;

  /// Application-defined category.
  final String? category;

  /// Display priority.
  final NotificationPriority priority;

  /// Deep link or URL opened when the item is tapped.
  final String? actionUrl;

  /// Icon identifier.
  final String? icon;

  /// Icon URL.
  final String? iconUrl;

  /// Hero image URL.
  final String? imageUrl;

  /// Arbitrary metadata attached at send time.
  final Map<String, dynamic>? metadata;

  /// Whether the recipient has read this item.
  final bool isRead;

  /// Whether the item is archived.
  final bool isArchived;

  /// Whether the recipient starred the item.
  final bool isStarred;

  /// Whether the item is soft-deleted.
  final bool? isDeleted;

  /// How many times the item was tapped.
  final int? clickCount;

  /// Whether the item has been tapped at least once.
  final bool? clicked;

  /// ISO-8601 timestamp of the first tap.
  final String? clickedAt;

  /// ISO-8601 timestamp the item was read.
  final String? readAt;

  /// ISO-8601 timestamp the item was archived.
  final String? archivedAt;

  /// ISO-8601 timestamp the item was starred.
  final String? starredAt;

  /// ISO-8601 timestamp the item was soft-deleted.
  final String? deletedAt;

  /// ISO-8601 timestamp the item stops being shown.
  final String? expiresAt;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  @override
  String toString() => 'InboxItem(id: $id, title: $title, read: $isRead)';
}

/// A page of inbox items, plus the recipient's unread count.
@immutable
class InboxList {
  /// Creates an inbox list.
  const InboxList({required this.page, required this.unreadCount});

  /// Decodes an inbox list from JSON.
  factory InboxList.fromJson(Map<String, dynamic> json) => InboxList(
        page: NotificationPage<InboxItem>.fromJson(json, InboxItem.fromJson),
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );

  /// The page of items.
  final NotificationPage<InboxItem> page;

  /// How many unread items the recipient has in total.
  final int unreadCount;

  /// The items on this page — shorthand for `page.items`.
  List<InboxItem> get items => page.items;

  @override
  String toString() =>
      'InboxList(items: ${items.length}, unread: $unreadCount)';
}

/// Variable definition metadata for a template.
///
/// Purely documentation and tooling metadata — never read by the placeholder
/// engine at send time.
@immutable
class TemplateVariable {
  /// Creates a variable definition.
  const TemplateVariable({
    required this.key,
    this.description,
    this.required,
    this.defaultValue,
  });

  /// Decodes a variable definition from JSON.
  factory TemplateVariable.fromJson(Map<String, dynamic> json) =>
      TemplateVariable(
        key: json['key'] as String? ?? '',
        description: json['description'] as String?,
        required: json['required'] as bool?,
        defaultValue: json['default'] as String?,
      );

  /// The placeholder name, without delimiters.
  final String key;

  /// What this variable is for.
  final String? description;

  /// Whether callers must supply it.
  final bool? required;

  /// The value substituted when the caller omits it.
  final String? defaultValue;

  /// Encodes this definition to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        if (description != null) 'description': description,
        if (required != null) 'required': required,
        if (defaultValue != null) 'default': defaultValue,
      };
}

/// A saved notification template.
@immutable
class NotificationTemplate {
  /// Creates a template.
  const NotificationTemplate({
    required this.id,
    required this.name,
    required this.slug,
    required this.channel,
    required this.body,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.subject,
    this.variables = const <TemplateVariable>[],
  });

  /// Decodes a template from JSON.
  factory NotificationTemplate.fromJson(Map<String, dynamic> json) =>
      NotificationTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        channel: NotificationChannel.fromWire(json['channel'] as String?),
        body: json['body'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        subject: json['subject'] as String?,
        variables: (json['variables'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(TemplateVariable.fromJson)
            .toList(growable: false),
      );

  /// Template identifier.
  final String id;

  /// Display name.
  final String name;

  /// Stable slug, usable in place of [id] when sending.
  final String slug;

  /// Which channel this template renders for.
  final NotificationChannel channel;

  /// Subject line, for email.
  final String? subject;

  /// Body, with `{{placeholder}}` variables.
  final String body;

  /// Declared variables.
  final List<TemplateVariable> variables;

  /// Whether the template may be used.
  final bool isActive;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  @override
  String toString() => 'NotificationTemplate(slug: $slug, channel: '
      '${channel.wireValue})';
}

/// A saved recurring or one-time schedule.
@immutable
class NotificationSchedule {
  /// Creates a schedule.
  const NotificationSchedule({
    required this.id,
    required this.name,
    required this.channel,
    required this.recipientType,
    required this.scheduleType,
    required this.status,
    required this.runCount,
    required this.createdAt,
    required this.updatedAt,
    this.templateId,
    this.recipientRef,
    this.cronExpression,
    this.runAt,
    this.timezone,
    this.maxRuns,
    this.nextRunAt,
    this.lastRunAt,
    this.completedAt,
    this.failedAt,
    this.variables,
    this.context,
  });

  /// Decodes a schedule from JSON.
  factory NotificationSchedule.fromJson(Map<String, dynamic> json) =>
      NotificationSchedule(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        channel: NotificationChannel.fromWire(json['channel'] as String?),
        recipientType:
            ScheduleRecipientType.fromWire(json['recipient_type'] as String?),
        scheduleType: ScheduleType.fromWire(json['schedule_type'] as String?),
        status: ScheduleStatus.fromWire(json['status'] as String?),
        runCount: (json['run_count'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        templateId: json['template_id'] as String?,
        recipientRef: json['recipient_ref'] as String?,
        cronExpression: json['cron_expression'] as String?,
        runAt: json['run_at'] as String?,
        timezone: json['timezone'] as String?,
        maxRuns: (json['max_runs'] as num?)?.toInt(),
        nextRunAt: json['next_run_at'] as String?,
        lastRunAt: json['last_run_at'] as String?,
        completedAt: json['completed_at'] as String?,
        failedAt: json['failed_at'] as String?,
        variables: json['variables'] as Map<String, dynamic>?,
        context: json['context'] as Map<String, dynamic>?,
      );

  /// Schedule identifier.
  final String id;

  /// Display name.
  final String name;

  /// Delivery channel.
  final NotificationChannel channel;

  /// Template rendered on each run.
  final String? templateId;

  /// How recipients are resolved.
  final ScheduleRecipientType recipientType;

  /// The specific recipient, when [recipientType] is
  /// [ScheduleRecipientType.user].
  final String? recipientRef;

  /// Whether this runs once or repeatedly.
  final ScheduleType scheduleType;

  /// Cron expression, for recurring schedules.
  final String? cronExpression;

  /// ISO-8601 run time, for one-time schedules.
  final String? runAt;

  /// IANA timezone the cron expression is evaluated in.
  final String? timezone;

  /// Stop after this many runs.
  final int? maxRuns;

  /// Current lifecycle status.
  final ScheduleStatus status;

  /// Runs completed so far.
  final int runCount;

  /// ISO-8601 timestamp of the next run.
  final String? nextRunAt;

  /// ISO-8601 timestamp of the last run.
  final String? lastRunAt;

  /// ISO-8601 timestamp the schedule completed.
  final String? completedAt;

  /// ISO-8601 timestamp the schedule last failed.
  final String? failedAt;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  /// Template variables applied on each run.
  final Map<String, dynamic>? variables;

  /// Additional context passed to the template engine.
  final Map<String, dynamic>? context;

  @override
  String toString() =>
      'NotificationSchedule(name: $name, status: ${status.wireValue})';
}

/// A single delivery queue item.
@immutable
class QueueItem {
  /// Creates a queue item.
  const QueueItem({
    required this.id,
    required this.projectId,
    required this.channel,
    required this.provider,
    required this.recipientId,
    required this.recipientRef,
    required this.subject,
    required this.body,
    required this.status,
    required this.raw,
    this.logId,
    this.templateId,
    this.eventId,
    this.scheduleId,
    this.broadcastId,
    this.attempts,
    this.createdAt,
  });

  /// Decodes a queue item from JSON.
  ///
  /// The complete decoded map is retained in [raw], because the documented
  /// field list for this resource is long and evolving; anything not surfaced
  /// as a typed property is still reachable without a SDK release.
  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        channel: NotificationChannel.fromWire(json['channel'] as String?),
        provider:
            NotificationProviderName.fromWire(json['provider'] as String?),
        recipientId: json['recipient_id'] as String? ?? '',
        recipientRef: json['recipient_ref'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        body: json['body'] as String? ?? '',
        status: QueueStatus.fromWire(json['status'] as String?),
        raw: json,
        logId: json['log_id'] as String?,
        templateId: json['template_id'] as String?,
        eventId: json['event_id'] as String?,
        scheduleId: json['schedule_id'] as String?,
        broadcastId: json['broadcast_id'] as String?,
        attempts: (json['attempts'] as num?)?.toInt(),
        createdAt: json['created_at'] as String?,
      );

  /// Queue item identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// The delivery log entry, once one exists.
  final String? logId;

  /// Delivery channel.
  final NotificationChannel channel;

  /// Delivery provider.
  final NotificationProviderName provider;

  /// The recipient's user ID.
  final String recipientId;

  /// The concrete address delivered to — a token, email, or phone number.
  final String recipientRef;

  /// Rendered subject.
  final String subject;

  /// Rendered body.
  final String body;

  /// Template used, if any.
  final String? templateId;

  /// Triggering event, if any.
  final String? eventId;

  /// Originating schedule, if any.
  final String? scheduleId;

  /// Originating broadcast, if any.
  final String? broadcastId;

  /// Delivery attempts made.
  final int? attempts;

  /// Lifecycle status.
  final QueueStatus status;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'QueueItem(id: $id, ${channel.wireValue}, ${status.wireValue})';
}

/// A registered push device.
@immutable
class NotificationDevice {
  /// Creates a device record.
  const NotificationDevice({
    required this.id,
    required this.userId,
    required this.deviceToken,
    required this.platform,
    required this.raw,
    this.provider,
    this.appVersion,
    this.deviceModel,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a device from JSON.
  factory NotificationDevice.fromJson(Map<String, dynamic> json) =>
      NotificationDevice(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        deviceToken: json['device_token'] as String? ?? '',
        platform: DevicePlatform.fromWire(json['platform'] as String?),
        raw: json,
        provider: json['provider'] == null
            ? null
            : DeviceProviderName.fromWire(json['provider'] as String?),
        appVersion: json['app_version'] as String?,
        deviceModel: json['device_model'] as String?,
        isActive: json['is_active'] as bool?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// Device identifier.
  final String id;

  /// The owning user.
  final String userId;

  /// The push token.
  final String deviceToken;

  /// The device's platform.
  final DevicePlatform platform;

  /// The push provider.
  final DeviceProviderName? provider;

  /// The app version that registered this device.
  final String? appVersion;

  /// The device model string.
  final String? deviceModel;

  /// Whether the device still receives pushes.
  final bool? isActive;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'NotificationDevice(id: $id, ${platform.wireValue})';
}

/// A user's notification preferences.
@immutable
class NotificationPreference {
  /// Creates a preference record.
  const NotificationPreference({
    required this.userId,
    required this.raw,
    this.receiveNotifications,
    this.inappEnabled,
    this.pushEnabled,
    this.emailEnabled,
    this.smsEnabled,
    this.quietHoursEnabled,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.timezone,
    this.deliveryFrequency,
    this.soundSettings,
    this.badgeEnabled,
  });

  /// Decodes preferences from JSON.
  factory NotificationPreference.fromJson(Map<String, dynamic> json) =>
      NotificationPreference(
        userId: json['user_id'] as String? ?? '',
        raw: json,
        receiveNotifications: json['receive_notifications'] as bool?,
        inappEnabled: json['inapp_enabled'] as bool?,
        pushEnabled: json['push_enabled'] as bool?,
        emailEnabled: json['email_enabled'] as bool?,
        smsEnabled: json['sms_enabled'] as bool?,
        quietHoursEnabled: json['quiet_hours_enabled'] as bool?,
        quietHoursStart: json['quiet_hours_start'] as String?,
        quietHoursEnd: json['quiet_hours_end'] as String?,
        timezone: json['timezone'] as String?,
        deliveryFrequency: json['delivery_frequency'] == null
            ? null
            : DeliveryFrequency.fromWire(json['delivery_frequency'] as String?),
        soundSettings: json['sound_settings'] == null
            ? null
            : SoundSetting.fromWire(json['sound_settings'] as String?),
        badgeEnabled: json['badge_enabled'] as bool?,
      );

  /// The user these preferences belong to.
  final String userId;

  /// The master switch. When false, nothing is delivered.
  final bool? receiveNotifications;

  /// Whether in-app inbox delivery is enabled.
  final bool? inappEnabled;

  /// Whether push delivery is enabled.
  final bool? pushEnabled;

  /// Whether email delivery is enabled.
  final bool? emailEnabled;

  /// Whether SMS delivery is enabled.
  final bool? smsEnabled;

  /// Whether quiet hours are observed.
  final bool? quietHoursEnabled;

  /// Quiet hours start, as `HH:mm`.
  final String? quietHoursStart;

  /// Quiet hours end, as `HH:mm`.
  final String? quietHoursEnd;

  /// IANA timezone quiet hours are evaluated in.
  final String? timezone;

  /// Batching cadence.
  final DeliveryFrequency? deliveryFrequency;

  /// Sound mode.
  final SoundSetting? soundSettings;

  /// Whether the app icon badge is updated.
  final bool? badgeEnabled;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'NotificationPreference(userId: $userId)';
}

/// A configured delivery provider.
@immutable
class NotificationProvider {
  /// Creates a provider record.
  const NotificationProvider({
    required this.name,
    required this.raw,
    this.channel,
    this.isEnabled,
    this.isConfigured,
  });

  /// Decodes a provider from JSON.
  factory NotificationProvider.fromJson(Map<String, dynamic> json) =>
      NotificationProvider(
        name: json['name'] as String? ?? json['provider'] as String? ?? '',
        raw: json,
        channel: json['channel'] == null
            ? null
            : NotificationChannel.fromWire(json['channel'] as String?),
        isEnabled: json['is_enabled'] as bool? ?? json['enabled'] as bool?,
        isConfigured:
            json['is_configured'] as bool? ?? json['configured'] as bool?,
      );

  /// The provider's name.
  final String name;

  /// The channel it serves.
  final NotificationChannel? channel;

  /// Whether it is enabled for the project.
  final bool? isEnabled;

  /// Whether its credentials are configured.
  final bool? isConfigured;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'NotificationProvider($name)';
}

/// Aggregated delivery analytics.
@immutable
class NotificationAnalytics {
  /// Creates an analytics summary.
  const NotificationAnalytics({required this.raw});

  /// Decodes analytics from JSON.
  ///
  /// The documented shape varies by channel filter and date range, so the
  /// payload is retained verbatim rather than flattened into properties that
  /// would be wrong for some filter combinations.
  factory NotificationAnalytics.fromJson(Map<String, dynamic> json) =>
      NotificationAnalytics(raw: json);

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Reads a top-level integer metric, or `null` when absent.
  int? metric(String key) => (raw[key] as num?)?.toInt();

  @override
  String toString() => 'NotificationAnalytics(${raw.keys.join(', ')})';
}

/// The result of a send, broadcast, or trigger call.
@immutable
class NotificationSendResult {
  /// Creates a send result.
  const NotificationSendResult({required this.raw, this.id, this.queued});

  /// Decodes a send result from JSON.
  factory NotificationSendResult.fromJson(Map<String, dynamic>? json) =>
      NotificationSendResult(
        raw: json ?? const <String, dynamic>{},
        id: json?['id'] as String? ?? json?['log_id'] as String?,
        queued: (json?['queued'] as num?)?.toInt() ??
            (json?['count'] as num?)?.toInt(),
      );

  /// The created log or batch identifier, when the backend returns one.
  final String? id;

  /// How many notifications were enqueued, for broadcasts.
  final int? queued;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'NotificationSendResult(id: $id, queued: $queued)';
}

/// Inbox unread and total counts.
@immutable
class InboxCounts {
  /// Creates a counts summary.
  const InboxCounts({
    required this.total,
    required this.unread,
    required this.raw,
    this.archived,
    this.starred,
  });

  /// Decodes counts from JSON.
  factory InboxCounts.fromJson(Map<String, dynamic>? json) => InboxCounts(
        total: (json?['total'] as num?)?.toInt() ?? 0,
        unread: (json?['unread'] as num?)?.toInt() ??
            (json?['unread_count'] as num?)?.toInt() ??
            0,
        raw: json ?? const <String, dynamic>{},
        archived: (json?['archived'] as num?)?.toInt(),
        starred: (json?['starred'] as num?)?.toInt(),
      );

  /// Total items.
  final int total;

  /// Unread items.
  final int unread;

  /// Archived items.
  final int? archived;

  /// Starred items.
  final int? starred;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'InboxCounts(total: $total, unread: $unread)';
}
