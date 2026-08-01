/// Domain models for the Payment module, mirrored from
/// `docs/payment-gateways/waafipay.md` and `stripe.md`.
///
/// Dart port of `supersosdk/src/payment/{types,enums,requests,responses}.ts`.
library;

import 'package:meta/meta.dart';

/// The gateways the platform can dispatch to.
///
/// The backend's `/v1/payment/*` routes are gateway-agnostic and dispatch
/// internally to whichever gateway the project has configured, so nothing in
/// this module's public surface is WaafiPay-specific.
enum PaymentGatewayName {
  /// WaafiPay.
  waafipay('waafipay'),

  /// Stripe.
  stripe('stripe');

  const PaymentGatewayName(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, returning `null` for anything unrecognized.
  static PaymentGatewayName? fromWire(String? value) {
    for (final gateway in values) {
      if (gateway.wireValue == value) return gateway;
    }
    return null;
  }
}

/// Whether a gateway is in test or live mode.
enum PaymentEnvironment {
  /// Test mode.
  sandbox('sandbox'),

  /// Live mode.
  production('production');

  const PaymentEnvironment(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [sandbox] for anything unrecognized.
  static PaymentEnvironment fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => PaymentEnvironment.sandbox,
      );
}

/// The kind of operation a transaction records.
enum PaymentOperation {
  /// A charge.
  purchase('purchase'),

  /// A same-day reversal of a charge.
  reversal('reversal'),

  /// A refund of a settled charge.
  refund('refund'),

  /// A hold placed on funds.
  preauthorize('preauthorize'),

  /// Capture of a held amount.
  commit('commit'),

  /// Release of a hold.
  cancel('cancel'),

  /// A hosted-payment-page charge.
  hppPurchase('hpp_purchase');

  const PaymentOperation(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [purchase] for anything unrecognized.
  static PaymentOperation fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => PaymentOperation.purchase,
      );
}

/// The outcome of a payment operation.
enum PaymentStatus {
  /// The gateway accepted the operation.
  approved('approved'),

  /// The gateway rejected it.
  declined('declined'),

  /// Awaiting customer action or gateway settlement.
  pending('pending');

  const PaymentStatus(this.wireValue);

  /// The value received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [pending] for anything unrecognized.
  ///
  /// Defaulting to [pending] rather than [declined] is deliberate: an
  /// unrecognized status must never be mistaken for a definitive failure, or a
  /// caller could refund or re-charge against a payment that actually
  /// succeeded.
  static PaymentStatus fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => PaymentStatus.pending,
      );

  /// Whether this status is final — no further transition is expected.
  bool get isTerminal => this != PaymentStatus.pending;
}

/// Stripe PaymentIntent lifecycle status.
enum StripePaymentIntentStatus {
  /// Needs a payment method attached.
  requiresPaymentMethod('requires_payment_method'),

  /// Needs confirmation.
  requiresConfirmation('requires_confirmation'),

  /// Needs customer action, e.g. 3-D Secure.
  requiresAction('requires_action'),

  /// Being processed.
  processing('processing'),

  /// Authorized and awaiting capture.
  requiresCapture('requires_capture'),

  /// Completed successfully.
  succeeded('succeeded'),

  /// Cancelled.
  canceled('canceled');

  const StripePaymentIntentStatus(this.wireValue);

  /// The value received from Stripe.
  final String wireValue;

  /// Parses a wire value, defaulting to [processing] for anything
  /// unrecognized.
  static StripePaymentIntentStatus fromWire(String? value) =>
      values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => StripePaymentIntentStatus.processing,
      );
}

/// When a Stripe PaymentIntent captures funds.
enum StripeCaptureMethod {
  /// Captured as soon as it is authorized.
  automatic('automatic'),

  /// Held until an explicit capture call.
  manual('manual');

  const StripeCaptureMethod(this.wireValue);

  /// The value sent to Stripe.
  final String wireValue;
}

/// How a saved payment method will be used later.
enum StripeSetupIntentUsage {
  /// Charged when the customer is not present. Triggers stronger upfront
  /// authentication, because the bank cannot be asked again later.
  offSession('off_session'),

  /// Charged while the customer is present.
  onSession('on_session');

  const StripeSetupIntentUsage(this.wireValue);

  /// The value sent to Stripe.
  final String wireValue;
}

/// What a Stripe Checkout Session collects.
enum StripeCheckoutMode {
  /// A one-time payment.
  payment('payment'),

  /// A subscription.
  subscription('subscription'),

  /// A payment method, without charging.
  setup('setup');

  const StripeCheckoutMode(this.wireValue);

  /// The value sent to Stripe.
  final String wireValue;
}

/// Why a Stripe refund was issued.
enum StripeRefundReason {
  /// The charge was a duplicate.
  duplicate('duplicate'),

  /// The charge was fraudulent.
  fraudulent('fraudulent'),

  /// The customer asked for it.
  customerRequest('customer_request');

  const StripeRefundReason(this.wireValue);

  /// The value sent to Stripe.
  final String wireValue;
}

/// The result of any WaafiPay-family payment operation.
@immutable
class PaymentResult {
  /// Creates a payment result.
  const PaymentResult({
    required this.status,
    required this.raw,
    this.transactionId,
    this.referenceId,
    this.orderId,
    this.amount,
    this.currency,
    this.accountNo,
    this.hppUrl,
    this.directPaymentLink,
    this.description,
    this.providerResponseCode,
    this.providerErrorCode,
    this.httpStatus,
  });

  /// Decodes a payment result from JSON.
  factory PaymentResult.fromJson(Map<String, dynamic> json) => PaymentResult(
        status: PaymentStatus.fromWire(json['status'] as String?),
        raw: json,
        transactionId: json['transaction_id'] as String?,
        referenceId: json['reference_id'] as String?,
        orderId: json['order_id'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        accountNo: json['phone'] as String?,
        hppUrl: json['hpp_url'] as String?,
        directPaymentLink: json['direct_payment_link'] as String?,
        description: json['description'] as String?,
        providerResponseCode: json['provider_response_code'] as String?,
        providerErrorCode: json['provider_error_code'] as String?,
        httpStatus: (json['http_status'] as num?)?.toInt(),
      );

  /// The outcome.
  final PaymentStatus status;

  /// The gateway's transaction identifier.
  final String? transactionId;

  /// The reference supplied on the originating request.
  final String? referenceId;

  /// The merchant order identifier.
  final String? orderId;

  /// The amount transacted.
  final double? amount;

  /// The ISO 4217 currency.
  final String? currency;

  /// The wallet or phone number charged.
  final String? accountNo;

  /// The hosted payment page URL. Present only for HPP purchases.
  final String? hppUrl;

  /// A direct payment link, when the gateway returns one. HPP purchases only.
  final String? directPaymentLink;

  /// The gateway's description of the outcome.
  final String? description;

  /// The gateway's own response code, verbatim — e.g. `2001`, `5001`.
  ///
  /// Present even on declines and failures. Inspect this rather than [raw] to
  /// distinguish a generic decline from a specific business-rule rejection.
  final String? providerResponseCode;

  /// The gateway's own error code, verbatim — e.g. `E10101`.
  final String? providerErrorCode;

  /// The HTTP status of the gateway call itself.
  ///
  /// WaafiPay normally returns 200 even for business-logic declines, so a
  /// non-200 value here usually indicates a transport or authentication
  /// failure rather than an ordinary decline.
  final int? httpStatus;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  /// Whether the gateway approved this operation.
  bool get isApproved => status == PaymentStatus.approved;

  @override
  String toString() =>
      'PaymentResult(${status.wireValue}, txn: $transactionId, '
      'code: $providerResponseCode)';
}

/// A persisted payment transaction record.
@immutable
class PaymentTransaction {
  /// Creates a transaction record.
  const PaymentTransaction({
    required this.id,
    required this.projectId,
    required this.gateway,
    required this.operation,
    required this.referenceId,
    required this.transactionId,
    required this.orderId,
    required this.currency,
    required this.raw,
    this.gatewayId,
    this.amount,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes a transaction from JSON.
  factory PaymentTransaction.fromJson(Map<String, dynamic> json) =>
      PaymentTransaction(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        gateway: json['gateway'] as String? ?? '',
        operation: PaymentOperation.fromWire(json['operation'] as String?),
        referenceId: json['reference_id'] as String? ?? '',
        transactionId: json['transaction_id'] as String? ?? '',
        orderId: json['order_id'] as String? ?? '',
        currency: json['currency'] as String? ?? '',
        raw: json,
        gatewayId: json['gateway_id'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        status: json['status'] == null
            ? null
            : PaymentStatus.fromWire(json['status'] as String?),
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  /// Record identifier.
  final String id;

  /// Owning project.
  final String projectId;

  /// The configured gateway record used.
  final String? gatewayId;

  /// The gateway name.
  final String gateway;

  /// What operation this records.
  final PaymentOperation operation;

  /// The reference supplied on the originating request.
  final String referenceId;

  /// The gateway's transaction identifier.
  final String transactionId;

  /// The merchant order identifier.
  final String orderId;

  /// The amount transacted.
  final double? amount;

  /// The ISO 4217 currency.
  final String currency;

  /// The recorded outcome.
  final PaymentStatus? status;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 last-update timestamp.
  final String? updatedAt;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'PaymentTransaction($operation, $transactionId, $amount $currency)';
}

/// A project's configured gateway, as returned by gateway discovery.
@immutable
class PaymentGateway {
  /// Creates a gateway record.
  const PaymentGateway({
    required this.gateway,
    required this.raw,
    this.environment,
    this.isActive,
    this.currency,
    this.merchantUid,
  });

  /// Decodes a gateway from JSON.
  factory PaymentGateway.fromJson(Map<String, dynamic> json) => PaymentGateway(
        gateway: json['gateway'] as String? ?? '',
        raw: json,
        environment: json['environment'] == null
            ? null
            : PaymentEnvironment.fromWire(json['environment'] as String?),
        isActive: json['is_active'] as bool? ?? json['active'] as bool?,
        currency: json['currency'] as String?,
        merchantUid: json['merchant_uid'] as String?,
      );

  /// The gateway name.
  final String gateway;

  /// Test or live mode.
  final PaymentEnvironment? environment;

  /// Whether the gateway accepts operations.
  final bool? isActive;

  /// The merchant's configured currency.
  ///
  /// The backend is the single source of truth for currency: omit `currency`
  /// on a payment request and this is what gets used.
  final String? currency;

  /// The merchant identifier registered with the gateway.
  final String? merchantUid;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'PaymentGateway($gateway, ${environment?.wireValue}, $currency)';
}

/// A Stripe PaymentIntent.
@immutable
class StripePaymentIntent {
  /// Creates a PaymentIntent record.
  const StripePaymentIntent({
    required this.id,
    required this.status,
    required this.raw,
    this.clientSecret,
    this.amountMinor,
    this.currency,
    this.orderId,
    this.customerId,
  });

  /// Decodes a PaymentIntent from JSON.
  factory StripePaymentIntent.fromJson(Map<String, dynamic> json) =>
      StripePaymentIntent(
        id: json['id'] as String? ??
            json['stripe_payment_intent_id'] as String? ??
            '',
        status: StripePaymentIntentStatus.fromWire(json['status'] as String?),
        raw: json,
        clientSecret: json['client_secret'] as String?,
        amountMinor: (json['amount_minor'] as num?)?.toInt() ??
            (json['amount'] as num?)?.toInt(),
        currency: json['currency'] as String?,
        orderId: json['order_id'] as String?,
        customerId: json['customer_id'] as String? ??
            json['stripe_customer_id'] as String?,
      );

  /// The Stripe `pi_...` identifier.
  final String id;

  /// Current lifecycle status.
  final StripePaymentIntentStatus status;

  /// The client secret to hand to Stripe's mobile SDK to complete payment.
  ///
  /// This SDK never confirms a PaymentIntent itself — confirmation requires
  /// Stripe's own SDK so card details never touch your server or this package.
  final String? clientSecret;

  /// The amount, in minor units.
  final int? amountMinor;

  /// The ISO 4217 currency.
  final String? currency;

  /// Your own order identifier.
  final String? orderId;

  /// The attached Stripe customer, if any.
  final String? customerId;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'StripePaymentIntent($id, ${status.wireValue}, $amountMinor $currency)';
}

/// A Stripe customer.
@immutable
class StripeCustomer {
  /// Creates a customer record.
  const StripeCustomer({
    required this.id,
    required this.raw,
    this.email,
    this.name,
    this.internalUserId,
  });

  /// Decodes a customer from JSON.
  factory StripeCustomer.fromJson(Map<String, dynamic> json) => StripeCustomer(
        id: json['id'] as String? ??
            json['stripe_customer_id'] as String? ??
            '',
        raw: json,
        email: json['email'] as String?,
        name: json['name'] as String?,
        internalUserId: json['internal_user_id'] as String?,
      );

  /// The Stripe `cus_...` identifier.
  final String id;

  /// The customer's email.
  final String? email;

  /// The customer's name.
  final String? name;

  /// Your own user identifier, stored in Stripe metadata for reconciliation.
  final String? internalUserId;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'StripeCustomer($id, $email)';
}

/// A Stripe SetupIntent, for saving a payment method without charging.
@immutable
class StripeSetupIntent {
  /// Creates a SetupIntent record.
  const StripeSetupIntent({
    required this.id,
    required this.raw,
    this.clientSecret,
    this.status,
    this.customerId,
  });

  /// Decodes a SetupIntent from JSON.
  factory StripeSetupIntent.fromJson(Map<String, dynamic> json) =>
      StripeSetupIntent(
        id: json['id'] as String? ??
            json['stripe_setup_intent_id'] as String? ??
            '',
        raw: json,
        clientSecret: json['client_secret'] as String?,
        status: json['status'] as String?,
        customerId: json['stripe_customer_id'] as String? ??
            json['customer_id'] as String?,
      );

  /// The Stripe `seti_...` identifier.
  final String id;

  /// The client secret to hand to Stripe's mobile SDK.
  final String? clientSecret;

  /// Current status.
  final String? status;

  /// The customer the payment method attaches to.
  final String? customerId;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'StripeSetupIntent($id, $status)';
}

/// A Stripe Checkout Session.
@immutable
class StripeCheckoutSession {
  /// Creates a Checkout Session record.
  const StripeCheckoutSession({
    required this.id,
    required this.raw,
    this.url,
    this.status,
    this.mode,
  });

  /// Decodes a Checkout Session from JSON.
  factory StripeCheckoutSession.fromJson(Map<String, dynamic> json) =>
      StripeCheckoutSession(
        id: json['id'] as String? ??
            json['stripe_session_id'] as String? ??
            '',
        raw: json,
        url: json['url'] as String? ?? json['checkout_url'] as String?,
        status: json['status'] as String?,
        mode: json['mode'] as String?,
      );

  /// The Stripe `cs_...` identifier.
  final String id;

  /// The hosted checkout URL to open in a browser.
  final String? url;

  /// Current status: `open`, `complete`, or `expired`.
  final String? status;

  /// What the session collects.
  final String? mode;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'StripeCheckoutSession($id, $status)';
}

/// A Stripe refund.
@immutable
class StripeRefund {
  /// Creates a refund record.
  const StripeRefund({
    required this.id,
    required this.raw,
    this.status,
    this.amountMinor,
    this.currency,
    this.paymentIntentId,
  });

  /// Decodes a refund from JSON.
  factory StripeRefund.fromJson(Map<String, dynamic> json) => StripeRefund(
        id: json['id'] as String? ?? json['stripe_refund_id'] as String? ?? '',
        raw: json,
        status: json['status'] as String?,
        amountMinor: (json['amount_minor'] as num?)?.toInt() ??
            (json['amount'] as num?)?.toInt(),
        currency: json['currency'] as String?,
        paymentIntentId: json['stripe_payment_intent_id'] as String?,
      );

  /// The Stripe `re_...` identifier.
  final String id;

  /// Current status.
  final String? status;

  /// The refunded amount, in minor units.
  final int? amountMinor;

  /// The ISO 4217 currency.
  final String? currency;

  /// The PaymentIntent that was refunded.
  final String? paymentIntentId;

  /// The complete decoded payload.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'StripeRefund($id, $status, $amountMinor)';
}

/// A single Checkout Session line item.
@immutable
class LineItemInput {
  /// Creates a line item.
  const LineItemInput({required this.priceId, required this.quantity});

  /// The Stripe Price object identifier.
  final String priceId;

  /// How many units.
  final int quantity;

  /// Encodes this line item to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'price_id': priceId,
        'quantity': quantity,
      };
}
