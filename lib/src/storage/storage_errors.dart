/// Storage-specific error hierarchy, normalized from `docs/storage.md`'s Error
/// Reference and Multipart Upload Requirements.
///
/// Every submodule routes its HTTP calls through [withStorageErrors], so
/// application code only ever sees these types — never a raw transport error
/// or the backend's `{success, message, error}` body.
///
/// [AuthenticationError], [PermissionError], [RateLimitError], and
/// [NetworkError] pass through unchanged from the shared hierarchy, because
/// their meaning is identical regardless of which module raised them.
///
/// Dart port of `supersosdk/src/storage/errors.ts`.
library;

import '../errors/superso_error.dart';

/// Base class for every Storage-domain error.
class StorageError extends SupersoError {
  /// Creates a storage error.
  const StorageError(
    String message, {
    int? status,
    String? code,
    Object? details,
  }) : super(message: message, status: status, code: code, details: details);
}

/// A bucket operation failed — e.g. `BUCKET_NAME_TAKEN`, or the bucket is
/// missing or inactive.
class BucketError extends StorageError {
  /// Creates a bucket error.
  const BucketError([
    String message = 'The bucket operation failed.',
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'BUCKET_ERROR', details: details);
}

/// An upload failed for a reason other than quota or malformed multipart —
/// e.g. `MIME_NOT_ALLOWED`, `FILE_TOO_LARGE`, or a provider-side failure.
class UploadError extends StorageError {
  /// Creates an upload error.
  const UploadError([
    String message = 'The file upload failed.',
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'UPLOAD_ERROR', details: details);
}

/// The bucket's delivery provider is not configured, not enabled, or returned
/// an error (`422 PROVIDER_NOT_CONFIGURED`, `500 PROVIDER_ERROR`).
///
/// Named `StorageProviderError` rather than bare `ProviderError` because the
/// Notification module exports a type by that name.
class StorageProviderError extends StorageError {
  /// Creates a provider error.
  const StorageProviderError([
    String message = 'The storage provider is unavailable.',
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'PROVIDER_ERROR', details: details);
}

/// `413 QUOTA_EXCEEDED` — the upload would push a limited bucket's used bytes
/// past its quota.
class QuotaExceededError extends StorageError {
  /// Creates a quota error.
  const QuotaExceededError([
    String message = 'This upload would exceed the bucket quota.',
    Object? details,
  ]) : super(
          message,
          status: 413,
          code: 'QUOTA_EXCEEDED',
          details: details,
        );
}

/// The multipart request was rejected before any field was read — `415` for a
/// wrong Content-Type, or `400` for a bad or missing boundary.
class MultipartError extends StorageError {
  /// Creates a multipart error.
  const MultipartError([
    String message = 'The multipart upload request was malformed.',
    int? status,
    Object? details,
  ]) : super(
          message,
          status: status,
          code: 'MULTIPART_ERROR',
          details: details,
        );
}

/// Builds a domain-specific [StorageError] from a generic failure.
typedef StorageErrorFactory = StorageError Function(
  String message,
  int? status,
  Object? details,
);

/// Re-throws any error from a Storage HTTP call as the [StorageError] subclass
/// produced by [errorFactory], preserving the status and details the shared
/// client already extracted.
///
/// Two failure modes bypass [errorFactory] because their meaning is
/// unambiguous and independent of which submodule made the call:
/// `413` always becomes [QuotaExceededError], and `415` always becomes
/// [MultipartError]. Authentication, permission, rate-limit, and network
/// errors pass through untouched.
Future<T> withStorageErrors<T>(
  Future<T> Function() operation,
  StorageErrorFactory errorFactory,
) async {
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
    if (error.status == 413) {
      throw QuotaExceededError(error.message, error.details);
    }
    if (error.status == 415) {
      throw MultipartError(error.message, error.status, error.details);
    }
    throw errorFactory(error.message, error.status, error.details);
  } on Object catch (error) {
    throw errorFactory('$error', null, null);
  }
}

/// Factory producing a [BucketError]. Pass to [withStorageErrors].
StorageError bucketError(String message, int? status, Object? details) =>
    BucketError(message, status, details);

/// Factory producing an [UploadError]. Pass to [withStorageErrors].
StorageError uploadError(String message, int? status, Object? details) =>
    UploadError(message, status, details);

/// Factory producing a [StorageProviderError]. Pass to [withStorageErrors].
StorageError providerError(String message, int? status, Object? details) =>
    StorageProviderError(message, status, details);
