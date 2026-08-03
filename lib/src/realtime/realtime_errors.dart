/// Realtime-specific error hierarchy, normalized from `docs/realtime.md` §16.
///
/// Every submodule routes both WebSocket error frames and REST failures
/// through the mapping functions here, so application code never sees a raw
/// error frame or transport exception.
///
/// Dart port of `supersosdk/src/realtime/errors.ts`.
library;

import '../errors/superso_error.dart';
import 'realtime_types.dart';

/// Base class for every Realtime-domain error.
class RealtimeError extends SupersoError {
  /// Creates a realtime error.
  const RealtimeError(
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

/// The connection could not be established, closed unexpectedly, or exhausted
/// its reconnect attempts.
class ConnectionError extends RealtimeError {
  /// Creates a connection error.
  const ConnectionError([
    String message = 'The realtime connection failed.',
    String? errorCode,
    Object? details,
  ]) : super(message, errorCode: errorCode, details: details);
}

/// A subscribe or unsubscribe request failed — channel or subscriber limits,
/// or denied access.
class SubscriptionError extends RealtimeError {
  /// Creates a subscription error.
  const SubscriptionError([
    String message = 'The channel subscription request failed.',
    String? errorCode,
    Object? details,
  ]) : super(message, errorCode: errorCode, status: 429, details: details);
}

/// A correlated request received no reply within its timeout.
class RealtimeTimeoutError extends RealtimeError {
  /// Creates a timeout error.
  const RealtimeTimeoutError([
    String message =
        'The realtime request timed out waiting for a server response.',
    Object? details,
  ]) : super(message, errorCode: 'TIMEOUT', details: details);
}

/// A malformed or unrecognized frame was sent or received.
class ProtocolError extends RealtimeError {
  /// Creates a protocol error.
  const ProtocolError([
    String message = 'A realtime protocol error occurred.',
    String? errorCode,
    Object? details,
  ]) : super(message, errorCode: errorCode, status: 400, details: details);
}

/// Maps a server `error` frame to the appropriate error type.
///
/// The code vocabulary is exactly the one documented in `docs/realtime.md`
/// §16 (WebSocket Error Codes).
SupersoError mapRealtimeErrorFrame(RealtimeFrame frame) {
  final message = frame.message ?? 'Realtime error.';
  final code = frame.code;
  switch (code) {
    case 'API_KEY_MISSING':
    case 'API_KEY_INVALID':
    case 'AUTH_REQUIRED':
      return AuthenticationError(message, frame.raw);
    case 'REALTIME_DISABLED':
      return ConnectionError(message, code, frame.raw);
    case 'CHANNEL_LIMIT_EXCEEDED':
    case 'SUBSCRIBER_LIMIT_EXCEEDED':
      return SubscriptionError(message, code, frame.raw);
    case 'CHANNEL_REQUIRED':
    case 'UNKNOWN_TYPE':
    case 'MESSAGE_TOO_LARGE':
      return ProtocolError(message, code, frame.raw);
    case 'RATE_LIMIT_EXCEEDED':
      return RateLimitError(message, frame.raw);
    case 'PRESENCE_DISABLED':
    case 'BROADCAST_DISABLED':
      return RealtimeError(
        message,
        errorCode: code,
        status: 403,
        details: frame.raw,
      );
    case 'SERVER_ERROR':
      return ServerError(message, 500, frame.raw);
    default:
      return RealtimeError(message, errorCode: code, details: frame.raw);
  }
}

/// Maps a REST failure to the appropriate Realtime error type.
///
/// Mirrors the shared client's status-based classification, overriding only
/// where the documented `error.code` identifies something more specific.
SupersoError mapRealtimeRestError(Object error) {
  if (error is! SupersoError) {
    return RealtimeError('$error');
  }
  final details = error.details;
  String? code;
  var message = error.message;
  if (details is Map<String, dynamic>) {
    // The platform sends the error object either directly or nested under
    // `error`, depending on the endpoint. Both shapes are accepted.
    final nested = details['error'];
    if (nested is Map<String, dynamic>) {
      code = nested['code'] as String?;
      message = nested['message'] as String? ?? message;
    } else {
      code = details['code'] as String?;
      message = details['message'] as String? ?? message;
    }
  }
  switch (code) {
    case 'API_KEY_MISSING':
    case 'API_KEY_INVALID':
      return AuthenticationError(message, details);
    default:
      return error;
  }
}

/// Wraps a Realtime REST call, translating failures through
/// [mapRealtimeRestError].
Future<T> withRealtimeRestErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on Object catch (error) {
    throw mapRealtimeRestError(error);
  }
}
