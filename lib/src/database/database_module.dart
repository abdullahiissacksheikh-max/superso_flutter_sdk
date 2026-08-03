/// The Database module: collections, documents, queries, batches, and
/// transactions.
///
/// Dart port of `supersosdk/src/database/{collections,documents,queries,
/// batch,transactions,database,converters,pagination}.ts`, consolidated into
/// one library because the Dart submodules are thin and splitting them across
/// eight files would add imports without adding clarity.
library;

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'database_errors.dart';
import 'database_filters.dart';
import 'database_types.dart';

/// The default `data` decoder: returns the raw JSON map unchanged.
Map<String, dynamic> rawData(Map<String, dynamic> data) => data;

/// Sentinel that stamps a field with the server's current UTC time at write
/// time.
///
/// Use as the value of any field inside the `data` map passed to
/// [DocumentsModule.create], [DocumentsModule.set], [DocumentsModule.update],
/// or [DocumentsModule.patch]. Mirrors Firestore's
/// `FieldValue.serverTimestamp()`.
///
/// ```dart
/// await db.documents.create('posts', {
///   'title': 'Hello',
///   'created': serverTimestamp(),
/// });
/// ```
String serverTimestamp() => serverTimestampSentinel;

/// Sentinel that atomically adds [n] to the current value of a numeric field.
///
/// Only takes effect inside a `PATCH`-based write ([DocumentsModule.update],
/// [DocumentsModule.patch], or a batch `update`/`patch` operation). Mirrors
/// Firestore's `FieldValue.increment()`.
///
/// ```dart
/// await db.documents.patch('posts', docId, {'views': increment(1)});
/// ```
Map<String, dynamic> increment(num n) => <String, dynamic>{'__increment__': n};

/// Parses a documented reference path string (e.g. `users/KdX7mNpQ9vRw2sTu`)
/// into its parts.
///
/// Throws a [ValidationError] if [path] is not in `collection/docId` form.
DatabaseDocumentReference parseDocumentReference(String path) {
  final idx = path.lastIndexOf('/');
  if (idx <= 0 || idx == path.length - 1) {
    throw ValidationError(
      'Invalid document reference path: "$path". Expected the documented '
      '"<collection>/<doc_id>" format.',
    );
  }
  return DatabaseDocumentReference(
    path.substring(0, idx),
    path.substring(idx + 1),
  );
}

/// Administrative collection lifecycle (`docs/database.md` §19.1–19.4).
///
/// Collections are also created implicitly on first document insert; this
/// module is for explicit management. Exposed at `superso.database.collections`.
class CollectionsModule {
  /// Creates a collections module bound to [client].
  const CollectionsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /database/collections` — lists top-level collections, or the
  /// subcollections of [parentPath] when provided.
  Future<ApiResponse<List<DatabaseCollection>>> list([String? parentPath]) {
    return withDatabaseErrors(
      () => _client.get<List<DatabaseCollection>>(
        '/database/collections',
        options: parentPath == null
            ? null
            : RequestOptions(
                query: <String, Object?>{'parent_path': parentPath}),
        decoder: (data) => (data as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(DatabaseCollection.fromJson)
            .toList(growable: false),
      ),
    );
  }

  /// `POST /database/collections` — explicitly creates a collection.
  ///
  /// Supports subcollections via [parentPath].
  Future<ApiResponse<DatabaseCollection>> create({
    required String path,
    String? name,
    String? parentPath,
  }) {
    return withDatabaseErrors(
      () => _client.post<DatabaseCollection>(
        '/database/collections',
        body: <String, dynamic>{
          'path': path,
          if (name != null) 'name': name,
          if (parentPath != null) 'parent_path': parentPath,
        },
        decoder: _collectionDecoder,
      ),
    );
  }

  /// `GET /database/collections/:collection`
  Future<ApiResponse<DatabaseCollection>> get(String path) {
    return withDatabaseErrors(
      () => _client.get<DatabaseCollection>(
        '/database/collections/${encodeSegment(path)}',
        decoder: _collectionDecoder,
      ),
    );
  }

  /// `PATCH /database/collections/:collection` — renames the collection's
  /// display name.
  Future<ApiResponse<DatabaseCollection>> rename(
    String path,
    String newName,
  ) {
    return withDatabaseErrors(
      () => _client.patch<DatabaseCollection>(
        '/database/collections/${encodeSegment(path)}',
        body: <String, dynamic>{'new_name': newName},
        decoder: _collectionDecoder,
      ),
    );
  }

  /// `DELETE /database/collections/:collection` — deletes the collection and
  /// all of its documents.
  Future<ApiResponse<void>> delete(String path) {
    return withDatabaseErrors(
      () => _client.delete<void>(
        '/database/collections/${encodeSegment(path)}',
        decoder: (_) {},
      ),
    );
  }

  static DatabaseCollection _collectionDecoder(Object? data) =>
      DatabaseCollection.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );
}

/// Full document CRUD (`docs/database.md` §19.5–19.11).
///
/// Supports autogenerated IDs (omit `docId` on [create]), custom IDs, server
/// timestamps and atomic increment (via the [serverTimestamp] and [increment]
/// sentinels embedded in `data`), and nested collection paths (any collection
/// string, e.g. `users/alice/comments`).
///
/// [set] maps to the documented `PUT` (full replace) endpoint. [update] and
/// [patch] both map to the documented `PATCH` (partial merge) endpoint — both
/// names exist because developers coming from Firestore expect `update` and
/// developers coming from REST expect `patch`; the platform defines only one
/// merge semantics for a single document, so both call the same route.
///
/// Identity: this module never generates a document ID itself — the backend is
/// the single source of truth for document IDs. [create]'s `docId` is
/// forwarded verbatim (or omitted) exactly as passed; the ID to use for every
/// subsequent operation is always the `docId` field of the returned document,
/// never a value computed on the client.
class DocumentsModule {
  /// Creates a documents module bound to [client].
  const DocumentsModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /database/collections/:collection/documents` — creates a document.
  ///
  /// Omit [docId] to let the server assign one per the project's Default ID
  /// Type setting.
  Future<ApiResponse<DatabaseDocument<Map<String, dynamic>>>> create(
    String collection,
    Map<String, dynamic> data, {
    String? docId,
  }) {
    return withDatabaseErrors(
      () => _client.post<DatabaseDocument<Map<String, dynamic>>>(
        '/database/collections/${encodeSegment(collection)}/documents',
        body: <String, dynamic>{
          if (docId != null) 'doc_id': docId,
          'data': data,
        },
        decoder: _documentDecoder,
      ),
    );
  }

  /// `PUT /database/collections/:collection/documents/:docId` — full replace.
  Future<ApiResponse<DatabaseDocument<Map<String, dynamic>>>> set(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) {
    return withDatabaseErrors(
      () => _client.put<DatabaseDocument<Map<String, dynamic>>>(
        _docPath(collection, docId),
        body: <String, dynamic>{'data': data},
        decoder: _documentDecoder,
      ),
    );
  }

  /// `PATCH /database/collections/:collection/documents/:docId` — partial
  /// merge.
  Future<ApiResponse<DatabaseDocument<Map<String, dynamic>>>> update(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) {
    return withDatabaseErrors(
      () => _client.patch<DatabaseDocument<Map<String, dynamic>>>(
        _docPath(collection, docId),
        body: <String, dynamic>{'data': data},
        decoder: _documentDecoder,
      ),
    );
  }

  /// Alias of [update] — same `PATCH` endpoint (partial merge).
  Future<ApiResponse<DatabaseDocument<Map<String, dynamic>>>> patch(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) =>
      update(collection, docId, data);

  /// `DELETE /database/collections/:collection/documents/:docId` —
  /// soft-delete. Recover with [restore].
  Future<ApiResponse<void>> delete(String collection, String docId) {
    return withDatabaseErrors(
      () => _client.delete<void>(_docPath(collection, docId), decoder: (_) {}),
    );
  }

  /// `POST /database/collections/:collection/documents/:docId/restore` —
  /// un-deletes a soft-deleted document.
  Future<ApiResponse<DatabaseDocument<Map<String, dynamic>>>> restore(
    String collection,
    String docId,
  ) {
    return withDatabaseErrors(
      () => _client.post<DatabaseDocument<Map<String, dynamic>>>(
        '${_docPath(collection, docId)}/restore',
        decoder: _documentDecoder,
      ),
    );
  }

  /// `GET /database/collections/:collection/documents/:docId`
  Future<ApiResponse<DatabaseDocument<Map<String, dynamic>>>> get(
    String collection,
    String docId,
  ) {
    return withDatabaseErrors(
      () => _client.get<DatabaseDocument<Map<String, dynamic>>>(
        _docPath(collection, docId),
        decoder: _documentDecoder,
      ),
    );
  }

  /// `POST /database/exists` — checks document existence without transferring
  /// its data.
  ///
  /// Uses the dedicated endpoint rather than a [get]-and-catch, which would
  /// fetch the entire document body just to answer a yes/no question.
  Future<bool> exists(String collection, String docId) {
    return withDatabaseErrors(() async {
      final res = await _client.post<Map<String, dynamic>>(
        '/database/exists',
        body: <String, dynamic>{'collection': collection, 'doc_id': docId},
        decoder: (data) =>
            data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );
      return res.data['exists'] as bool? ?? false;
    });
  }

  /// `GET /database/collections/:collection/documents` — paginated list.
  Future<ApiResponse<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>>
      list(
    String collection, {
    int? limit,
    int? offset,
  }) {
    return withDatabaseErrors(
      () => _client.get<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>(
        '/database/collections/${encodeSegment(collection)}/documents',
        options: RequestOptions(
          query: <String, Object?>{'limit': limit, 'offset': offset},
        ),
        decoder: (data) => toPage(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  String _docPath(String collection, String docId) =>
      '/database/collections/${encodeSegment(collection)}'
      '/documents/${encodeSegment(docId)}';

  static DatabaseDocument<Map<String, dynamic>> _documentDecoder(
          Object? data) =>
      DatabaseDocument<Map<String, dynamic>>.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
        rawData,
      );
}

/// Normalizes the raw `{documents, total, has_more, next_cursor}` wire shape
/// into a [DatabasePage].
///
/// Shared by both document listing and query execution, so the conversion
/// exists in exactly one place.
DatabasePage<DatabaseDocument<Map<String, dynamic>>> toPage(
  Map<String, dynamic> raw,
) {
  final documents = (raw['documents'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map((d) => DatabaseDocument<Map<String, dynamic>>.fromJson(d, rawData))
      .toList(growable: false);
  final explain = raw['explain'];
  return DatabasePage<DatabaseDocument<Map<String, dynamic>>>(
    items: documents,
    total: (raw['total'] as num?)?.toInt() ?? documents.length,
    hasMore: raw['has_more'] as bool? ?? false,
    nextCursor: raw['next_cursor'] as String?,
    explain: explain is Map<String, dynamic>
        ? DatabaseQueryExplain.fromJson(explain)
        : null,
  );
}

/// Fluent query builder scoped to a single collection.
///
/// ```dart
/// final page = await db.collection('users')
///     .where('age', WhereOperator.greaterThanOrEqual, 18)
///     .where('verified', WhereOperator.equal, true)
///     .orderBy('created_at', OrderByDirection.desc)
///     .limit(20)
///     .get();
/// ```
///
/// Every terminal method ([get], [count], [exists]) issues the request through
/// the shared client; the builder itself never constructs HTTP calls.
class QueryBuilder {
  /// Creates a builder scoped to [collection].
  QueryBuilder(this._client, this._collection);

  final SupersoHttpClient _client;
  final String _collection;
  final List<WhereFilter> _where = <WhereFilter>[];
  final List<OrderBy> _orderBy = <OrderBy>[];
  int? _limit;
  int? _offset;
  List<String>? _select;
  String? _startAfter;
  String? _startAt;
  String? _distinct;
  bool _explain = false;

  /// Adds a filter condition. Conditions combine with logical AND.
  ///
  /// [value2] is used only by [WhereOperator.between].
  QueryBuilder where(
    String field,
    WhereOperator op, [
    Object? value,
    Object? value2,
  ]) {
    _where.add(WhereFilter(field, op, value, value2));
    return this;
  }

  /// Adds a sort clause. Clauses apply in the order added.
  QueryBuilder orderBy(
    String field, [
    OrderByDirection direction = OrderByDirection.asc,
  ]) {
    _orderBy.add(OrderBy(field, direction));
    return this;
  }

  /// Limits the result set to [n] documents.
  QueryBuilder limit(int n) {
    _limit = n;
    return this;
  }

  /// Skips [n] documents.
  QueryBuilder offset(int n) {
    _offset = n;
    return this;
  }

  /// Restricts the returned `data` to [fields].
  QueryBuilder select(List<String> fields) {
    _select = fields;
    return this;
  }

  /// Starts strictly after the document with [docId].
  QueryBuilder startAfter(String docId) {
    _startAfter = docId;
    return this;
  }

  /// Starts at the document with [docId], inclusive.
  QueryBuilder startAt(String docId) {
    _startAt = docId;
    return this;
  }

  /// Returns only distinct values of [field].
  QueryBuilder distinct(String field) {
    _distinct = field;
    return this;
  }

  /// Opts this query into a real Postgres `EXPLAIN (ANALYZE, FORMAT JSON)`
  /// run; the resulting page's `explain` field carries the plan diagnostics.
  ///
  /// Adds one extra database round trip — call this only when diagnosing.
  QueryBuilder explain() {
    _explain = true;
    return this;
  }

  /// The raw [DatabaseQuery] this builder has accumulated.
  DatabaseQuery toQuery() => DatabaseQuery(
        collection: _collection,
        where: List<WhereFilter>.unmodifiable(_where),
        orderBy: List<OrderBy>.unmodifiable(_orderBy),
        limit: _limit,
        offset: _offset,
        select: _select,
        startAfter: _startAfter,
        startAt: _startAt,
        distinct: _distinct,
        explain: _explain ? true : null,
      );

  /// `POST /database/query` — executes the query and returns a page.
  Future<ApiResponse<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>>
      get() {
    return withDatabaseErrors(
      () => _client.post<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>(
        '/database/query',
        body: toQuery().toJson(),
        decoder: (data) => toPage(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /database/count` — counts matching documents without transferring
  /// them.
  Future<ApiResponse<DatabaseCountResult>> count() {
    return withDatabaseErrors(
      () => _client.post<DatabaseCountResult>(
        '/database/count',
        body: toQuery().toJson(),
        decoder: (data) => DatabaseCountResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /database/exists` — whether any document matches the filters.
  ///
  /// For a specific known document ID, use [DocumentsModule.exists] instead —
  /// it is cheaper, since it needs no query planning.
  Future<ApiResponse<DatabaseExistsResult>> exists() {
    final body = toQuery().toJson()..['limit'] = 1;
    return withDatabaseErrors(
      () => _client.post<DatabaseExistsResult>(
        '/database/exists',
        body: body,
        decoder: (data) => DatabaseExistsResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

/// The composition root for the Database module.
///
/// ```dart
/// // Fluent query
/// final page = await superso.database
///     .collection('posts')
///     .where('published', WhereOperator.equal, true)
///     .orderBy('created_at', OrderByDirection.desc)
///     .limit(20)
///     .get();
///
/// // Direct CRUD
/// final doc = await superso.database.documents.create('posts', {'title': 'Hi'});
/// await superso.database.documents.patch('posts', doc.data.docId, {
///   'views': increment(1),
/// });
/// ```
class DatabaseModule implements SdkModule {
  /// Creates the database module bound to [client].
  DatabaseModule(this.client)
      : collections = CollectionsModule(client),
        documents = DocumentsModule(client);

  @override
  final SupersoHttpClient client;

  /// Administrative collection lifecycle.
  final CollectionsModule collections;

  /// Document CRUD.
  final DocumentsModule documents;

  /// Starts a fluent query scoped to [collection].
  QueryBuilder collection(String collection) =>
      QueryBuilder(client, collection);

  /// `POST /database/query` — executes a pre-built [DatabaseQuery].
  ///
  /// Prefer [collection] for readability; this exists for callers that build
  /// queries dynamically.
  Future<ApiResponse<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>>
      query(DatabaseQuery query) {
    return withDatabaseErrors(
      () => client.post<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>(
        '/database/query',
        body: query.toJson(),
        decoder: (data) => toPage(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /database/batch` — applies up to [maxBatchOperations] writes in one
  /// request.
  ///
  /// Operations are applied independently: a failure in one does not roll back
  /// the others, and the result reports both counts. Use [transaction] when
  /// all-or-nothing semantics are required.
  ///
  /// Throws a [ValidationError] if more than [maxBatchOperations] are supplied,
  /// rather than letting the server reject the whole request.
  Future<ApiResponse<DatabaseBatchResult>> batch(
    List<DatabaseBatchOperation> operations,
  ) {
    if (operations.length > maxBatchOperations) {
      throw ValidationError(
        'A batch accepts at most $maxBatchOperations operations; '
        '${operations.length} were supplied. Split them across multiple '
        'batch() calls.',
      );
    }
    return withDatabaseErrors(
      () => client.post<DatabaseBatchResult>(
        '/database/batch',
        body: <String, dynamic>{
          'operations':
              operations.map((o) => o.toJson()).toList(growable: false),
        },
        decoder: (data) => DatabaseBatchResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /database/transactions` — applies every operation inside a single
  /// PostgreSQL transaction.
  ///
  /// Rolls back entirely on any failure, surfacing a [TransactionFailedError];
  /// a completed call therefore always means every operation succeeded.
  Future<ApiResponse<DatabaseTransactionResult>> transaction(
    List<DatabaseBatchOperation> operations,
  ) {
    if (operations.length > maxBatchOperations) {
      throw ValidationError(
        'A transaction accepts at most $maxBatchOperations operations; '
        '${operations.length} were supplied.',
      );
    }
    return withDatabaseErrors(
      () => client.post<DatabaseTransactionResult>(
        '/database/transactions',
        body: <String, dynamic>{
          'operations':
              operations.map((o) => o.toJson()).toList(growable: false),
        },
        decoder: (data) => DatabaseTransactionResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /database/bulk` — upserts many documents into [collection] at once.
  Future<ApiResponse<DatabaseBatchResult>> bulkUpsert(
    String collection,
    List<DatabaseBulkUpsertItem> items,
  ) {
    return withDatabaseErrors(
      () => client.post<DatabaseBatchResult>(
        '/database/bulk',
        body: <String, dynamic>{
          'collection': collection,
          'documents': items.map((i) => i.toJson()).toList(growable: false),
        },
        decoder: (data) => DatabaseBatchResult.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}
