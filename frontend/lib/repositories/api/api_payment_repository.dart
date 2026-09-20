import 'dart:typed_data';

import '../../models/payment.dart';
import '../payment_repository.dart';
import '../repository_exception.dart';
import 'api_client.dart';

/// HTTP [PaymentRepository] for the manual QR-slip flow.
class ApiPaymentRepository implements PaymentRepository {
  ApiPaymentRepository(this._api);

  final ApiClient _api;

  @override
  Future<PaymentInfo> fetchInfo() async {
    // Public endpoint — no token needed, and the QR must load before login too.
    final data = await _api.get('/api/payment/info', auth: false)
        as Map<String, dynamic>;
    final rel = (data['qrImageUrl'] as String?) ?? '';
    return PaymentInfo(
      accountName: (data['accountName'] as String?) ?? '',
      promptPayId: (data['promptPayId'] as String?) ?? '',
      note: (data['note'] as String?) ?? '',
      // The API returns a relative path; make it absolute for Image.network.
      qrImageUrl: rel.isEmpty ? '' : '${_api.baseUrl}$rel',
      holdMinutes: (data['holdMinutes'] as num?)?.toInt() ?? 3,
    );
  }

  @override
  String qrUrl(double amount) =>
      '${_api.baseUrl}/api/payment/qr?amount=${amount.toStringAsFixed(2)}';

  @override
  Future<PaymentView> uploadSlip({
    required String bookingId,
    required List<int> bytes,
    required String filename,
  }) async {
    final data = await _api.multipart(
      '/api/bookings/$bookingId/pay',
      field: 'slip',
      bytes: bytes,
      filename: filename,
    ) as Map<String, dynamic>;
    return PaymentView.fromJson(data);
  }

  @override
  Future<PaymentView?> fetchForBooking(String bookingId) async {
    try {
      final data = await _api.get('/api/bookings/$bookingId/payment')
          as Map<String, dynamic>;
      return PaymentView.fromJson(data);
    } on RepositoryException catch (e) {
      // 404 = no slip uploaded yet; the caller shows the QR instead.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<StaffPayment>> fetchPending({String? status}) async {
    final data = await _api.get(
      '/api/staff/payments',
      query: status == null ? null : {'status': status},
    ) as List<dynamic>;
    return data
        .map((e) => StaffPayment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Uint8List> fetchSlipBytes(String paymentId) {
    return _api.getBytes('/api/staff/payments/$paymentId/slip');
  }

  @override
  Future<StaffPayment> verify(
    String paymentId, {
    required bool approve,
    String? reason,
  }) async {
    final data = await _api.patch('/api/staff/payments/$paymentId', body: {
      'action': approve ? 'approve' : 'reject',
      if (!approve && reason != null) 'reason': reason,
    }) as Map<String, dynamic>;
    return StaffPayment.fromJson(data);
  }
}
