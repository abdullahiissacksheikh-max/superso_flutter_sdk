/// Shared SDK error hierarchy.
///
/// Every module throws these — and only these — so consumers can rely on a
/// single set of error types regardless of which module (auth, database,
/// storage, realtime, media, notification, payment, ai) raised the error.
///
/// Dart port of `supersosdk/src/errors/SupersoError.ts`. The class names,
/// status mapping, and `code` values are identical to the TypeScript SDK so
/// error-handling logic ports across the two SDKs unchanged.
library;

/// Base class for every error thrown by the SDK.
///
/// Catch this to handle any Superso failure uniformly:
///
/// ```dart
/// try {
///   await superso.auth.login(email: email, password: password);
/// } on SupersoError catch (e) {
///   debugPrint('${e.code}: ${e.message}');
/// }
/// ```
class SupersoError implements Exception {
  /// Creates a Superso error.
  const SupersoError({
    required this.message,
    this.status,
    this.code,
    this.details,
  });

  /// Human-readable description. May be localized — switch on [code] instead.
  final String message;

  /// HTTP status code, or `null` for transport-level failures.
  final int? status;

  /// Machine-readable error code. This is the stable identifier to branch on.
  final String? code;

  /// Additional structured context supplied by the backend.
  ///
  /// The platform populates this for several error classes — for example the
  /// Database module's document errors and, since backend v0.3.1, API-key
  /// permission rejections (`required_permission` / `granted_permissions`).
  final Object? details;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (code != null) buffer.write(' (code: $code)');
    if (status != null) buffer.write(' [HTTP $status]');
    return buffer.toString();
  }
}

/// Request payload failed validation (HTTP 400 / 422).
class ValidationError extends SupersoError {
  /// Creates a validation error.
  const ValidationError(String message, [Object? details])
      : super(
          message: message,
          status: 400,
          code: 'VALIDATION_ERROR',
          details: details,
        );
}

/// Missing, invalid, or expired credentials (HTTP 401).
class AuthenticationError extends SupersoError {
  /// Creates an authentication error.
  const AuthenticationError([
    String message = 'Authentication failed.',
    Object? details,
  ]) : super(
          message: message,
          status: 401,
          code: 'AUTHENTICATION_ERROR',
          details: details,
        );
}

/// Authenticated but not authorized for this action (HTTP 403).
class PermissionError extends SupersoError {
  /// Creates a permission error.
  const PermissionError([
    String message = 'You do not have permission to perform this action.',
    Object? details,
  ]) : super(
          message: message,
          status: 403,
          code: 'PERMISSION_ERROR',
          details: details,
        );
}

/// Requested resource does not exist (HTTP 404).
class NotFoundError extends SupersoError {
  /// Creates a not-found error.
  const NotFoundError([
    String message = 'The requested resource was not found.',
    Object? details,
  ]) : super(
          message: message,
          status: 404,
          code: 'NOT_FOUND_ERROR',
          details: details,
        );
}

/// Resource already exists, e.g. a duplicate email or phone (HTTP 409).
class ConflictError extends SupersoError {
  /// Creates a conflict error.
  const ConflictError([
    String message = 'This resource already exists.',
    Object? details,
  ]) : super(
          message: message,
          status: 409,
          code: 'CONFLICT_ERROR',
          details: details,
        );
}

/// Too many requests in a given time window (HTTP 429).
class RateLimitError extends SupersoError {
  /// Creates a rate-limit error.
  const RateLimitError([
    String message = 'Too many requests, please try again later.',
    Object? details,
  ]) : super(
          message: message,
          status: 429,
          code: 'RATE_LIMIT_ERROR',
          details: details,
        );
}

/// Request never reached the server (timeout, DNS failure, offline, aborted).
class NetworkError extends SupersoError {
  /// Creates a network error.
  const NetworkError([
    String message = 'A network error occurred while contacting Superso.',
    Object? details,
  ]) : super(message: message, code: 'NETWORK_ERROR', details: details);
}

/// The request was cancelled via a [CancelToken] before it completed.
///
/// This has no TypeScript equivalent by name — the JS SDK surfaces an aborted
/// `fetch` as a [NetworkError]. Dart separates it so callers can distinguish
/// "the user navigated away" from "the network failed", which matters for
/// error reporting and retry logic in a mobile app.
class CancelledError extends SupersoError {
  /// Creates a cancellation error.
  const CancelledError([String message = 'Request cancelled by caller.'])
      : super(message: message, code: 'CANCELLED');
}

/// Superso responded with a server-side failure (HTTP 5xx).
class ServerError extends SupersoError {
  /// Creates a server error.
  const ServerError([
    String message = 'Superso encountered an internal error.',
    int status = 500,
    Object? details,
  ]) : super(
          message: message,
          status: status,
          code: 'SERVER_ERROR',
          details: details,
        );
}

/// Maps an HTTP status code to the appropriate [SupersoError] subclass.
///
/// This is the ONLY place status-to-error mapping happens — it is used
/// exclusively by the shared HTTP client so every module gets identical error
/// handling. Mirrors `errorFromResponse` in the TypeScript SDK exactly.
SupersoError errorFromResponse(int status, String message, [Object? details]) {
  if (status == 400 || status == 422) return ValidationError(message, details);
  if (status == 401) return AuthenticationError(message, details);
  if (status == 403) return PermissionError(message, details);
  if (status == 404) return NotFoundError(message, details);
  if (status == 409) return ConflictError(message, details);
  if (status == 429) return RateLimitError(message, details);
  if (status >= 500) return ServerError(message, status, details);
  return SupersoError(message: message, status: status, details: details);
}
