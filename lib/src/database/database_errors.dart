/// Database-specific error hierarchy, normalized from `docs/database.md` §18.
///
/// Every Database method routes its HTTP call through [withDatabaseErrors], so
/// there is exactly one place raw HTTP failures are translated into these
/// types — no submodule reimplements this mapping.
///
/// [ValidationError], [RateLimitError], and [NetworkError] are reused as-is
/// from the shared SDK hierarchy rather than duplicated here.
///
/// Dart port of `supersosdk/src/database/errors.ts`.
library;

import '../errors/superso_error.dart';

/// Base class for every Database-domain error.
///
/// Carries the documented machine-readable `error.code` in [SupersoError.code].
class DatabaseError extends SupersoError {
  /// Creates a database error.
  const DatabaseError(
    String message, {
    String? errorCode,
    int? status,
    Object? details,
  }) : super(
          message: message,
          status: status,
          code: errorCode,
          details: details,
        );
}

/// `404 COLLECTION_NOT_FOUND` — the target collection does not exist.
class CollectionNotFoundError extends DatabaseError {
  /// Creates the error.
  const CollectionNotFoundError([
    String message = 'Collection not found.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'COLLECTION_NOT_FOUND',
          status: 404,
          details: details,
        );
}

/// `404 DOCUMENT_NOT_FOUND` — the document does not exist or was soft-deleted.
///
/// A very common cause is passing a document's internal `id` where its
/// `doc_id` was required — see the `DatabaseDocument` class documentation.
class DocumentNotFoundError extends DatabaseError {
  /// Creates the error.
  const DocumentNotFoundError([
    String message = 'Document not found.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'DOCUMENT_NOT_FOUND',
          status: 404,
          details: details,
        );
}

/// `403 ACCESS_DENIED` / `403 FORBIDDEN` — denied by security rules or by
/// insufficient API-key permission.
class PermissionDeniedError extends DatabaseError {
  /// Creates the error.
  const PermissionDeniedError([
    String message = 'This operation was denied.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'ACCESS_DENIED',
          status: 403,
          details: details,
        );
}

/// `409 TRANSACTION_FAILED` — the transaction rolled back; no operation was
/// persisted.
///
/// Distinct from a `409 DOCUMENT_EXISTS`/`COLLECTION_EXISTS` conflict, which
/// the shared [ConflictError] already covers.
class TransactionFailedError extends DatabaseError {
  /// Creates the error.
  const TransactionFailedError([
    String message = 'Transaction rolled back — no changes were persisted.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'TRANSACTION_FAILED',
          status: 409,
          details: details,
        );
}

/// `400 RESERVED_FIELD_CONFLICT` — the payload contains a top-level key
/// matching a reserved system *identity* field (`id`, `doc_id`, `collection`,
/// `path`, `project_id`, `version`, `size_bytes`, `created_by`, `updated_by`,
/// `is_deleted`).
///
/// Note `created_at`/`updated_at`/`deleted_at` are NOT reserved — they may
/// always be sent inside `data` as client-supplied event timestamps, alongside
/// the server's own top-level metadata of the same name.
class ReservedFieldConflictError extends DatabaseError {
  /// Creates the error.
  const ReservedFieldConflictError([
    String message = 'Payload contains a reserved system field.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'RESERVED_FIELD_CONFLICT',
          status: 400,
          details: details,
        );
}

/// `400 QUERY_PATTERN_INVALID` — a `matchesRegex` or `jsonPath` filter's
/// pattern is malformed.
class QueryPatternInvalidError extends DatabaseError {
  /// Creates the error.
  const QueryPatternInvalidError([
    String message = 'Query pattern is invalid.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'QUERY_PATTERN_INVALID',
          status: 400,
          details: details,
        );
}

/// `400 COLLECTION_LIMIT_REACHED` — the collection reached its configured
/// `max_collection_size`.
class CollectionLimitReachedError extends DatabaseError {
  /// Creates the error.
  const CollectionLimitReachedError([
    String message =
        'Collection has reached its maximum allowed document count.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'COLLECTION_LIMIT_REACHED',
          status: 400,
          details: details,
        );
}

/// `400 INDEX_REQUIRED` — the query filters or sorts on a field with no
/// covering index, and the collection is large enough that a full scan would
/// be slow.
///
/// The message embeds a ready-to-submit index suggestion in the platform's
/// real index-creation JSON shape; parse it out to act on it programmatically.
class IndexRequiredError extends DatabaseError {
  /// Creates the error.
  const IndexRequiredError([
    String message = 'Query requires an index.',
    Object? details,
  ]) : super(
          message,
          errorCode: 'INDEX_REQUIRED',
          status: 400,
          details: details,
        );
}

/// Maps a thrown error into the appropriate Database-specific type.
///
/// Errors thrown by the shared HTTP client are already classified by HTTP
/// status ([ValidationError] for 400/422, [ConflictError] for 409, and so on).
/// This only overrides the cases where the documented `error.code`
/// distinguishes something the status alone cannot: which 404 is a collection
/// versus a document, and which 403 is a permission denial.
SupersoError mapDatabaseError(Object error) {
  if (error is! SupersoError) {
    return DatabaseError(
      error is Exception ? error.toString() : 'Unknown database error.',
    );
  }

  final details = error.details;
  String? code;
  var message = error.message;
  if (details is Map<String, dynamic>) {
    final nested = details['error'];
    if (nested is Map<String, dynamic>) {
      code = nested['code'] as String?;
      message = nested['message'] as String? ?? message;
    } else {
      code = details['code'] as String?;
    }
  }

  switch (code) {
    case 'COLLECTION_NOT_FOUND':
      return CollectionNotFoundError(message, details);
    case 'DOCUMENT_NOT_FOUND':
      return DocumentNotFoundError(message, details);
    case 'ACCESS_DENIED':
    case 'FORBIDDEN':
      return PermissionDeniedError(message, details);
    case 'TRANSACTION_FAILED':
      return TransactionFailedError(message, details);
    case 'RESERVED_FIELD_CONFLICT':
      return ReservedFieldConflictError(message, details);
    case 'QUERY_PATTERN_INVALID':
      return QueryPatternInvalidError(message, details);
    case 'COLLECTION_LIMIT_REACHED':
      return CollectionLimitReachedError(message, details);
    case 'INDEX_REQUIRED':
      return IndexRequiredError(message, details);
    default:
      // Already correctly classified by the shared client.
      return error;
  }
}

/// Wraps a single Database HTTP call, translating any thrown error through
/// [mapDatabaseError].
Future<T> withDatabaseErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on Object catch (error) {
    throw mapDatabaseError(error);
  }
}
