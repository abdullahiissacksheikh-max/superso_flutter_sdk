/// Shared URL helpers.
///
/// These are used exclusively by [SupersoConfig] and the shared HTTP client —
/// no module should build query strings or join paths itself.
///
/// Dart port of `supersosdk/src/utils/url.ts`.
library;

/// Serializes a map into a `?a=1&b=2` query string, skipping null values.
///
/// Returns an empty string when [query] yields no usable entries, so the
/// result can always be concatenated onto a URL unconditionally.
///
/// ```dart
/// buildQueryString({'page': 1, 'q': 'hello world', 'cursor': null});
/// // => '?page=1&q=hello+world'
/// ```
String buildQueryString(Map<String, Object?> query) {
  final pairs = <String>[];
  for (final entry in query.entries) {
    final value = entry.value;
    if (value == null) continue;
    final encodedKey = Uri.encodeQueryComponent(entry.key);
    final encodedValue = Uri.encodeQueryComponent('$value');
    pairs.add('$encodedKey=$encodedValue');
  }
  return pairs.isEmpty ? '' : '?${pairs.join('&')}';
}

/// Joins path [segments] into a single leading-slash path without double
/// slashes.
///
/// ```dart
/// joinPath(['/media/', '/sessions', 'abc']); // => '/media/sessions/abc'
/// ```
String joinPath(List<String> segments) {
  final cleaned = segments
      .map((s) => s.replaceAll(RegExp(r'^/+|/+$'), ''))
      .where((s) => s.isNotEmpty);
  return '/${cleaned.join('/')}';
}

/// Percent-encodes a single path segment.
///
/// Every module uses this when interpolating a user-supplied identifier into a
/// URL path, so an ID containing `/` or a space can never break routing. This
/// is the Dart equivalent of the TypeScript SDK's `encodeURIComponent` calls.
String encodeSegment(String segment) => Uri.encodeComponent(segment);
