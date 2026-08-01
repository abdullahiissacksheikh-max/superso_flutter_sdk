/// The Payment module: WaafiPay-family operations plus Stripe.
///
/// Dart port of `supersosdk/src/payment/*`.
///
/// **Scope.** Every one of the 10 `X-API-Key` payment routes and 7 Stripe
/// routes is implemented. Gateway health, transaction listing, analytics,
/// logs, and webhooks are not exposed, because no `X-API-Key` route exists for
/// them anywhere in the backend — they are Admin-JWT only. Shipping methods
/// that would reliably 404 would be worse than omitting them.
library;

import 'dart:async';

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../types/common.dart';
import '../utils/url.dart';
import 'payment_types.dart';

/// Base class for every Payment-domain error.
class PaymentError extends SupersoError {
  /// Creates a payment error.
  const PaymentError(
    String message, {
    int? status,
    String? code,
    Object? details,
  }) : super(message: message, status: status, code: code, details: details);
}

/// The gateway rejected the operation.
///
/// Inspect [PaymentResult.providerResponseCode] on the result — or
/// [SupersoError.details] here — for the gateway's own reason code.
class PaymentDeclinedError extends PaymentError {
  /// Creates a declined error.
  const PaymentDeclinedError(
    String message, [
    Object? details,
  ]) : super(message, code: 'PAYMENT_DECLINED', details: details);
}

/// The project has no usable gateway configured.
class GatewayNotConfiguredError extends PaymentError {
  /// Creates a gateway-configuration error.
  const GatewayNotConfiguredError(
    String message, [
    int? status,
    Object? details,
  ]) : super(
          message,
          status: status,
          code: 'GATEWAY_NOT_CONFIGURED',
          details: details,
        );
}

/// Wraps a Payment call, normalizing failures into this hierarchy.
Future<T> withPaymentErrors<T>(Future<T> Function() operation) async {
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
    if (error.status == 422 || error.code == 'GATEWAY_NOT_CONFIGURED') {
      throw GatewayNotConfiguredError(
        error.message,
        error.status,
        error.details,
      );
    }
    throw PaymentError(
      error.message,
      status: error.status,
      code: error.code,
      details: error.details,
    );
  } on Object catch (error) {
    throw PaymentError('$error');
  }
}

void _requireNonEmpty(String value, String field) {
  if (value.trim().isEmpty) {
    throw ValidationError('Superso: `$field` is required and cannot be empty.');
  }
}

void _requirePositive(num value, String field) {
  if (value <= 0) {
    throw ValidationError('Superso: `$field` must be greater than zero.');
  }
}

/// Gateway discovery.
///
/// Exposed at `superso.payment.gateway`.
class GatewayModule {
  /// Creates a gateway module bound to [client].
  const GatewayModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /v1/payment/gateway` — the project's active gateway configuration.
  ///
  /// Omit [gateway] to use the server's backward-compatible WaafiPay-then-
  /// Stripe priority.
  Future<ApiResponse<PaymentGateway>> get({PaymentGatewayName? gateway}) {
    return withPaymentErrors(
      () => _client.get<PaymentGateway>(
        '/payment/gateway',
        options: RequestOptions(
          query: <String, Object?>{'gateway': gateway?.wireValue},
        ),
        decoder: (data) => PaymentGateway.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

/// Hosted Payment Page operations.
///
/// Exposed at `superso.payment.hpp`.
class HppModule {
  /// Creates an HPP module bound to [client].
  const HppModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/payment/hpp/purchase` — creates a hosted payment session.
  ///
  /// Open the returned [PaymentResult.hppUrl] in a browser or web view to let
  /// the customer complete payment.
  ///
  /// [currency] is optional: the backend resolves the merchant's configured
  /// currency when it is omitted, falling back to USD. Pass it only to
  /// override that resolution for one request.
  Future<ApiResponse<PaymentResult>> purchase({
    required String accountNo,
    required double amount,
    String? currency,
    String? invoiceId,
    String? referenceId,
    String? description,
    String? successCallbackUrl,
    String? failureCallbackUrl,
  }) {
    _requireNonEmpty(accountNo, 'accountNo');
    _requirePositive(amount, 'amount');
    return withPaymentErrors(
      () => _client.post<PaymentResult>(
        '/payment/hpp/purchase',
        body: <String, dynamic>{
          'account_no': accountNo,
          'amount': amount,
          if (currency != null) 'currency': currency,
          if (invoiceId != null) 'invoice_id': invoiceId,
          if (referenceId != null) 'reference_id': referenceId,
          if (description != null) 'description': description,
          if (successCallbackUrl != null)
            'success_callback_url': successCallbackUrl,
          if (failureCallbackUrl != null)
            'failure_callback_url': failureCallbackUrl,
        },
        decoder: _result,
      ),
    );
  }

  /// `POST /v1/payment/refund` — refunds a settled transaction.
  Future<ApiResponse<PaymentResult>> refund({
    required String transactionId,
    double? amount,
    String? description,
  }) {
    _requireNonEmpty(transactionId, 'transactionId');
    return withPaymentErrors(
      () => _client.post<PaymentResult>(
        '/payment/refund',
        body: <String, dynamic>{
          'transaction_id': transactionId,
          if (amount != null) 'amount': amount,
          if (description != null) 'description': description,
        },
        decoder: _result,
      ),
    );
  }
}

/// Transaction record lookup.
///
/// Exposed at `superso.payment.transactions`.
///
/// There is deliberately no `list` method: transaction listing is Admin-JWT
/// only, with no `X-API-Key` equivalent.
class PaymentTransactionsModule {
  /// Creates a transactions module bound to [client].
  const PaymentTransactionsModule(this._client);

  final SupersoHttpClient _client;

  /// `GET /v1/payment/transaction/:id`
  Future<ApiResponse<PaymentTransaction>> get(String transactionId) {
    _requireNonEmpty(transactionId, 'transactionId');
    return withPaymentErrors(
      () => _client.get<PaymentTransaction>(
        '/payment/transaction/${encodeSegment(transactionId)}',
        decoder: (data) => PaymentTransaction.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

/// Stripe operations.
///
/// Exposed at `superso.payment.stripe`.
///
/// This SDK never confirms a PaymentIntent or handles card details — that
/// requires Stripe's own mobile SDK, which keeps card data off your server and
/// out of this package. The flow is: create an intent here, hand its
/// [StripePaymentIntent.clientSecret] to `flutter_stripe`, and let Stripe
/// complete it.
class StripeModule {
  /// Creates a Stripe module bound to [client].
  const StripeModule(this._client);

  final SupersoHttpClient _client;

  /// `POST /v1/stripe/payment-intents` — creates a PaymentIntent.
  ///
  /// [amountMinor] is in the currency's smallest unit — cents for USD.
  Future<ApiResponse<StripePaymentIntent>> createPaymentIntent({
    required int amountMinor,
    required String orderId,
    String? currency,
    String? customerId,
    StripeCaptureMethod? captureMethod,
    String? description,
    Map<String, String>? metadata,
  }) {
    _requirePositive(amountMinor, 'amountMinor');
    _requireNonEmpty(orderId, 'orderId');
    return withPaymentErrors(
      () => _client.post<StripePaymentIntent>(
        '/stripe/payment-intents',
        body: <String, dynamic>{
          'amount_minor': amountMinor,
          'order_id': orderId,
          if (currency != null) 'currency': currency,
          if (customerId != null) 'customer_id': customerId,
          if (captureMethod != null)
            'capture_method': captureMethod.wireValue,
          if (description != null) 'description': description,
          if (metadata != null) 'metadata': metadata,
        },
        decoder: _paymentIntent,
      ),
    );
  }

  /// `GET /v1/stripe/payment-intents/:piId`
  Future<ApiResponse<StripePaymentIntent>> getPaymentIntent(String piId) {
    _requireNonEmpty(piId, 'piId');
    return withPaymentErrors(
      () => _client.get<StripePaymentIntent>(
        '/stripe/payment-intents/${encodeSegment(piId)}',
        decoder: _paymentIntent,
      ),
    );
  }

  /// `POST /v1/stripe/payment-intents/:piId/capture` — captures held funds.
  ///
  /// Only valid on an intent created with [StripeCaptureMethod.manual]. Omit
  /// [amountToCapture] for a full capture.
  Future<ApiResponse<StripePaymentIntent>> capturePaymentIntent(
    String piId, {
    int? amountToCapture,
  }) {
    _requireNonEmpty(piId, 'piId');
    return withPaymentErrors(
      () => _client.post<StripePaymentIntent>(
        '/stripe/payment-intents/${encodeSegment(piId)}/capture',
        body: <String, dynamic>{
          if (amountToCapture != null) 'amount_to_capture': amountToCapture,
        },
        decoder: _paymentIntent,
      ),
    );
  }

  /// `POST /v1/stripe/payment-intents/:piId/cancel` — cancels an uncaptured
  /// PaymentIntent, releasing the authorization hold at no cost.
  Future<ApiResponse<StripePaymentIntent>> cancelPaymentIntent(String piId) {
    _requireNonEmpty(piId, 'piId');
    return withPaymentErrors(
      () => _client.post<StripePaymentIntent>(
        '/stripe/payment-intents/${encodeSegment(piId)}/cancel',
        decoder: _paymentIntent,
      ),
    );
  }

  /// `POST /v1/stripe/customers` — creates a customer for saved-card flows.
  Future<ApiResponse<StripeCustomer>> createCustomer({
    String? email,
    String? name,
    String? internalUserId,
    Map<String, String>? metadata,
  }) {
    return withPaymentErrors(
      () => _client.post<StripeCustomer>(
        '/stripe/customers',
        body: <String, dynamic>{
          if (email != null) 'email': email,
          if (name != null) 'name': name,
          if (internalUserId != null) 'internal_user_id': internalUserId,
          if (metadata != null) 'metadata': metadata,
        },
        decoder: _customer,
      ),
    );
  }

  /// `GET /v1/stripe/customers/:customerId`
  Future<ApiResponse<StripeCustomer>> getCustomer(String customerId) {
    _requireNonEmpty(customerId, 'customerId');
    return withPaymentErrors(
      () => _client.get<StripeCustomer>(
        '/stripe/customers/${encodeSegment(customerId)}',
        decoder: _customer,
      ),
    );
  }

  /// `POST /v1/stripe/setup-intents` — saves a payment method for later use.
  Future<ApiResponse<StripeSetupIntent>> createSetupIntent({
    String? stripeCustomerId,
    StripeSetupIntentUsage? usage,
  }) {
    return withPaymentErrors(
      () => _client.post<StripeSetupIntent>(
        '/stripe/setup-intents',
        body: <String, dynamic>{
          if (stripeCustomerId != null) 'stripe_customer_id': stripeCustomerId,
          if (usage != null) 'usage': usage.wireValue,
        },
        decoder: (data) => StripeSetupIntent.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /v1/stripe/checkout-sessions` — creates a hosted checkout session.
  Future<ApiResponse<StripeCheckoutSession>> createCheckoutSession({
    required StripeCheckoutMode mode,
    required List<LineItemInput> lineItems,
    required String successUrl,
    required String cancelUrl,
    String? customerId,
    Map<String, String>? metadata,
  }) {
    if (lineItems.isEmpty) {
      throw const ValidationError(
        'Superso: a checkout session requires at least one line item.',
      );
    }
    _requireNonEmpty(successUrl, 'successUrl');
    _requireNonEmpty(cancelUrl, 'cancelUrl');
    return withPaymentErrors(
      () => _client.post<StripeCheckoutSession>(
        '/stripe/checkout-sessions',
        body: <String, dynamic>{
          'mode': mode.wireValue,
          'line_items':
              lineItems.map((i) => i.toJson()).toList(growable: false),
          'success_url': successUrl,
          'cancel_url': cancelUrl,
          if (customerId != null) 'customer_id': customerId,
          if (metadata != null) 'metadata': metadata,
        },
        decoder: (data) => StripeCheckoutSession.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// `POST /v1/stripe/refund` — refunds a PaymentIntent.
  ///
  /// [orderId] doubles as the idempotency key, so retrying with the same value
  /// will not double-refund.
  Future<ApiResponse<StripeRefund>> createRefund({
    required String stripePaymentIntentId,
    required String orderId,
    int? amountMinor,
    StripeRefundReason? reason,
  }) {
    _requireNonEmpty(stripePaymentIntentId, 'stripePaymentIntentId');
    _requireNonEmpty(orderId, 'orderId');
    return withPaymentErrors(
      () => _client.post<StripeRefund>(
        '/stripe/refund',
        body: <String, dynamic>{
          'stripe_payment_intent_id': stripePaymentIntentId,
          'order_id': orderId,
          if (amountMinor != null) 'amount_minor': amountMinor,
          if (reason != null) 'reason': reason.wireValue,
        },
        decoder: (data) => StripeRefund.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  static StripePaymentIntent _paymentIntent(Object? data) =>
      StripePaymentIntent.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );

  static StripeCustomer _customer(Object? data) => StripeCustomer.fromJson(
        data as Map<String, dynamic>? ?? const <String, dynamic>{},
      );
}

PaymentResult _result(Object? data) => PaymentResult.fromJson(
      data as Map<String, dynamic>? ?? const <String, dynamic>{},
    );

/// The composition root for the Payment module.
///
/// ```dart
/// // WaafiPay-family charge
/// final result = await superso.payment.purchase(
///   accountNo: '252615000000',
///   amount: 10.50,
/// );
/// if (result.data.isApproved) { /* ... */ }
///
/// // Hosted payment page
/// final hpp = await superso.payment.hpp.purchase(
///   accountNo: '252615000000',
///   amount: 10.50,
/// );
/// launchUrl(Uri.parse(hpp.data.hppUrl!));
///
/// // Stripe
/// final intent = await superso.payment.stripe.createPaymentIntent(
///   amountMinor: 1050,
///   orderId: 'order-123',
/// );
/// // Hand intent.data.clientSecret to flutter_stripe to complete.
/// ```
///
/// Currency is resolved server-side from the merchant's gateway configuration
/// whenever it is omitted, so most callers should not pass it.
class PaymentModule implements SdkModule {
  /// Creates the payment module bound to [client].
  PaymentModule(this.client)
      : gateway = GatewayModule(client),
        hpp = HppModule(client),
        transactions = PaymentTransactionsModule(client),
        stripe = StripeModule(client);

  @override
  final SupersoHttpClient client;

  /// Gateway discovery.
  final GatewayModule gateway;

  /// Hosted Payment Page operations.
  final HppModule hpp;

  /// Transaction record lookup.
  final PaymentTransactionsModule transactions;

  /// Stripe operations.
  final StripeModule stripe;

  /// `POST /v1/payment/purchase` — charges an account immediately.
  Future<ApiResponse<PaymentResult>> purchase({
    required String accountNo,
    required double amount,
    String? currency,
    String? invoiceId,
    String? referenceId,
    String? description,
  }) {
    _requireNonEmpty(accountNo, 'accountNo');
    _requirePositive(amount, 'amount');
    return withPaymentErrors(
      () => client.post<PaymentResult>(
        '/payment/purchase',
        body: <String, dynamic>{
          'account_no': accountNo,
          'amount': amount,
          if (currency != null) 'currency': currency,
          if (invoiceId != null) 'invoice_id': invoiceId,
          if (referenceId != null) 'reference_id': referenceId,
          if (description != null) 'description': description,
        },
        decoder: _result,
      ),
    );
  }

  /// `POST /v1/payment/reversal` — reverses a same-day charge.
  Future<ApiResponse<PaymentResult>> reversal({
    required String transactionId,
    String? description,
  }) {
    _requireNonEmpty(transactionId, 'transactionId');
    return withPaymentErrors(
      () => client.post<PaymentResult>(
        '/payment/reversal',
        body: <String, dynamic>{
          'transaction_id': transactionId,
          if (description != null) 'description': description,
        },
        decoder: _result,
      ),
    );
  }

  /// `POST /v1/payment/preauthorize` — reserves funds without deducting them.
  ///
  /// Follow with [commit] to capture, or [cancel] to release.
  Future<ApiResponse<PaymentResult>> preauthorize({
    required String accountNo,
    required double amount,
    String? currency,
    String? referenceId,
    String? description,
  }) {
    _requireNonEmpty(accountNo, 'accountNo');
    _requirePositive(amount, 'amount');
    return withPaymentErrors(
      () => client.post<PaymentResult>(
        '/payment/preauthorize',
        body: <String, dynamic>{
          'account_no': accountNo,
          'amount': amount,
          if (currency != null) 'currency': currency,
          if (referenceId != null) 'reference_id': referenceId,
          if (description != null) 'description': description,
        },
        decoder: _result,
      ),
    );
  }

  /// `POST /v1/payment/commit` — captures a preauthorized hold.
  Future<ApiResponse<PaymentResult>> commit({
    required String transactionId,
    String? description,
  }) {
    _requireNonEmpty(transactionId, 'transactionId');
    return withPaymentErrors(
      () => client.post<PaymentResult>(
        '/payment/commit',
        body: <String, dynamic>{
          'transaction_id': transactionId,
          if (description != null) 'description': description,
        },
        decoder: _result,
      ),
    );
  }

  /// `POST /v1/payment/cancel` — releases a preauthorized hold.
  Future<ApiResponse<PaymentResult>> cancel({
    required String transactionId,
    String? description,
  }) {
    _requireNonEmpty(transactionId, 'transactionId');
    return withPaymentErrors(
      () => client.post<PaymentResult>(
        '/payment/cancel',
        body: <String, dynamic>{
          'transaction_id': transactionId,
          if (description != null) 'description': description,
        },
        decoder: _result,
      ),
    );
  }

  /// `GET /v1/payment/status` — looks up an operation's current outcome.
  ///
  /// Supply either [referenceId] or [transactionId].
  Future<ApiResponse<PaymentResult>> status({
    String? referenceId,
    String? transactionId,
  }) {
    if ((referenceId == null || referenceId.isEmpty) &&
        (transactionId == null || transactionId.isEmpty)) {
      throw const ValidationError(
        'Superso: a status lookup needs either a referenceId or a '
        'transactionId.',
      );
    }
    return withPaymentErrors(
      () => client.get<PaymentResult>(
        '/payment/status',
        options: RequestOptions(
          query: <String, Object?>{
            'reference_id': referenceId,
            'transaction_id': transactionId,
          },
        ),
        decoder: _result,
      ),
    );
  }

  /// An alias of `transactions.get`.
  Future<ApiResponse<PaymentTransaction>> transaction(String transactionId) =>
      transactions.get(transactionId);

  /// Polls [status] until the result reaches a terminal state.
  ///
  /// Completes with the first non-pending result, or throws a
  /// [PaymentError] once [timeout] elapses. No JavaScript counterpart in this
  /// shape — the JS SDK exposes a callback-based poller — but a `Future` is
  /// what a Dart caller awaiting a payment actually wants.
  Future<PaymentResult> waitForCompletion({
    String? referenceId,
    String? transactionId,
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await status(
        referenceId: referenceId,
        transactionId: transactionId,
      );
      if (response.data.status.isTerminal) return response.data;
      await Future<void>.delayed(interval);
    }
    throw PaymentError(
      'Superso: the payment did not reach a final state within '
      '${timeout.inSeconds}s. It may still complete — check its status again '
      'rather than re-charging.',
      code: 'PAYMENT_POLL_TIMEOUT',
    );
  }

  /// Emits every polled status until the payment reaches a terminal state.
  ///
  /// Useful for driving a progress UI while a customer completes a hosted
  /// payment page.
  Stream<PaymentResult> watch({
    String? referenceId,
    String? transactionId,
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 5),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await status(
        referenceId: referenceId,
        transactionId: transactionId,
      );
      yield response.data;
      if (response.data.status.isTerminal) return;
      await Future<void>.delayed(interval);
    }
  }
}
