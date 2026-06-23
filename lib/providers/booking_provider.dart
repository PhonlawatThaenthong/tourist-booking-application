import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/mock_data.dart';
import '../models/booking.dart';

class BookingProvider extends ChangeNotifier {
  final List<Booking> _bookings = MockData.bookings();

  List<Booking> get all {
    final sorted = [..._bookings];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  List<Booking> forCustomer(String customerId) =>
      all.where((b) => b.customerId == customerId).toList();

  /// True if an active (non-cancelled) booking already covers the date range
  /// for the given room.
  bool isRoomBooked(String roomId, DateTime checkIn, DateTime checkOut) {
    return _bookings.any((b) =>
        b.roomId == roomId &&
        b.status != BookingStatus.cancelled &&
        b.overlaps(checkIn, checkOut));
  }

  /// Creates a booking. The returned object is mutated later by the payment
  /// flow and by staff actions.
  Booking createBooking({
    required String roomId,
    required String roomName,
    required String customerId,
    required String customerName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
    required double totalPrice,
  }) {
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
    );
    _bookings.add(booking);
    notifyListeners();
    return booking;
  }

  void markPaid(String bookingId) {
    _update(bookingId, (b) => b.paymentStatus = PaymentStatus.paid);
  }

  void approve(String bookingId) {
    _update(bookingId, (b) => b.status = BookingStatus.approved);
  }

  void cancel(String bookingId) {
    _update(bookingId, (b) {
      b.status = BookingStatus.cancelled;
      if (b.paymentStatus == PaymentStatus.paid) {
        b.paymentStatus = PaymentStatus.refunded;
      }
    });
  }

  void reschedule(String bookingId, DateTime checkIn, DateTime checkOut) {
    final i = _bookings.indexWhere((b) => b.id == bookingId);
    if (i == -1) return;
    final old = _bookings[i];
    final nights = checkOut.difference(checkIn).inDays;
    final perNight = old.nights == 0 ? old.totalPrice : old.totalPrice / old.nights;
    _bookings[i] = Booking(
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
    notifyListeners();
  }

  void _update(String id, void Function(Booking) change) {
    final i = _bookings.indexWhere((b) => b.id == id);
    if (i != -1) {
      change(_bookings[i]);
      notifyListeners();
    }
  }

  // ---- Reporting --------------------------------------------------------

  /// Revenue counts paid bookings that have not been refunded.
  double get totalRevenue => _bookings
      .where((b) => b.paymentStatus == PaymentStatus.paid)
      .fold(0.0, (sum, b) => sum + b.totalPrice);

  int get totalBookings => _bookings.length;
  int get pendingCount =>
      _bookings.where((b) => b.status == BookingStatus.pending).length;
  int get approvedCount =>
      _bookings.where((b) => b.status == BookingStatus.approved).length;
  int get cancelledCount =>
      _bookings.where((b) => b.status == BookingStatus.cancelled).length;

  /// Occupancy rate = booked room-nights for the next [windowDays] days divided
  /// by total available room-nights, given [totalRooms].
  double occupancyRate(int totalRooms, {int windowDays = 30}) {
    if (totalRooms == 0) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: windowDays));
    var bookedNights = 0;
    for (final b in _bookings) {
      if (b.status == BookingStatus.cancelled) continue;
      final from = b.checkIn.isAfter(start) ? b.checkIn : start;
      final to = b.checkOut.isBefore(end) ? b.checkOut : end;
      final nights = to.difference(from).inDays;
      if (nights > 0) bookedNights += nights;
    }
    final capacity = totalRooms * windowDays;
    return (bookedNights / capacity).clamp(0, 1).toDouble();
  }
}
