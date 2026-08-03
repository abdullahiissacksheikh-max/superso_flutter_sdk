/// Shared generic types used by every module in the SDK.
///
/// No module should define its own copy of these — always import them from
/// `package:superso_flutter_sdk/superso_flutter_sdk.dart`.
///
/// This is the Dart port of `supersosdk/src/types/common.ts`. Where the
/// TypeScript SDK uses structural interfaces, Dart uses immutable classes with
/// explicit `fromJson` constructors, because Dart has no structural typing and
/// JSON decoding is not implicit.
library;

import 'package:meta/meta.dart';

/// Standard Superso API response envelope.
///
/// Every endpoint in the platform returns this shape:
/// `{ "success": true, "message": "...", "data": {...} }`. The generic [T] is
/// the decoded `data` payload.
@immutable
class ApiResponse<T> {
  /// Creates an API response envelope.
  const ApiResponse({
    required this.success,
    required this.message,
    required this.data,
    this.meta,
  });

  /// Decodes an envelope from raw JSON, mapping `data` through [fromData].
  ///
  /// [fromData] receives the raw `data` value — which may be `null` for
  /// endpoints that return only an acknowledgement — and converts it to [T].
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? data) fromData,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      data: fromData(json['data']),
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }

  /// Whether the request succeeded.
  final bool success;

  /// Human-readable message. Never switch on this — use error codes instead.
  final String message;

  /// The decoded payload.
  final T data;

  /// Optional response metadata (rate limits, request IDs, and similar).
  final Map<String, dynamic>? meta;

  @override
  String toString() =>
      'ApiResponse(success: $success, message: $message, data: $data)';
}

/// Pagination metadata returned by list endpoints.
@immutable
class Pagination {
  /// Creates pagination metadata.
  const Pagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  /// Decodes pagination metadata from JSON.
  factory Pagination.fromJson(Map<String, dynamic> json) => Pagination(
        total: (json['total'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
        totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      );

  /// Total number of items across all pages.
  final int total;

  /// The current page number.
  final int page;

  /// Maximum number of items per page.
  final int limit;

  /// Total number of pages available.
  final int totalPages;

  /// Encodes this metadata back to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'total': total,
        'page': page,
        'limit': limit,
        'total_pages': totalPages,
      };

  @override
  String toString() =>
      'Pagination(total: $total, page: $page, limit: $limit, totalPages: $totalPages)';
}

/// A paginated collection of items plus its [Pagination] metadata.
@immutable
class PaginatedResult<T> {
  /// Creates a paginated result.
  const PaginatedResult({required this.items, required this.pagination});

  /// Decodes a paginated result, mapping each element through [fromItem].
  factory PaginatedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) fromItem,
  ) {
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    return PaginatedResult<T>(
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(fromItem)
          .toList(growable: false),
      pagination: Pagination.fromJson(
        json['pagination'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
    );
  }

  /// The items on the current page.
  final List<T> items;

  /// Metadata describing the overall result set.
  final Pagination pagination;

  @override
  String toString() =>
      'PaginatedResult(items: ${items.length}, pagination: $pagination)';
}

/// HTTP verbs supported by the shared [SupersoHttpClient].
enum HttpMethod {
  /// HTTP `GET`.
  get('GET'),

  /// HTTP `POST`.
  post('POST'),

  /// HTTP `PUT`.
  put('PUT'),

  /// HTTP `PATCH`.
  patch('PATCH'),

  /// HTTP `DELETE`.
  delete('DELETE');

  const HttpMethod(this.value);

  /// The wire representation of this verb.
  final String value;
}

/// Per-request options accepted by the shared HTTP client.
///
/// The TypeScript SDK's `AbortSignal` is replaced here by [cancelToken], which
/// is the idiomatic Dart equivalent — see [CancelToken].
@immutable
class RequestOptions {
  /// Creates per-request options.
  const RequestOptions(
      {this.headers, this.query, this.cancelToken, this.timeout});

  /// Extra headers merged into this request only.
  final Map<String, String>? headers;

  /// Query parameters appended to the URL. Null values are skipped.
  final Map<String, Object?>? query;

  /// Optional token allowing this request to be cancelled in flight.
  final CancelToken? cancelToken;

  /// Overrides the client-wide timeout for this request only.
  final Duration? timeout;
}

/// Cancels an in-flight request.
///
/// Dart has no `AbortSignal`; this is the direct equivalent. Pass the same
/// token to any number of requests and call [cancel] to abort all of them.
///
/// ```dart
/// final token = CancelToken();
/// final future = superso.database.collection('posts').get(cancelToken: token);
/// token.cancel('user navigated away');
/// ```
class CancelToken {
  /// Creates a token that has not yet been cancelled.
  CancelToken();

  String? _reason;
  final List<void Function(String reason)> _listeners =
      <void Function(String reason)>[];

  /// Whether [cancel] has been called.
  bool get isCancelled => _reason != null;

  /// Why the token was cancelled, or `null` if it is still live.
  String? get reason => _reason;

  /// Cancels every request using this token.
  ///
  /// Calling this more than once has no additional effect.
  void cancel([String reason = 'Request cancelled by caller.']) {
    if (isCancelled) return;
    _reason = reason;
    for (final listener in List<void Function(String)>.of(_listeners)) {
      listener(reason);
    }
    _listeners.clear();
  }

  /// Registers [listener], invoked when this token is cancelled.
  ///
  /// If the token is already cancelled, [listener] runs immediately.
  void addListener(void Function(String reason) listener) {
    final currentReason = _reason;
    if (currentReason != null) {
      listener(currentReason);
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously registered [listener].
  void removeListener(void Function(String reason) listener) {
    _listeners.remove(listener);
  }
}
