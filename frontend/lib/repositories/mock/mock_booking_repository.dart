import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../models/booking.dart';
import '../booking_repository.dart';
import '../repository_exception.dart';

class MockBookingRepository implements BookingRepository {
  MockBookingRepository() : _bookings = MockData.bookings();

  final List<Booking> _bookings;

  @override
  Future<List<Booking>> fetchBookings() async => List.unmodifiable(_bookings);

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
    // The real backend rejects an overlapping range with 409 (exclusion
    // constraint). The mock reproduces that so the UI error path is exercised
    // before the API exists.
    final clash = _bookings.any((b) =>
        b.roomId == roomId &&
        b.status != BookingStatus.cancelled &&
        b.overlaps(checkIn, checkOut));
    if (clash) {
      throw const RepositoryException(
        'This room is already booked for the selected dates.',
        statusCode: 409,
      );
    }

    final booking = Booking(
      id: 'b-${const Uuid().v4().substring(0, 6).toUpperCase()}',
      roomId: roomId,
      roomName: roomName,
      customerId: customerId,
      customerName: customerName,
      checkIn: checkIn,
      checkOut: checkOut,
      guests: guests,
      totalPrice: totalPrice,
      createdAt: DateTime.now(),
    ); // pending / unpaid — payment is a separate step
    _bookings.add(booking);
    return booking;
  }

  @override
  Future<Booking> cancelBooking(String id) =>
      updateStatus(id, BookingStatus.cancelled);

  @override
  Future<Booking> checkIn(String id) =>
      updateStatus(id, BookingStatus.checkedIn);

  @override
  Future<Booking> checkOut(String id) =>
      updateStatus(id, BookingStatus.checkedOut);

  @override
  Future<Booking> updateStatus(String id, BookingStatus status) async {
    final booking = _bookings[_indexOf(id)];
    booking.status = status;
    if (status == BookingStatus.cancelled &&
        booking.paymentStatus == PaymentStatus.paid) {
      booking.paymentStatus = PaymentStatus.refunded;
    }
    return booking;
  }

  @override
  Future<Booking> reschedule(
    String id,
    DateTime checkIn,
    DateTime checkOut,
  ) async {
    final i = _indexOf(id);
    final old = _bookings[i];
    final nights = checkOut.difference(checkIn).inDays;
    final perNight =
        old.nights == 0 ? old.totalPrice : old.totalPrice / old.nights;
    final updated = Booking(
      id: old.id,
      roomId: old.roomId,
      roomName: old.roomName,
      customerId: old.customerId,
      customerName: old.customerName,
      checkIn: checkIn,
      checkOut: checkOut,
      guests: old.guests,
      totalPrice: perNight * nights,
      status: old.status,
      paymentStatus: old.paymentStatus,
      createdAt: old.createdAt,
    );
    _bookings[i] = updated;
    return updated;
  }

  int _indexOf(String id) {
    final i = _bookings.indexWhere((b) => b.id == id);
    if (i == -1) throw const RepositoryException('Booking not found.');
    return i;
  }
}
