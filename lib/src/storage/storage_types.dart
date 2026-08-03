/// Domain models for the Storage module, mirrored from `docs/storage.md`.
///
/// Names follow the `AuthUser`/`DatabaseDocument` convention used by every
/// other module. `StorageFile` is never bare `File` — that name collides with
/// `dart:io`'s `File`, which Flutter apps import constantly.
///
/// **Scope note.** `docs/storage.md` documents two authentication models: the
/// SDK API (`X-API-Key`, `/v1/storage/*`, what this module calls) and the
/// Admin Dashboard API (`Authorization: Bearer <admin_jwt>`). Signed URL
/// tokens, provider configuration writes, usage, activity logs, and webhooks
/// exist only under the Admin API — the SDK route table has no endpoints for
/// them, so this module exposes no callable methods for those. Their data
/// shapes are still declared here so a consumer that receives one through
/// another channel (e.g. a dashboard app built on this same package) has a
/// strict type to use.
///
/// Dart port of `supersosdk/src/storage/types.ts`.
library;

import 'package:meta/meta.dart';

/// Whether a bucket or file is publicly readable.
enum StorageVisibility {
  /// Readable by anyone with the URL.
  public('public'),

  /// Requires authentication.
  private('private');

  const StorageVisibility(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [private] for anything unrecognized.
  static StorageVisibility fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => StorageVisibility.private,
      );
}

/// The delivery backend serving a bucket's files.
enum StorageProviderName {
  /// Cloudinary.
  cloudinary('cloudinary'),

  /// Amazon S3.
  s3('s3'),

  /// Server-local disk.
  local('local');

  const StorageProviderName(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [local] for anything unrecognized.
  static StorageProviderName fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => StorageProviderName.local,
      );
}

/// Lifecycle of a chunked upload session.
enum UploadSessionStatus {
  /// Created but no chunk received yet.
  pending('pending'),

  /// At least one chunk received.
  inProgress('in_progress'),

  /// Every chunk received and the file assembled.
  complete('complete'),

  /// Assembly or a chunk write failed.
  failed('failed'),

  /// The session outlived its expiry window.
  expired('expired');

  const UploadSessionStatus(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [pending] for anything unrecognized.
  static UploadSessionStatus fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => UploadSessionStatus.pending,
      );
}

/// Who performed a logged storage action.
enum StorageActorType {
  /// A dashboard administrator.
  admin('admin'),

  /// An end user acting through the SDK.
  sdkUser('sdk_user'),

  /// The platform itself, e.g. a retention sweep.
  system('system');

  const StorageActorType(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [system] for anything unrecognized.
  static StorageActorType fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => StorageActorType.system,
      );
}

/// The action recorded on an activity log entry.
enum StorageLogAction {
  /// A file was uploaded.
  upload('upload'),

  /// A file was deleted.
  delete('delete'),

  /// A file was downloaded.
  download('download'),

  /// A file's metadata was updated.
  update('update'),

  /// A file was accessed.
  access('access');

  const StorageLogAction(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [access] for anything unrecognized.
  static StorageLogAction fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => StorageLogAction.access,
      );
}

/// Realtime event names broadcast on the `storage` channel.
enum StorageRealtimeEvent {
  /// A file finished uploading.
  fileUploaded('file.uploaded'),

  /// A file was deleted.
  fileDeleted('file.deleted');

  const StorageRealtimeEvent(this.wireValue);

  /// The event name on the wire.
  final String wireValue;

  /// Parses a wire value, returning `null` for anything unrecognized.
  static StorageRealtimeEvent? fromWire(String? value) {
    for (final event in values) {
      if (event.wireValue == value) return event;
    }
    return null;
  }
}

/// Every event a webhook may subscribe to — a superset of
/// [StorageRealtimeEvent].
enum StorageWebhookEvent {
  /// A file finished uploading.
  fileUploaded('file.uploaded'),

  /// A file was deleted.
  fileDeleted('file.deleted'),

  /// A file's metadata changed.
  fileUpdated('file.updated'),

  /// A bucket was created.
  bucketCreated('bucket.created'),

  /// A bucket was deleted.
  bucketDeleted('bucket.deleted');

  const StorageWebhookEvent(this.wireValue);

  /// The event name on the wire.
  final String wireValue;

  /// Parses a wire value, returning `null` for anything unrecognized.
  static StorageWebhookEvent? fromWire(String? value) {
    for (final event in values) {
      if (event.wireValue == value) return event;
    }
    return null;
  }
}

/// A storage bucket.
///
/// [quotaBytes] is `null` and [isUnlimited] is `true` for a bucket with no
/// storage cap. Branch on [isUnlimited], never on [quotaBytes] being falsy,
/// when deciding how to render capacity — a limited bucket with a zero quota
/// and an unlimited bucket are different things.
@immutable
class StorageBucket {
  /// Creates a bucket.
  const StorageBucket({
    required this.id,
    required this.projectId,
    required this.name,
    required this.visibility,
    required this.maxFileSize,
    required this.allowedTypes,
    required this.isUnlimited,
    required this.usedBytes,
    required this.usedPercent,
    required this.fileCount,
    required this.provider,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.quotaBytes,
    this.retentionDays,
  });

  /// Decodes a bucket from JSON.
  factory StorageBucket.fromJson(Map<String, dynamic> json) => StorageBucket(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        visibility: StorageVisibility.fromWire(json['visibility'] as String?),
        maxFileSize: (json['max_file_size'] as num?)?.toInt() ?? 0,
        allowedTypes:
            (json['allowed_types'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false),
        isUnlimited: json['is_unlimited'] as bool? ?? false,
        usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
        usedPercent: (json['used_percent'] as num?)?.toDouble() ?? 0,
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
        provider: StorageProviderName.fromWire(json['provider'] as String?),
        isActive: json['is_active'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        description: json['description'] as String?,
        quotaBytes: (json['quota_bytes'] as num?)?.toInt(),
        retentionDays: (json['retention_days'] as num?)?.toInt(),
      );

  /// Unique bucket identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// Bucket name.
  final String name;

  /// Optional description.
  final String? description;

  /// Default visibility for files in this bucket.
  final StorageVisibility visibility;

  /// Largest accepted file, in bytes.
  final int maxFileSize;

  /// Accepted MIME types. Empty means any type is allowed.
  final List<String> allowedTypes;

  /// Storage cap in bytes, or `null` when [isUnlimited].
  final int? quotaBytes;

  /// Whether this bucket has no storage cap.
  final bool isUnlimited;

  /// Bytes currently stored.
  final int usedBytes;

  /// Percentage of [quotaBytes] consumed. Always 0 when [isUnlimited].
  final double usedPercent;

  /// Number of files stored.
  final int fileCount;

  /// Automatic deletion age in days, or `null` to retain indefinitely.
  final int? retentionDays;

  /// The delivery provider serving this bucket.
  final StorageProviderName provider;

  /// Whether the bucket accepts operations.
  final bool isActive;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  @override
  String toString() => 'StorageBucket(id: $id, name: $name, files: $fileCount, '
      'unlimited: $isUnlimited)';
}

/// A stored file.
@immutable
class StorageFile {
  /// Creates a file record.
  const StorageFile({
    required this.id,
    required this.projectId,
    required this.bucketId,
    required this.name,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    required this.provider,
    required this.cdnUrl,
    required this.tags,
    required this.metadata,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
    this.sizeHuman,
    this.checksum,
    this.providerId,
    this.providerUrl,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.durationSecs,
    this.format,
    this.uploadedBy,
  });

  /// Decodes a file from JSON.
  factory StorageFile.fromJson(Map<String, dynamic> json) => StorageFile(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        bucketId: json['bucket_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        mimeType: json['mime_type'] as String? ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        provider: StorageProviderName.fromWire(json['provider'] as String?),
        cdnUrl: json['cdn_url'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
        metadata: json['metadata'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
        isPublic: json['is_public'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        sizeHuman: json['size_human'] as String?,
        checksum: json['checksum'] as String?,
        providerId: json['provider_id'] as String?,
        providerUrl: json['provider_url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        durationSecs: (json['duration_secs'] as num?)?.toDouble(),
        format: json['format'] as String?,
        uploadedBy: json['uploaded_by'] as String?,
      );

  /// Unique file identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// Containing bucket.
  final String bucketId;

  /// File name.
  final String name;

  /// Path within the bucket.
  final String path;

  /// MIME type.
  final String mimeType;

  /// Size in bytes.
  final int sizeBytes;

  /// Human-readable size, e.g. `2.4 MB`.
  final String? sizeHuman;

  /// Content checksum.
  final String? checksum;

  /// The delivery provider storing this file.
  final StorageProviderName provider;

  /// The provider's own identifier for this file.
  final String? providerId;

  /// The provider's direct URL.
  final String? providerUrl;

  /// The CDN URL to serve this file from. This is the URL to render.
  final String cdnUrl;

  /// Generated thumbnail URL, for images and video.
  final String? thumbnailUrl;

  /// Pixel width, for images and video.
  final int? width;

  /// Pixel height, for images and video.
  final int? height;

  /// Duration in seconds, for audio and video.
  final double? durationSecs;

  /// Container or codec format.
  final String? format;

  /// Free-form tags.
  final List<String> tags;

  /// Arbitrary developer-supplied metadata.
  final Map<String, dynamic> metadata;

  /// Whether the file is publicly readable.
  final bool isPublic;

  /// User who uploaded the file, if recorded.
  final String? uploadedBy;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  @override
  String toString() =>
      'StorageFile(id: $id, name: $name, size: ${sizeHuman ?? sizeBytes})';
}

/// A chunked upload session, for files over 100 MB.
@immutable
class UploadSession {
  /// Creates an upload session.
  const UploadSession({
    required this.id,
    required this.projectId,
    required this.bucketId,
    required this.fileName,
    required this.mimeType,
    required this.totalSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.uploadedChunks,
    required this.receivedBytes,
    required this.progress,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.fileId,
  });

  /// Decodes a session from JSON.
  factory UploadSession.fromJson(Map<String, dynamic> json) => UploadSession(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        bucketId: json['bucket_id'] as String? ?? '',
        fileName: json['file_name'] as String? ?? '',
        mimeType: json['mime_type'] as String? ?? '',
        totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
        chunkSize: (json['chunk_size'] as num?)?.toInt() ?? 0,
        totalChunks: (json['total_chunks'] as num?)?.toInt() ?? 0,
        uploadedChunks: (json['uploaded_chunks'] as num?)?.toInt() ?? 0,
        receivedBytes: (json['received_bytes'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        status: UploadSessionStatus.fromWire(json['status'] as String?),
        expiresAt: json['expires_at'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        fileId: json['file_id'] as String?,
      );

  /// Session identifier, used to poll status.
  final String id;

  /// Owning project.
  final String projectId;

  /// Destination bucket.
  final String bucketId;

  /// Name the assembled file will take.
  final String fileName;

  /// MIME type of the assembled file.
  final String mimeType;

  /// Total bytes expected.
  final int totalSize;

  /// Bytes per chunk.
  final int chunkSize;

  /// Number of chunks expected.
  final int totalChunks;

  /// Number of chunks received so far.
  final int uploadedChunks;

  /// Bytes received so far.
  final int receivedBytes;

  /// Completion fraction, 0.0 to 1.0.
  final double progress;

  /// Current lifecycle state.
  final UploadSessionStatus status;

  /// The assembled file's ID, populated once [status] is
  /// [UploadSessionStatus.complete].
  final String? fileId;

  /// ISO-8601 expiry timestamp.
  final String expiresAt;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  @override
  String toString() =>
      'UploadSession(id: $id, ${(progress * 100).toStringAsFixed(0)}%, '
      '${status.wireValue})';
}

/// The payload of `GET /v1/storage/buckets/:bucketId/files`.
@immutable
class ListFilesResult {
  /// Creates a file-list result.
  const ListFilesResult({
    required this.files,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// Decodes a file-list result from JSON.
  factory ListFilesResult.fromJson(Map<String, dynamic> json) =>
      ListFilesResult(
        files: (json['files'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StorageFile.fromJson)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
        offset: (json['offset'] as num?)?.toInt() ?? 0,
      );

  /// The files on this page.
  final List<StorageFile> files;

  /// Total files in the bucket.
  final int total;

  /// Page size used.
  final int limit;

  /// Offset used.
  final int offset;

  @override
  String toString() => 'ListFilesResult(files: ${files.length}, total: $total)';
}

/// A generic confirmation payload for mutations that do not return the
/// mutated resource.
@immutable
class StorageActionResult {
  /// Creates an action result.
  const StorageActionResult({required this.success, this.message});

  /// Decodes an action result from JSON.
  factory StorageActionResult.fromJson(Map<String, dynamic>? json) =>
      StorageActionResult(
        success: json?['success'] as bool? ?? true,
        message: json?['message'] as String?,
      );

  /// Whether the operation succeeded.
  final bool success;

  /// Optional server message.
  final String? message;

  @override
  String toString() => 'StorageActionResult(success: $success)';
}

// ── Reference-only models (Admin API — no SDK method returns these) ───────

/// Cloudinary's provider configuration shape.
///
/// Unsigned-upload only: no `api_key`/`api_secret` is ever stored or sent.
@immutable
class CloudinaryConfig {
  /// Creates a Cloudinary configuration.
  const CloudinaryConfig({required this.cloudName, required this.uploadPreset});

  /// Decodes a configuration from JSON.
  factory CloudinaryConfig.fromJson(Map<String, dynamic> json) =>
      CloudinaryConfig(
        cloudName: json['cloud_name'] as String? ?? '',
        uploadPreset: json['upload_preset'] as String? ?? '',
      );

  /// The Cloudinary cloud name.
  final String cloudName;

  /// The unsigned upload preset.
  final String uploadPreset;

  /// Encodes this configuration to JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'cloud_name': cloudName,
        'upload_preset': uploadPreset,
      };
}

/// A per-file signed URL access token.
///
/// Managed exclusively through the Admin Dashboard API; no SDK method returns
/// one. Declared so a type is available for tokens obtained through another
/// channel.
@immutable
class StorageSignedToken {
  /// Creates a signed token.
  const StorageSignedToken({
    required this.id,
    required this.fileId,
    required this.token,
    required this.signedUrl,
    required this.downloadCount,
    required this.ipWhitelist,
    required this.expiresAt,
    required this.isRevoked,
    required this.createdAt,
    this.maxDownloads,
  });

  /// Decodes a signed token from JSON.
  factory StorageSignedToken.fromJson(Map<String, dynamic> json) =>
      StorageSignedToken(
        id: json['id'] as String? ?? '',
        fileId: json['file_id'] as String? ?? '',
        token: json['token'] as String? ?? '',
        signedUrl: json['signed_url'] as String? ?? '',
        downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
        ipWhitelist:
            (json['ip_whitelist'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false),
        expiresAt: json['expires_at'] as String? ?? '',
        isRevoked: json['is_revoked'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        maxDownloads: (json['max_downloads'] as num?)?.toInt(),
      );

  /// Token identifier.
  final String id;

  /// The file this token grants access to.
  final String fileId;

  /// The opaque token value.
  final String token;

  /// The full signed URL.
  final String signedUrl;

  /// Maximum permitted downloads, or `null` for unlimited.
  final int? maxDownloads;

  /// Downloads consumed so far.
  final int downloadCount;

  /// IP addresses permitted to use this token. Empty means any.
  final List<String> ipWhitelist;

  /// ISO-8601 expiry timestamp.
  final String expiresAt;

  /// Whether the token has been revoked.
  final bool isRevoked;

  /// ISO-8601 creation timestamp.
  final String createdAt;
}

/// A project's storage provider configuration.
///
/// Reading and writing this is Admin-Dashboard-only; no SDK method returns one.
@immutable
class StorageProviderConfig {
  /// Creates a provider configuration.
  const StorageProviderConfig({
    required this.id,
    required this.projectId,
    required this.provider,
    required this.isEnabled,
    required this.isDefault,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Decodes a provider configuration from JSON.
  factory StorageProviderConfig.fromJson(Map<String, dynamic> json) =>
      StorageProviderConfig(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        provider: StorageProviderName.fromWire(json['provider'] as String?),
        isEnabled: json['is_enabled'] as bool? ?? false,
        isDefault: json['is_default'] as bool? ?? false,
        config: json['config'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );

  /// Configuration identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// Which provider this configures.
  final StorageProviderName provider;

  /// Whether the provider is enabled.
  final bool isEnabled;

  /// Whether this is the project's default provider.
  final bool isDefault;

  /// Provider-specific settings. For Cloudinary, parse with
  /// [CloudinaryConfig.fromJson].
  final Map<String, dynamic> config;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;
}

/// One day's storage usage.
@immutable
class StorageDailyUsage {
  /// Creates a daily usage entry.
  const StorageDailyUsage({
    required this.date,
    required this.uploadsCount,
    required this.deletesCount,
    required this.bytesUploaded,
    required this.bytesDeleted,
    required this.bandwidthBytes,
    required this.transformations,
  });

  /// Decodes a daily usage entry from JSON.
  factory StorageDailyUsage.fromJson(Map<String, dynamic> json) =>
      StorageDailyUsage(
        date: json['date'] as String? ?? '',
        uploadsCount: (json['uploads_count'] as num?)?.toInt() ?? 0,
        deletesCount: (json['deletes_count'] as num?)?.toInt() ?? 0,
        bytesUploaded: (json['bytes_uploaded'] as num?)?.toInt() ?? 0,
        bytesDeleted: (json['bytes_deleted'] as num?)?.toInt() ?? 0,
        bandwidthBytes: (json['bandwidth_bytes'] as num?)?.toInt() ?? 0,
        transformations: (json['transformations'] as num?)?.toInt() ?? 0,
      );

  /// The day, as `YYYY-MM-DD`.
  final String date;

  /// Uploads performed.
  final int uploadsCount;

  /// Deletions performed.
  final int deletesCount;

  /// Bytes uploaded.
  final int bytesUploaded;

  /// Bytes freed by deletion.
  final int bytesDeleted;

  /// Bandwidth served.
  final int bandwidthBytes;

  /// Media transformations performed.
  final int transformations;
}

/// Aggregated storage usage statistics.
///
/// `GET /usage` is Admin-Dashboard-only; no SDK method returns this.
@immutable
class StorageUsage {
  /// Creates a usage summary.
  const StorageUsage({
    required this.totalFiles,
    required this.totalBytes,
    required this.totalBuckets,
    required this.totalBandwidth,
    required this.uploadsToday,
    required this.bytesUploadedToday,
    required this.quotaUsedPercent,
    required this.hasUnlimitedBucket,
    required this.daily,
    this.totalBytesHuman,
  });

  /// Decodes a usage summary from JSON.
  factory StorageUsage.fromJson(Map<String, dynamic> json) => StorageUsage(
        totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
        totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
        totalBuckets: (json['total_buckets'] as num?)?.toInt() ?? 0,
        totalBandwidth: (json['total_bandwidth'] as num?)?.toInt() ?? 0,
        uploadsToday: (json['uploads_today'] as num?)?.toInt() ?? 0,
        bytesUploadedToday:
            (json['bytes_uploaded_today'] as num?)?.toInt() ?? 0,
        quotaUsedPercent: (json['quota_used_percent'] as num?)?.toDouble() ?? 0,
        hasUnlimitedBucket: json['has_unlimited_bucket'] as bool? ?? false,
        daily: (json['daily'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StorageDailyUsage.fromJson)
            .toList(growable: false),
        totalBytesHuman: json['total_bytes_human'] as String?,
      );

  /// Total files stored across every bucket.
  final int totalFiles;

  /// Total bytes stored.
  final int totalBytes;

  /// Human-readable total.
  final String? totalBytesHuman;

  /// Number of buckets.
  final int totalBuckets;

  /// Lifetime bandwidth served.
  final int totalBandwidth;

  /// Uploads performed today.
  final int uploadsToday;

  /// Bytes uploaded today.
  final int bytesUploadedToday;

  /// Percentage of the project quota consumed.
  final double quotaUsedPercent;

  /// Whether any bucket is unlimited, which makes [quotaUsedPercent]
  /// unrepresentative of true capacity.
  final bool hasUnlimitedBucket;

  /// Per-day breakdown.
  final List<StorageDailyUsage> daily;
}

/// An immutable audit log entry.
///
/// `GET /logs` is Admin-Dashboard-only; no SDK method returns this.
@immutable
class StorageActivityLog {
  /// Creates a log entry.
  const StorageActivityLog({
    required this.id,
    required this.projectId,
    required this.actorType,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    required this.status,
    required this.createdAt,
    this.bucketId,
    this.fileId,
    this.actorId,
    this.ipAddress,
    this.errorMessage,
  });

  /// Decodes a log entry from JSON.
  factory StorageActivityLog.fromJson(Map<String, dynamic> json) =>
      StorageActivityLog(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        actorType: StorageActorType.fromWire(json['actor_type'] as String?),
        action: StorageLogAction.fromWire(json['action'] as String?),
        resourceType: json['resource_type'] as String? ?? '',
        resourceId: json['resource_id'] as String? ?? '',
        status: json['status'] as String? ?? 'success',
        createdAt: json['created_at'] as String? ?? '',
        bucketId: json['bucket_id'] as String?,
        fileId: json['file_id'] as String?,
        actorId: json['actor_id'] as String?,
        ipAddress: json['ip_address'] as String?,
        errorMessage: json['error_message'] as String?,
      );

  /// Log entry identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// The bucket involved, if any.
  final String? bucketId;

  /// The file involved, if any.
  final String? fileId;

  /// Who performed the action.
  final StorageActorType actorType;

  /// The actor's identifier, if known.
  final String? actorId;

  /// What was done.
  final StorageLogAction action;

  /// The kind of resource acted on.
  final String resourceType;

  /// The resource's identifier.
  final String resourceId;

  /// Originating IP address.
  final String? ipAddress;

  /// `success` or `failure`.
  final String status;

  /// Failure detail, when [status] is `failure`.
  final String? errorMessage;

  /// ISO-8601 timestamp.
  final String createdAt;
}

/// A registered outbound webhook.
///
/// Managed exclusively through the Admin Dashboard API; no SDK method returns
/// one.
@immutable
class StorageWebhook {
  /// Creates a webhook record.
  const StorageWebhook({
    required this.id,
    required this.projectId,
    required this.name,
    required this.url,
    required this.events,
    required this.isActive,
    required this.failureCount,
    required this.createdAt,
    required this.updatedAt,
    this.lastFiredAt,
    this.lastStatus,
  });

  /// Decodes a webhook from JSON.
  factory StorageWebhook.fromJson(Map<String, dynamic> json) => StorageWebhook(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        events: (json['events'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .map(StorageWebhookEvent.fromWire)
            .whereType<StorageWebhookEvent>()
            .toList(growable: false),
        isActive: json['is_active'] as bool? ?? false,
        failureCount: (json['failure_count'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        lastFiredAt: json['last_fired_at'] as String?,
        lastStatus: json['last_status'] as String?,
      );

  /// Webhook identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// Display name.
  final String name;

  /// Destination URL.
  final String url;

  /// Events this webhook fires on.
  final List<StorageWebhookEvent> events;

  /// Whether the webhook is active.
  final bool isActive;

  /// Consecutive delivery failures.
  final int failureCount;

  /// ISO-8601 timestamp of the last delivery attempt.
  final String? lastFiredAt;

  /// HTTP status of the last delivery attempt.
  final String? lastStatus;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;
}
