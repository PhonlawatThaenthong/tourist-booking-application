import '../../models/booking.dart';
import '../booking_repository.dart';
import 'api_client.dart';

/// HTTP [BookingRepository] against `/api/bookings` and `/api/staff/bookings`.
class ApiBookingRepository implements BookingRepository {
  ApiBookingRepository(this._api);

  final ApiClient _api;

  /// Customers see their own bookings, staff see every booking — the split the
  /// [BookingRepository] contract already describes.
  /// Both endpoints require a token. The Bloc fires `BookingStarted` while the
  /// app is still on the splash screen, so a signed-out call answers with an
  /// empty list; `main.dart` re-fires the event once authentication settles.
  @override
  Future<List<Booking>> fetchBookings() async {
    if (!_api.isSignedIn) return const [];
    final path = _api.isStaffSide ? '/api/staff/bookings' : '/api/bookings/me';
    final data = await _api.get(path) as List<dynamic>;
    return data
        .map((e) => bookingFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `POST /api/bookings` — creates a PENDING/UNPAID booking. Payment (QR slip
  /// upload + staff confirmation) is a separate flow via [PaymentRepository].
  ///
  /// `roomName`, `customerId`, `customerName` and `totalPrice` are deliberately
  /// NOT sent: the API recomputes the price from the stored nightly rate inside
  /// the booking transaction and takes the customer from the JWT. Sending them
  /// would be rejected outright by `forbidNonWhitelisted`.
  ///
  /// A 409 (the room was taken in the meantime) propagates as a
  /// [RepositoryException] with `statusCode: 409`.
  @override
  Future<Booking> createBooking({
    required String roomId,
    required String roomName,
    required String customerId,
    required String customerName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
    required double totalPrice,
  }) async {
    final created =
        await _api.post(
              '/api/bookings',
              body: {
                'roomId': roomId,
                'checkIn': ymd(checkIn),
                'checkOut': ymd(checkOut),
                'guests': guests,
              },
            )
            as Map<String, dynamic>;
    return bookingFromJson(created);
  }

  @override
  Future<Booking> cancelBooking(String id) async {
    final data = await _api.post('/api/bookings/$id/cancel');
    return bookingFromJson(data as Map<String, dynamic>);
  }

  @override
  Future<Booking> checkIn(String id) async {
    final data = await _api.post('/api/staff/bookings/$id/check-in');
    return bookingFromJson(data as Map<String, dynamic>);
  }

  @override
  Future<Booking> checkOut(String id) async {
    final data = await _api.post('/api/staff/bookings/$id/check-out');
    return bookingFromJson(data as Map<String, dynamic>);
  }

  @override
  Future<Booking> updateStatus(String id, BookingStatus status) async {
    final data = await _api.patch(
      '/api/staff/bookings/$id',
      body: {'status': status.wireName},
    );
    return bookingFromJson(data as Map<String, dynamic>);
  }

  /// The API re-prices from the stored nightly rate, so no total is sent.
  @override
  Future<Booking> reschedule(
    String id,
    DateTime checkIn,
    DateTime checkOut,
  ) async {
    final data = await _api.patch(
      '/api/staff/bookings/$id',
      body: {'checkIn': ymd(checkIn), 'checkOut': ymd(checkOut)},
    );
    return bookingFromJson(data as Map<String, dynamic>);
  }
}

Booking bookingFromJson(Map<String, dynamic> json) {
  return Booking(
    id: json['id'] as String,
    roomId: json['roomId'] as String,
    roomName: (json['roomName'] as String?) ?? '',
    customerId: json['customerId'] as String,
    customerName: (json['customerName'] as String?) ?? '',
    // 'YYYY-MM-DD' parses to local midnight, which is what the calendar
    // screens compare against.
    checkIn: DateTime.parse(json['checkIn'] as String),
    checkOut: DateTime.parse(json['checkOut'] as String),
    guests: (json['guests'] as num).toInt(),
    totalPrice: (json['totalPrice'] as num).toDouble(),
    status: BookingStatus.values.firstWhere(
      (s) => s.wireName == json['status'],
      orElse: () => BookingStatus.pending,
    ),
    paymentStatus: PaymentStatus.values.firstWhere(
      (s) => s.name == json['paymentStatus'],
      orElse: () => PaymentStatus.unpaid,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );
}
