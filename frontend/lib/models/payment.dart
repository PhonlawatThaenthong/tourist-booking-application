/// Lifecycle of a payment in the manual QR-slip flow. Mirrors
/// `payments_status_enum` in the backend.
enum PaymentState {
  pending, // row exists, no slip yet
  awaitingVerification, // slip uploaded, waiting for staff
  succeeded, // staff confirmed
  rejected, // staff rejected — customer may re-upload
  refunded,
  failed,
}

PaymentState paymentStateFromString(String? value) {
  switch (value) {
    case 'awaiting_verification':
      return PaymentState.awaitingVerification;
    case 'succeeded':
      return PaymentState.succeeded;
    case 'rejected':
      return PaymentState.rejected;
    case 'refunded':
      return PaymentState.refunded;
    case 'failed':
      return PaymentState.failed;
    default:
      return PaymentState.pending;
  }
}

extension PaymentStateX on PaymentState {
  String get label {
    switch (this) {
      case PaymentState.pending:
        return 'Awaiting payment';
      case PaymentState.awaitingVerification:
        return 'Awaiting verification';
      case PaymentState.succeeded:
        return 'Confirmed';
      case PaymentState.rejected:
        return 'Rejected';
      case PaymentState.refunded:
        return 'Refunded';
      case PaymentState.failed:
        return 'Failed';
    }
  }
}

/// The resort's static PromptPay QR + account details. Backend:
/// `GET /api/payment/info`.
class PaymentInfo {
  final String accountName;
  final String promptPayId;
  final String note;

  /// Absolute URL to the QR image (public, no auth). Empty in mock mode.
  final String qrImageUrl;

  /// Minutes an unpaid booking holds its room (drives the payment countdown).
  final int holdMinutes;

  const PaymentInfo({
    required this.accountName,
    required this.promptPayId,
    required this.note,
    required this.qrImageUrl,
    this.holdMinutes = 3,
  });
}

/// A customer's view of their own payment. Backend:
/// `POST /api/bookings/:id/pay`, `GET /api/bookings/:id/payment`.
class PaymentView {
  final String id;
  final String bookingId;
  final double amount;
  final String method;
  final PaymentState status;
  final bool hasSlip;
  final DateTime? slipUploadedAt;
  final String? rejectReason;

  const PaymentView({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.method,
    required this.status,
    required this.hasSlip,
    this.slipUploadedAt,
    this.rejectReason,
  });

  factory PaymentView.fromJson(Map<String, dynamic> json) {
    return PaymentView(
      id: (json['id'] as String?) ?? '',
      bookingId: json['bookingId'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      method: (json['method'] as String?) ?? 'promptpay',
      status: paymentStateFromString(json['status'] as String?),
      hasSlip: (json['hasSlip'] as bool?) ?? false,
      slipUploadedAt: _parseDate(json['slipUploadedAt']),
      rejectReason: json['rejectReason'] as String?,
    );
  }
}

/// The back-office view of a payment. Backend: `GET /api/staff/payments`.
class StaffPayment {
  final String id;
  final String bookingId;
  final double amount;
  final String method;
  final PaymentState status;
  final bool hasSlip;
  final DateTime? slipUploadedAt;
  final String? rejectReason;
  final String customerId;
  final String customerName;
  final String roomName;
  final String? checkIn;
  final String? checkOut;
  final DateTime? verifiedAt;
  final DateTime? createdAt;

  const StaffPayment({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.method,
    required this.status,
    required this.hasSlip,
    this.slipUploadedAt,
    this.rejectReason,
    required this.customerId,
    required this.customerName,
    required this.roomName,
    this.checkIn,
    this.checkOut,
    this.verifiedAt,
    this.createdAt,
  });

  factory StaffPayment.fromJson(Map<String, dynamic> json) {
    return StaffPayment(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      method: (json['method'] as String?) ?? 'promptpay',
      status: paymentStateFromString(json['status'] as String?),
      hasSlip: (json['hasSlip'] as bool?) ?? false,
      slipUploadedAt: _parseDate(json['slipUploadedAt']),
      rejectReason: json['rejectReason'] as String?,
      customerId: (json['customerId'] as String?) ?? '',
      customerName: (json['customerName'] as String?) ?? '',
      roomName: (json['roomName'] as String?) ?? '',
      checkIn: json['checkIn'] as String?,
      checkOut: json['checkOut'] as String?,
      verifiedAt: _parseDate(json['verifiedAt']),
      createdAt: _parseDate(json['createdAt']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}
