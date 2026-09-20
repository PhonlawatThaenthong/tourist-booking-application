import 'dart:typed_data';

import '../../models/payment.dart';
import '../payment_repository.dart';
import '../repository_exception.dart';

/// In-memory [PaymentRepository] for offline/demo mode. Self-contained: it does
/// not sync with MockBookingRepository (mock mode is only for running the UI
/// without the API).
class MockPaymentRepository implements PaymentRepository {
  final Map<String, _MockPayment> _byBooking = {};
  int _seq = 0;

  // A 1x1 transparent PNG, so the admin "view slip" preview has something.
  static final Uint8List _placeholderPng = Uint8List.fromList(<int>[
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
    0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
    120, 156, 99, 250, 207, 0, 0, 3, 1, 1, 0, 24, 221, 141, 219, 0, 0, 0, 0,
    73, 69, 78, 68, 174, 66, 96, 130,
  ]);

  @override
  Future<PaymentInfo> fetchInfo() async => const PaymentInfo(
        accountName: 'Poonsuk Resort',
        promptPayId: '000-000-0000',
        note: 'สแกน QR แล้วโอนตามยอด จากนั้นอัปโหลดสลิปเพื่อรอเจ้าหน้าที่ยืนยัน',
        qrImageUrl: '',
        holdMinutes: 3,
      );

  @override
  String qrUrl(double amount) => '';

  @override
  Future<PaymentView> uploadSlip({
    required String bookingId,
    required List<int> bytes,
    required String filename,
  }) async {
    final existing = _byBooking[bookingId];
    final p = existing ??
        _MockPayment(
          id: 'pay-${(++_seq).toString().padLeft(4, '0')}',
          bookingId: bookingId,
          amount: 0,
        );
    p.status = PaymentState.awaitingVerification;
    p.hasSlip = true;
    p.slipUploadedAt = DateTime.now();
    p.rejectReason = null;
    _byBooking[bookingId] = p;
    return p.toView();
  }

  @override
  Future<PaymentView?> fetchForBooking(String bookingId) async =>
      _byBooking[bookingId]?.toView();

  @override
  Future<List<StaffPayment>> fetchPending({String? status}) async {
    return _byBooking.values
        .where((p) => status == null || p.status == paymentStateFromString(status))
        .map((p) => p.toStaff())
        .toList(growable: false);
  }

  @override
  Future<Uint8List> fetchSlipBytes(String paymentId) async {
    if (!_byBooking.values.any((p) => p.id == paymentId)) {
      throw const RepositoryException('Slip not found.', statusCode: 404);
    }
    return _placeholderPng;
  }

  @override
  Future<StaffPayment> verify(
    String paymentId, {
    required bool approve,
    String? reason,
  }) async {
    final p = _byBooking.values.firstWhere(
      (x) => x.id == paymentId,
      orElse: () =>
          throw const RepositoryException('Payment not found.', statusCode: 404),
    );
    if (approve) {
      p.status = PaymentState.succeeded;
      p.rejectReason = null;
    } else {
      p.status = PaymentState.rejected;
      p.rejectReason = reason;
    }
    return p.toStaff();
  }
}

class _MockPayment {
  _MockPayment({required this.id, required this.bookingId, required this.amount});

  final String id;
  final String bookingId;
  double amount;
  PaymentState status = PaymentState.pending;
  bool hasSlip = false;
  DateTime? slipUploadedAt;
  String? rejectReason;

  PaymentView toView() => PaymentView(
        id: id,
        bookingId: bookingId,
        amount: amount,
        method: 'promptpay',
        status: status,
        hasSlip: hasSlip,
        slipUploadedAt: slipUploadedAt,
        rejectReason: rejectReason,
      );

  StaffPayment toStaff() => StaffPayment(
        id: id,
        bookingId: bookingId,
        amount: amount,
        method: 'promptpay',
        status: status,
        hasSlip: hasSlip,
        slipUploadedAt: slipUploadedAt,
        rejectReason: rejectReason,
        customerId: '',
        customerName: 'Mock customer',
        roomName: 'Mock room',
        createdAt: slipUploadedAt,
      );
}
