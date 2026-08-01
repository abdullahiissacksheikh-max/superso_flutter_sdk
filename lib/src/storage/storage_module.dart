/// The Storage module: buckets, files, uploads, and realtime file events.
///
/// Dart port of `supersosdk/src/storage/{bucket,file,chunked,upload,
/// multipart,validators,storage}.ts`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../realtime/realtime_socket.dart';
import '../types/common.dart';
import '../utils/mime.dart';
import '../utils/url.dart';
import 'storage_errors.dart';
import 'storage_types.dart';

/// Request body for creating a bucket.
///
/// Omit [quotaBytes] (or pass `null`) for an unlimited bucket, which is the
/// default; pass a positive byte count to cap it.
@immutable
class CreateBucketRequest {
  /// Creates a bucket-creation request.
  const CreateBucketRequest({
    required this.name,
    required this.provider,
    this.description,
    this.visibility,
    this.maxFileSize,
    this.allowedTypes,
    this.quotaBytes,
    this.retentionDays,
  });

  /// Bucket name. Required and must be non-empty.
  final String name;

  /// Delivery provider to serve this bucket's files.
  final StorageProviderName provider;

  /// Optional description.
  final String? description;

  /// Default visibility for files in this bucket.
  final StorageVisibility? visibility;

  /// Largest accepted file, in bytes.
  final int? maxFileSize;

  /// Accepted MIME types. Omit to accept any type.
  final List<String>? allowedTypes;

  /// Storage cap in bytes. Omit for an unlimited bucket.
  final int? quotaBytes;

  /// Automatic deletion age, in days.
  final int? retentionDays;

  /// Encodes this request to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'provider': provider.wireValue,
        if (description != null) 'description': description,
        if (visibility != null) 'visibility': visibility!.wireValue,
        if (maxFileSize != null) 'max_file_size': maxFileSize,
        if (allowedTypes != null) 'allowed_types': allowedTypes,
        if (quotaBytes != null) 'quota_bytes': quotaBytes,
        if (retentionDays != null) 'retention_days': retentionDays,
      };
}

/// Request body for updating a bucket. Every field is optional.
///
/// Omitting [quotaBytes] leaves the current limit unchanged. To make a bucket
/// unlimited, pass [makeUnlimited] — this is distinct from omitting the field,
/// which is why a plain nullable `int?` is not enough to express both cases.
@immutable
class UpdateBucketRequest {
  /// Creates a bucket-update request.
  const UpdateBucketRequest({
    this.name,
    this.description,
    this.visibility,
    this.maxFileSize,
    this.allowedTypes,
    this.quotaBytes,
    this.makeUnlimited = false,
    this.retentionDays,
    this.provider,
    this.isActive,
  });

  /// New bucket name.
  final String? name;

  /// New description.
  final String? description;

  /// New default visibility.
  final StorageVisibility? visibility;

  /// New maximum file size, in bytes.
  final int? maxFileSize;

  /// New accepted MIME types.
  final List<String>? allowedTypes;

  /// New storage cap, in bytes. Ignored when [makeUnlimited] is true.
  final int? quotaBytes;

  /// Removes the bucket's storage cap, making it unlimited.
  final bool makeUnlimited;

  /// New automatic deletion age, in days.
  final int? retentionDays;

  /// New delivery provider.
  final StorageProviderName? provider;

  /// Whether the bucket accepts operations.
  final bool? isActive;

  /// Encodes this request to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (visibility != null) 'visibility': visibility!.wireValue,
        if (maxFileSize != null) 'max_file_size': maxFileSize,
        if (allowedTypes != null) 'allowed_types': allowedTypes,
        if (makeUnlimited) 'quota_bytes': null,
        if (!makeUnlimited && quotaBytes != null) 'quota_bytes': quotaBytes,
        if (retentionDays != null) 'retention_days': retentionDays,
        if (provider != null) 'provider': provider!.wireValue,
        if (isActive != null) 'is_active': isActive,
      };
}

/// Options accepted by [FileModule.upload].
///
/// The SDK builds the multipart body — you never construct it yourself.
@immutable
class UploadFileOptions {
  /// Creates upload options.
  const UploadFileOptions({
    required this.bucketId,
    this.path,
    this.visibility,
    this.metadata,
    this.tags,
  });

  /// Destination bucket.
  final String bucketId;

  /// Path within the bucket.
  final String? path;

  /// Visibility for this file, overriding the bucket default.
  final StorageVisibility? visibility;

  /// Arbitrary metadata to attach.
  final Map<String, dynamic>? metadata;

  /// Free-form tags.
  final List<String>? tags;

  /// Encodes these options as multipart form fields.
  Map<String, String> toFields() => <String, String>{
        'bucket_id': bucketId,
        if (path != null) 'path': path!,
        if (visibility != null) 'visibility': visibility!.wireValue,
        if (metadata != null) 'metadata': jsonEncode(metadata),
        if (tags != null) 'tags': jsonEncode(tags),
      };
}

/// Bucket management (`docs/storage.md` — Buckets).
///
/// Exposed at `superso.storage.bucket`.
class BucketModule {
  /// Creates a bucket module bound to [client].
  const BucketModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/storage/buckets` — creates a bucket. Requires `write` scope.
  ///
  /// Throws a [ValidationError] if the name is empty, without a round trip.
  Future<ApiResponse<StorageBucket>> create(CreateBucketRequest request) {
    if (request.name.trim().isEmpty) {
      throw const ValidationError(
        'Superso: a bucket name is required and cannot be empty.',
      );
    }
    return withStorageErrors(
      () => _client.post<StorageBucket>(
        '/storage/buckets',
        body: request.toJson(),
        decoder: _bucket,
      ),
      bucketError,
    );
  }

  /// `GET /v1/storage/buckets` — lists active buckets. Requires `read` scope.
  Future<ApiResponse<List<StorageBucket>>> list() {
    return withStorageErrors(
      () => _client.get<List<StorageBucket>>(
        '/storage/buckets',
        decoder: (data) => (data as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StorageBucket.fromJson)
            .toList(growable: false),
      ),
      bucketError,
    );
  }

  /// `GET /v1/storage/buckets/:bucketId`. Requires `read` scope.
  Future<ApiResponse<StorageBucket>> get(String bucketId) {
    return withStorageErrors(
      () => _client.get<StorageBucket>(
        '/storage/buckets/${encodeSegment(bucketId)}',
        decoder: _bucket,
      ),
      bucketError,
    );
  }

  /// `PATCH /v1/storage/buckets/:bucketId`. Requires `write` scope.
  Future<ApiResponse<StorageBucket>> update(
    String bucketId,
    UpdateBucketRequest request,
  ) {
    return withStorageErrors(
      () => _client.patch<StorageBucket>(
        '/storage/buckets/${encodeSegment(bucketId)}',
        body: request.toJson(),
        decoder: _bucket,
      ),
      bucketError,
    );
  }

  /// `DELETE /v1/storage/buckets/:bucketId`. Requires `delete` scope.
  Future<ApiResponse<StorageActionResult>> delete(String bucketId) {
    return withStorageErrors(
      () => _client.delete<StorageActionResult>(
        '/storage/buckets/${encodeSegment(bucketId)}',
        decoder: (data) =>
            StorageActionResult.fromJson(data as Map<String, dynamic>?),
      ),
      bucketError,
    );
  }

  static StorageBucket _bucket(Object? data) =>
      StorageBucket.fromJson(data as Map<String, dynamic>? ?? const {});
}

/// File operations (`docs/storage.md` — Files).
///
/// Exposed at `superso.storage.file`.
///
/// There is deliberately no `update` method: `PATCH /files/:fileId` exists
/// only under the Admin Dashboard API. The SDK route table has no
/// `X-API-Key` equivalent, so shipping the method would ship a guaranteed 404.
class FileModule {
  /// Creates a file module bound to [client].
  const FileModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/storage/files/upload` — uploads [bytes] as a multipart request.
  /// Requires `write` scope.
  ///
  /// Every multipart detail — boundary generation, the `Content-Type` header,
  /// field encoding — is handled for you.
  ///
  /// ```dart
  /// final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  /// final result = await superso.storage.file.upload(
  ///   bytes: await picked!.readAsBytes(),
  ///   filename: picked.name,
  ///   options: UploadFileOptions(bucketId: bucketId, tags: ['avatar']),
  /// );
  /// print(result.data.cdnUrl);
  /// ```
  ///
  /// [contentType] should be a MIME type such as `image/jpeg`. When omitted it
  /// is inferred from [filename]'s extension, falling back to
  /// `application/octet-stream`.
  ///
  /// Unlike the JavaScript SDK — which accepts a browser `File`, `Blob`, or
  /// `Buffer` and detects the runtime — this takes raw [bytes] plus an
  /// explicit [filename]. Dart has no single cross-platform file type
  /// (`dart:io`'s `File` does not exist on Web), so bytes are the one
  /// representation that works identically on mobile, desktop, and Web. Read
  /// them with `File.readAsBytes()`, `XFile.readAsBytes()`, or
  /// `PlatformFile.bytes` depending on your picker.
  Future<ApiResponse<StorageFile>> upload({
    required Uint8List bytes,
    required String filename,
    required UploadFileOptions options,
    String? contentType,
  }) {
    if (filename.trim().isEmpty) {
      throw const ValidationError(
        'Superso: a filename is required to upload a file.',
      );
    }
    if (bytes.isEmpty) {
      throw const ValidationError('Superso: cannot upload an empty file.');
    }

    final file = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: parseMediaType(contentType ?? inferMimeType(filename)),
    );

    return withStorageErrors(
      () => _client.postMultipart<StorageFile>(
        '/storage/files/upload',
        files: <http.MultipartFile>[file],
        fields: options.toFields(),
        decoder: _file,
      ),
      uploadError,
    );
  }

  /// `GET /v1/storage/buckets/:bucketId/files` — paginated list. Requires
  /// `read` scope.
  Future<ApiResponse<ListFilesResult>> list(
    String bucketId, {
    int? limit,
    int? offset,
  }) {
    return withStorageErrors(
      () => _client.get<ListFilesResult>(
        '/storage/buckets/${encodeSegment(bucketId)}/files',
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => ListFilesResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
      uploadError,
    );
  }

  /// `GET /v1/storage/files/:fileId`. Requires `read` scope.
  Future<ApiResponse<StorageFile>> get(String fileId) {
    return withStorageErrors(
      () => _client.get<StorageFile>(
        '/storage/files/${encodeSegment(fileId)}',
        decoder: _file,
      ),
      uploadError,
    );
  }

  /// `DELETE /v1/storage/files/:fileId`. Requires `write` scope.
  ///
  /// Removes the file from both the provider and the database, and broadcasts
  /// a `file.deleted` realtime event.
  Future<ApiResponse<StorageActionResult>> delete(String fileId) {
    return withStorageErrors(
      () => _client.delete<StorageActionResult>(
        '/storage/files/${encodeSegment(fileId)}',
        decoder: (data) =>
            StorageActionResult.fromJson(data as Map<String, dynamic>?),
      ),
      uploadError,
    );
  }

  /// Downloads a file's bytes from its CDN URL.
  ///
  /// No JavaScript counterpart — the browser SDK simply hands `cdnUrl` to an
  /// `<img>` tag or `fetch`. A Flutter app frequently needs the raw bytes
  /// (to cache them, write them to disk, or feed `Image.memory`), so this
  /// convenience is offered. It issues a plain GET against [StorageFile.cdnUrl]
  /// with no Superso headers attached, since a CDN URL is already
  /// self-authenticating.
  Future<Uint8List> download(StorageFile file) async {
    try {
      final response = await http.get(Uri.parse(file.cdnUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UploadError(
          'Download failed with HTTP ${response.statusCode}.',
          response.statusCode,
        );
      }
      return response.bodyBytes;
    } on StorageError {
      rethrow;
    } on Object catch (error) {
      throw NetworkError('Failed to download ${file.name}: $error', error);
    }
  }

  static StorageFile _file(Object? data) =>
      StorageFile.fromJson(data as Map<String, dynamic>? ?? const {});
}

/// Chunked/resumable upload sessions, for files over 100 MB.
///
/// Exposed at `superso.storage.uploads`.
///
/// Only session initiation and status polling are implemented, because
/// `POST /v1/storage/uploads` and `GET /v1/storage/uploads/:uploadId` are the
/// only two chunked-upload routes registered under the SDK API. Per-chunk
/// transport, resume, and cancel are not documented anywhere — not even under
/// the Admin API — so no methods are exposed for them rather than fabricating
/// an undocumented contract.
class ChunkedUploadModule {
  /// Creates a chunked-upload module bound to [client].
  const ChunkedUploadModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/storage/uploads` — initiates a session. Requires `write` scope.
  ///
  /// Throws a [ValidationError] for a non-positive [totalSize] or [chunkSize].
  Future<ApiResponse<UploadSession>> create({
    required String bucketId,
    required String fileName,
    required String mimeType,
    required int totalSize,
    required int chunkSize,
  }) {
    if (totalSize <= 0) {
      throw const ValidationError('Superso: totalSize must be positive.');
    }
    if (chunkSize <= 0) {
      throw const ValidationError('Superso: chunkSize must be positive.');
    }
    return withStorageErrors(
      () => _client.post<UploadSession>(
        '/storage/uploads',
        body: <String, dynamic>{
          'bucket_id': bucketId,
          'file_name': fileName,
          'mime_type': mimeType,
          'total_size': totalSize,
          'chunk_size': chunkSize,
        },
        decoder: _session,
      ),
      uploadError,
    );
  }

  /// `GET /v1/storage/uploads/:uploadId` — polls session status. Requires
  /// `read` scope.
  Future<ApiResponse<UploadSession>> status(String uploadId) {
    return withStorageErrors(
      () => _client.get<UploadSession>(
        '/storage/uploads/${encodeSegment(uploadId)}',
        decoder: _session,
      ),
      uploadError,
    );
  }

  /// Polls [status] until the session reaches a terminal state.
  ///
  /// Emits every observed [UploadSession], so a progress bar can bind straight
  /// to the stream. Completes when the session is complete, failed, or
  /// expired. No JavaScript counterpart — the JS SDK leaves polling to the
  /// caller — but a `Stream` is the natural Dart shape for this.
  Stream<UploadSession> watch(
    String uploadId, {
    Duration interval = const Duration(seconds: 2),
  }) async* {
    while (true) {
      final response = await status(uploadId);
      final session = response.data;
      yield session;
      if (session.status == UploadSessionStatus.complete ||
          session.status == UploadSessionStatus.failed ||
          session.status == UploadSessionStatus.expired) {
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  static UploadSession _session(Object? data) =>
      UploadSession.fromJson(data as Map<String, dynamic>? ?? const {});
}

/// A parsed frame received on the `storage` realtime channel.
@immutable
class StorageRealtimeMessage {
  /// Creates a realtime message.
  const StorageRealtimeMessage({required this.event, required this.file});

  /// Which event occurred.
  final StorageRealtimeEvent event;

  /// The file the event concerns.
  final StorageFile file;

  @override
  String toString() =>
      'StorageRealtimeMessage(${event.wireValue}, ${file.name})';
}

/// The composition root for every `X-API-Key`-authenticated Storage endpoint.
///
/// ```dart
/// final bucket = await superso.storage.bucket.create(
///   const CreateBucketRequest(
///     name: 'avatars',
///     provider: StorageProviderName.cloudinary,
///   ),
/// );
///
/// final uploaded = await superso.storage.file.upload(
///   bytes: bytes,
///   filename: 'photo.jpg',
///   options: UploadFileOptions(bucketId: bucket.data.id),
/// );
///
/// superso.storage.onUploaded.listen((file) => print('new: ${file.cdnUrl}'));
/// ```
///
/// **Scope note.** `file.update`, signed URL tokens, provider configuration,
/// usage, activity logs, and webhooks are not exposed. Those are documented
/// only under the Admin Dashboard API, which uses a different authentication
/// model. See `storage_types.dart` for their data shapes, kept for typing.
class StorageModule implements SdkModule, Disposable {
  /// Creates the storage module bound to [client].
  StorageModule(this.client)
      : bucket = BucketModule(client),
        file = FileModule(client),
        uploads = ChunkedUploadModule(client),
        _socket = RealtimeSocket(client, channel: 'storage');

  @override
  final SupersoHttpClient client;

  /// Bucket management.
  final BucketModule bucket;

  /// File operations.
  final FileModule file;

  /// Chunked upload sessions.
  final ChunkedUploadModule uploads;

  final RealtimeSocket _socket;

  /// Every event on the `storage` channel, regardless of type.
  ///
  /// The connection opens lazily on first listen and is shared by every
  /// stream below. This replaces the JavaScript SDK's
  /// `subscribe(handler) => unsubscribe` callback pattern — in Dart a
  /// `StreamSubscription` already provides cancellation, so a bespoke
  /// unsubscribe function would be redundant.
  Stream<StorageRealtimeMessage> get events =>
      _socket.messages.map(_parse).where((m) => m != null).cast();

  /// Files that finished uploading.
  Stream<StorageFile> get onUploaded => events
      .where((m) => m.event == StorageRealtimeEvent.fileUploaded)
      .map((m) => m.file);

  /// Files that were deleted.
  Stream<StorageFile> get onDeleted => events
      .where((m) => m.event == StorageRealtimeEvent.fileDeleted)
      .map((m) => m.file);

  /// Closes the realtime connection, if one is open.
  Future<void> disconnectRealtime() => _socket.disconnect();

  @override
  Future<void> dispose() => _socket.dispose();

  static StorageRealtimeMessage? _parse(Map<String, dynamic> frame) {
    final event = StorageRealtimeEvent.fromWire(frame['event'] as String?);
    final data = frame['data'];
    if (event == null || data is! Map<String, dynamic>) return null;
    return StorageRealtimeMessage(
      event: event,
      file: StorageFile.fromJson(data),
    );
  }
}
