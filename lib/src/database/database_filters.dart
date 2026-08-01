/// Query filter primitives from `docs/database.md` §11 (Query System — Where
/// Operators).
///
/// Defined once here and imported by both the raw wire request and the fluent
/// builder, so the operator list exists in exactly one place.
///
/// Dart port of `supersosdk/src/database/filters.ts`.
library;

import 'package:meta/meta.dart';

/// Every `where` operator the query engine implements.
///
/// Kept in sync with `model.QueryOperator` / `buildFilter` in the Go query
/// engine (`backend/internal/modules/database/repository/query_repository.go`).
///
/// A note carried over from the TypeScript SDK, because it still matters: an
/// earlier revision of this list included `regex` and `prefix`, which
/// type-checked but were rejected at request time with
/// `400 QUERY_OPERATOR_UNKNOWN`. The names below are the ones the engine
/// actually accepts — `matchesRegex` maps to `matches_regex`, not `regex`.
///
/// [exists], [notExists], [isNull], and [isNotNull] ignore `value` entirely;
/// the backend discards whatever is sent for those four.
enum WhereOperator {
  /// Equal to.
  equal('=='),

  /// Not equal to.
  notEqual('!='),

  /// Less than.
  lessThan('<'),

  /// Less than or equal to.
  lessThanOrEqual('<='),

  /// Greater than.
  greaterThan('>'),

  /// Greater than or equal to.
  greaterThanOrEqual('>='),

  /// Value is one of a supplied list.
  whereIn('in'),

  /// Value is not one of a supplied list.
  notIn('not_in'),

  /// Value falls between `value` and `value2`, inclusive.
  between('between'),

  /// String contains a substring.
  contains('contains'),

  /// String starts with a prefix.
  startsWith('starts_with'),

  /// String ends with a suffix.
  endsWith('ends_with'),

  /// Array field contains a specific element.
  arrayContains('array_contains'),

  /// Array field contains any element of a supplied list.
  arrayContainsAny('array_contains_any'),

  /// Field is present on the document.
  exists('exists'),

  /// Field is absent from the document.
  notExists('not_exists'),

  /// Field is explicitly null.
  isNull('is_null'),

  /// Field is not null.
  isNotNull('is_not_null'),

  /// Field matches a regular expression.
  matchesRegex('matches_regex'),

  /// Full-text search across the field.
  textSearch('text_search'),

  /// JSON object has the given key.
  hasKey('has_key'),

  /// JSON object has the given value.
  hasValue('has_value'),

  /// JSON path expression matches.
  jsonPath('json_path');

  const WhereOperator(this.wireValue);

  /// The operator string sent to the backend.
  final String wireValue;
}

/// A single filter condition.
///
/// [value2] is used only by [WhereOperator.between] (the upper bound), e.g.
/// `WhereFilter('age', WhereOperator.between, 18, 65)`.
@immutable
class WhereFilter {
  /// Creates a filter condition.
  const WhereFilter(this.field, this.op, [this.value, this.value2]);

  /// The document field this condition applies to.
  final String field;

  /// The comparison operator.
  final WhereOperator op;

  /// The comparison value. Ignored by the presence/null operators.
  final Object? value;

  /// The upper bound, used only by [WhereOperator.between].
  final Object? value2;

  /// Encodes this filter to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'field': field,
        'op': op.wireValue,
        if (value != null) 'value': value,
        if (value2 != null) 'value2': value2,
      };

  @override
  String toString() => 'WhereFilter($field ${op.wireValue} $value)';
}

/// Sort direction for an [OrderBy] clause.
enum OrderByDirection {
  /// Ascending order.
  asc('asc'),

  /// Descending order.
  desc('desc');

  const OrderByDirection(this.wireValue);

  /// The direction string sent to the backend.
  final String wireValue;
}

/// A single sort clause.
@immutable
class OrderBy {
  /// Creates a sort clause.
  const OrderBy(this.field, [this.direction = OrderByDirection.asc]);

  /// The document field to sort by.
  final String field;

  /// The sort direction.
  final OrderByDirection direction;

  /// Encodes this clause to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'field': field,
        'direction': direction.wireValue,
      };

  @override
  String toString() => 'OrderBy($field ${direction.wireValue})';
}
