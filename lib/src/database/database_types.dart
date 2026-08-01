/// Request and response models for the Database module, mirrored exactly from
/// `docs/database.md`.
///
/// Names are prefixed with `Database` (matching the `AuthUser`/`AuthSession`
/// convention used by the Auth module) so they never collide with the shared
/// root types or a sibling module's exports.
///
/// Dart port of `supersosdk/src/database/types.ts`.
library;

import 'package:meta/meta.dart';

import 'database_filters.dart';

/// Maximum operations accepted by a single `POST /database/batch` request.
const int maxBatchOperations = 500;

/// The sentinel that stamps a field with the server's current UTC time.
const String serverTimestampSentinel = '__server_timestamp__';

/// A collection of documents.
@immutable
class DatabaseCollection {
  /// Creates a collection.
  const DatabaseCollection({
    required this.id,
    required this.path,
    required this.name,
    required this.documentCount,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.parentPath,
  });

  /// Decodes a collection from JSON.
  factory DatabaseCollection.fromJson(Map<String, dynamic> json) =>
      DatabaseCollection(
        id: json['id'] as String? ?? '',
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '',
        documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        parentPath: json['parent_path'] as String?,
      );

  /// Internal identifier.
  final String id;

  /// Full collection path, e.g. `users` or `orgs/acme/members`.
  final String path;

  /// Display name.
  final String name;

  /// Number of documents currently stored.
  final int documentCount;

  /// Total size on disk, in bytes.
  final int sizeBytes;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  /// Parent collection path, or `null` for a top-level collection.
  final String? parentPath;

  @override
  String toString() =>
      'DatabaseCollection(path: $path, documents: $documentCount)';
}

/// A stored document.
///
/// [T] is the shape of the developer-defined [data] field.
///
/// IMPORTANT — [id] and [docId] are two different values that can both look
/// like UUIDs when the project's `default_id_type` setting is `uuid` (the
/// default), which makes them easy to mix up:
///
/// - [docId] is the developer-facing document identifier. It is the ONLY valid
///   identifier for `get`, `set`, `update`, `patch`, `delete`, and `restore` —
///   every one of those resolves the document by `collection + "/" + docId`
///   server-side.
/// - [id] is the internal database row UUID. It is returned for reference
///   (e.g. matching a `database.document.*` realtime event back to a locally
///   cached document), but passing it where [docId] is expected reliably fails
///   with `DocumentNotFoundError` — the backend has no lookup path keyed on
///   [id] at all.
///
/// Always read [docId] — never [id] — when performing a follow-up operation on
/// a document you just created, fetched, or received from a realtime event.
@immutable
class DatabaseDocument<T> {
  /// Creates a document.
  const DatabaseDocument({
    required this.id,
    required this.docId,
    required this.collection,
    required this.path,
    required this.data,
    required this.version,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Decodes a document, mapping `data` through [fromData].
  factory DatabaseDocument.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> data) fromData,
  ) =>
      DatabaseDocument<T>(
        id: json['id'] as String? ?? '',
        docId: json['doc_id'] as String? ?? '',
        collection: json['collection'] as String? ?? '',
        path: json['path'] as String? ?? '',
        data: fromData(
          json['data'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
        version: (json['version'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        createdBy: json['created_by'] as String?,
        updatedBy: json['updated_by'] as String?,
      );

  /// Internal database row UUID. Not a valid lookup key — see the class docs.
  final String id;

  /// The developer-facing document identifier. Use this for every operation.
  final String docId;

  /// The collection path this document belongs to.
  final String collection;

  /// Full document path, `collection/docId`.
  final String path;

  /// The developer-defined payload.
  final T data;

  /// Monotonically increasing version, bumped on every write.
  final int version;

  /// Serialized size in bytes.
  final int sizeBytes;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  /// User ID that created this document, if recorded.
  final String? createdBy;

  /// User ID that last updated this document, if recorded.
  final String? updatedBy;

  @override
  String toString() =>
      'DatabaseDocument(docId: $docId, collection: $collection, v$version)';
}

/// A page of results, normalized from the raw
/// `{documents, total, has_more, next_cursor}` wire shape.
@immutable
class DatabasePage<T> {
  /// Creates a page.
  const DatabasePage({
    required this.items,
    required this.total,
    required this.hasMore,
    this.nextCursor,
    this.explain,
  });

  /// The items on this page.
  final List<T> items;

  /// Total matching documents across all pages.
  final int total;

  /// Whether more pages remain.
  final bool hasMore;

  /// Opaque cursor for the next page, or `null` when [hasMore] is false.
  final String? nextCursor;

  /// Query-plan diagnostics, present only when the query set `explain: true`.
  final DatabaseQueryExplain? explain;

  @override
  String toString() =>
      'DatabasePage(items: ${items.length}, total: $total, hasMore: $hasMore)';
}

/// Real Postgres query-plan diagnostics for a single query execution.
///
/// Every field except [recommendedIndex] and [warnings] comes directly off
/// Postgres's own `EXPLAIN (ANALYZE, FORMAT JSON)` output — never fabricated
/// or estimated client-side. Those two the backend derives by correlating the
/// plan against the index catalog.
@immutable
class DatabaseQueryExplain {
  /// Creates explain diagnostics.
  const DatabaseQueryExplain({
    required this.scanType,
    required this.estimatedCost,
    required this.documentsScanned,
    required this.documentsReturned,
    required this.planningMs,
    required this.executionMs,
    required this.rawPlan,
    this.indexUsed,
    this.recommendedIndex,
    this.warnings = const <String>[],
  });

  /// Decodes explain diagnostics from JSON.
  factory DatabaseQueryExplain.fromJson(Map<String, dynamic> json) =>
      DatabaseQueryExplain(
        scanType: json['scan_type'] as String? ?? '',
        estimatedCost: (json['estimated_cost'] as num?)?.toDouble() ?? 0,
        documentsScanned: (json['documents_scanned'] as num?)?.toInt() ?? 0,
        documentsReturned: (json['documents_returned'] as num?)?.toInt() ?? 0,
        planningMs: (json['planning_ms'] as num?)?.toDouble() ?? 0,
        executionMs: (json['execution_ms'] as num?)?.toDouble() ?? 0,
        rawPlan: json['raw_plan'] as String? ?? '',
        indexUsed: json['index_used'] as String?,
        recommendedIndex: json['recommended_index'] as String?,
        warnings: (json['warnings'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
      );

  /// Postgres plan node type, e.g. `Seq Scan`, `Index Scan`.
  final String scanType;

  /// Planner's estimated cost.
  final double estimatedCost;

  /// Rows the executor actually examined.
  final int documentsScanned;

  /// Rows returned to the caller.
  final int documentsReturned;

  /// Time spent planning, in milliseconds.
  final double planningMs;

  /// Time spent executing, in milliseconds.
  final double executionMs;

  /// Full `EXPLAIN (ANALYZE, FORMAT JSON)` output, verbatim.
  final String rawPlan;

  /// Index the planner actually used, if any.
  final String? indexUsed;

  /// Ready-to-submit index-creation JSON body, present only when the plan
  /// shows a sequential scan on a field with no covering index.
  final String? recommendedIndex;

  /// Advisory warnings derived from the plan.
  final List<String> warnings;

  @override
  String toString() =>
      'DatabaseQueryExplain(scanType: $scanType, executionMs: $executionMs)';
}

/// The `POST /database/count` response.
@immutable
class DatabaseCountResult {
  /// Creates a count result.
  const DatabaseCountResult({
    required this.count,
    required this.total,
    required this.collection,
    required this.executionMs,
  });

  /// Decodes a count result from JSON.
  factory DatabaseCountResult.fromJson(Map<String, dynamic> json) =>
      DatabaseCountResult(
        count: (json['count'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        collection: json['collection'] as String? ?? '',
        executionMs: (json['execution_ms'] as num?)?.toDouble() ?? 0,
      );

  /// Number of documents matching the filters.
  final int count;

  /// Total documents in the collection.
  final int total;

  /// The collection that was counted.
  final String collection;

  /// Server-side execution time, in milliseconds.
  final double executionMs;

  @override
  String toString() => 'DatabaseCountResult(count: $count, total: $total)';
}

/// The `POST /database/exists` query-based existence response.
///
/// Distinct from `documents.exists()`, which covers a specific `docId` lookup
/// and returns a plain `bool`; this shape matches what the backend sends when
/// a `where` clause drives the check.
@immutable
class DatabaseExistsResult {
  /// Creates an exists result.
  const DatabaseExistsResult({
    required this.exists,
    required this.collection,
    this.executionMs,
  });

  /// Decodes an exists result from JSON.
  factory DatabaseExistsResult.fromJson(Map<String, dynamic> json) =>
      DatabaseExistsResult(
        exists: json['exists'] as bool? ?? false,
        collection: json['collection'] as String? ?? '',
        executionMs: (json['execution_ms'] as num?)?.toDouble(),
      );

  /// Whether at least one matching document exists.
  final bool exists;

  /// The collection that was checked.
  final String collection;

  /// Server-side execution time, in milliseconds.
  final double? executionMs;

  @override
  String toString() => 'DatabaseExistsResult(exists: $exists)';
}

/// The `POST /database/batch` response.
@immutable
class DatabaseBatchResult {
  /// Creates a batch result.
  const DatabaseBatchResult({
    required this.succeeded,
    required this.failed,
    this.errors = const <String>[],
  });

  /// Decodes a batch result from JSON.
  factory DatabaseBatchResult.fromJson(Map<String, dynamic> json) =>
      DatabaseBatchResult(
        succeeded: (json['succeeded'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        errors: (json['errors'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
      );

  /// Operations that succeeded.
  final int succeeded;

  /// Operations that failed.
  final int failed;

  /// Per-operation error messages.
  final List<String> errors;

  @override
  String toString() =>
      'DatabaseBatchResult(succeeded: $succeeded, failed: $failed)';
}

/// The `POST /database/transactions` response.
///
/// Unlike [DatabaseBatchResult] there is no `failed`/`errors` — this endpoint
/// wraps every operation in a single PostgreSQL transaction and rolls back
/// entirely on any failure (returning `409 TRANSACTION_FAILED` rather than a
/// 200), so a completed call always means every operation succeeded.
@immutable
class DatabaseTransactionResult {
  /// Creates a transaction result.
  const DatabaseTransactionResult({required this.succeeded});

  /// Decodes a transaction result from JSON.
  factory DatabaseTransactionResult.fromJson(Map<String, dynamic> json) =>
      DatabaseTransactionResult(
        succeeded: (json['succeeded'] as num?)?.toInt() ?? 0,
      );

  /// Number of operations committed.
  final int succeeded;

  @override
  String toString() => 'DatabaseTransactionResult(succeeded: $succeeded)';
}

/// The kind of write a [DatabaseBatchOperation] performs.
enum DatabaseBatchOperationType {
  /// Create a new document.
  create('create'),

  /// Replace a document's data wholesale.
  update('update'),

  /// Merge fields into a document.
  patch('patch'),

  /// Soft-delete a document.
  delete('delete');

  const DatabaseBatchOperationType(this.wireValue);

  /// The operation string sent to the backend.
  final String wireValue;
}

/// A single operation inside a batch or transaction.
@immutable
class DatabaseBatchOperation {
  /// Creates a batch operation.
  const DatabaseBatchOperation({
    required this.operation,
    required this.collection,
    this.docId,
    this.data,
  });

  /// The write to perform.
  final DatabaseBatchOperationType operation;

  /// The target collection path.
  final String collection;

  /// The target document ID. Omit on [DatabaseBatchOperationType.create] for a
  /// server-assigned ID.
  final String? docId;

  /// The payload. Not used by [DatabaseBatchOperationType.delete].
  final Map<String, dynamic>? data;

  /// Encodes this operation to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'operation': operation.wireValue,
        'collection': collection,
        if (docId != null) 'doc_id': docId,
        if (data != null) 'data': data,
      };
}

/// A single entry in a `POST /database/bulk` upsert request.
@immutable
class DatabaseBulkUpsertItem {
  /// Creates a bulk-upsert item.
  const DatabaseBulkUpsertItem({required this.data, this.docId});

  /// The document payload.
  final Map<String, dynamic> data;

  /// The target document ID. Omit for a server-assigned ID.
  final String? docId;

  /// Encodes this item to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'data': data,
        if (docId != null) 'doc_id': docId,
      };
}

/// The raw `POST /database/query` request body.
///
/// Most callers should use the fluent builder (`database.collection(...)`)
/// rather than constructing this directly.
@immutable
class DatabaseQuery {
  /// Creates a query.
  const DatabaseQuery({
    required this.collection,
    this.where = const <WhereFilter>[],
    this.orderBy = const <OrderBy>[],
    this.limit,
    this.offset,
    this.select,
    this.startAfter,
    this.startAt,
    this.count,
    this.distinct,
    this.explain,
  });

  /// The collection to query.
  final String collection;

  /// Filter conditions, combined with logical AND.
  final List<WhereFilter> where;

  /// Sort clauses, applied in order.
  final List<OrderBy> orderBy;

  /// Maximum documents to return.
  final int? limit;

  /// Documents to skip.
  final int? offset;

  /// Restrict the returned `data` to these fields.
  final List<String>? select;

  /// Cursor: start strictly after this document.
  final String? startAfter;

  /// Cursor: start at this document, inclusive.
  final String? startAt;

  /// Return a count instead of documents.
  final bool? count;

  /// Return only distinct values of this field.
  final String? distinct;

  /// Run a real Postgres `EXPLAIN (ANALYZE, FORMAT JSON)` against this query
  /// and return diagnostics as [DatabasePage.explain].
  ///
  /// Adds one extra database round trip — set this only when actually
  /// diagnosing a query, never on every request.
  final bool? explain;

  /// Encodes this query to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'collection': collection,
        if (where.isNotEmpty)
          'where': where.map((f) => f.toJson()).toList(growable: false),
        if (orderBy.isNotEmpty)
          'order_by': orderBy.map((o) => o.toJson()).toList(growable: false),
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (select != null) 'select': select,
        if (startAfter != null) 'start_after': startAfter,
        if (startAt != null) 'start_at': startAt,
        if (count != null) 'count': count,
        if (distinct != null) 'distinct': distinct,
        if (explain != null) 'explain': explain,
      };
}

/// A pointer to a specific document, matching the documented `Reference` data
/// type: stored as a `collection/docId` path string.
///
/// SuperDatabase does not enforce referential integrity — resolving a
/// reference is the application's responsibility — so this type provides only
/// construct and parse helpers, not a fetch.
@immutable
class DatabaseDocumentReference {
  /// Creates a reference from its parts.
  DatabaseDocumentReference(this.collection, this.docId)
      : path = '$collection/$docId';

  /// The collection path.
  final String collection;

  /// The document identifier.
  final String docId;

  /// The combined `collection/docId` path.
  final String path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatabaseDocumentReference && other.path == path);

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'DatabaseDocumentReference($path)';
}
