import 'dart:typed_data';

import '../models/payment.dart';

/// Data access for the manual QR-slip payment flow.
///
/// Backend endpoints:
///  * `GET  /api/payment/info`                 — [fetchInfo]
///  * `POST /api/bookings/:id/pay` (multipart)  — [uploadSlip]
///  * `GET  /api/bookings/:id/payment`          — [fetchForBooking]
///  * `GET  /api/staff/payments?status=`        — [fetchPending]
///  * `GET  /api/staff/payments/:id/slip`       — [fetchSlipBytes]
///  * `PATCH /api/staff/payments/:id`           — [verify]
abstract class PaymentRepository {
  /// The resort's PromptPay account details shown to the customer.
  Future<PaymentInfo> fetchInfo();

  /// Absolute URL of a dynamic PromptPay QR image with [amount] embedded
  /// (backend renders it via promptpay-qr). Empty string in mock mode.
  String qrUrl(double amount);

  /// Uploads a transfer slip for a booking. Moves the payment to
  /// `awaiting_verification`; it does NOT mark the booking paid.
  Future<PaymentView> uploadSlip({
    required String bookingId,
    required List<int> bytes,
    required String filename,
  });

  /// The customer's current payment state for a booking, or null if none yet.
  Future<PaymentView?> fetchForBooking(String bookingId);

  /// Back office: payments, optionally filtered by status
  /// (e.g. `awaiting_verification`).
  Future<List<StaffPayment>> fetchPending({String? status});

  /// Back office: the raw slip image bytes for staff to inspect.
  Future<Uint8List> fetchSlipBytes(String paymentId);

  /// Back office: confirm or reject an uploaded slip.
  Future<StaffPayment> verify(
    String paymentId, {
    required bool approve,
    String? reason,
  });
}
