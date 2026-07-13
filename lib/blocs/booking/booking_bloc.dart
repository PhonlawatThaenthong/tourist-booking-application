import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../models/booking.dart';
import 'booking_event.dart';
import 'booking_state.dart';

class BookingBloc extends Bloc<BookingEvent, BookingState> {
  BookingBloc() : super(const BookingState()) {
    on<BookingStarted>(_onStarted);
    on<BookingCreateAndPayRequested>(_onCreateAndPay);
    on<BookingApproveRequested>(_onApprove);
    on<BookingCancelRequested>(_onCancel);
    on<BookingRescheduleRequested>(_onReschedule);
  }

  List<Booking> get all {
    final sorted = [...state.bookings];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  List<Booking> forCustomer(String customerId) =>
      all.where((b) => b.customerId == customerId).toList();

  /// True if an active (non-cancelled) booking already covers the date range
  /// for the given room.
  bool isRoomBooked(String roomId, DateTime checkIn, DateTime checkOut) {
    return state.bookings.any((b) =>
        b.roomId == roomId &&
        b.status != BookingStatus.cancelled &&
        b.overlaps(checkIn, checkOut));
  }

  // ---- Reporting --------------------------------------------------------

  /// Revenue counts paid bookings that have not been refunded.
  double get totalRevenue => state.bookings
      .where((b) => b.paymentStatus == PaymentStatus.paid)
      .fold(0.0, (sum, b) => sum + b.totalPrice);

  int get totalBookings => state.bookings.length;
  int get pendingCount =>
      state.bookings.where((b) => b.status == BookingStatus.pending).length;
  int get approvedCount =>
      state.bookings.where((b) => b.status == BookingStatus.approved).length;
  int get cancelledCount =>
      state.bookings.where((b) => b.status == BookingStatus.cancelled).length;

  /// Occupancy rate = booked room-nights for the next [windowDays] days divided
  /// by total available room-nights, given [totalRooms].
  double occupancyRate(int totalRooms, {int windowDays = 30}) {
    if (totalRooms == 0) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: windowDays));
    var bookedNights = 0;
    for (final b in state.bookings) {
      if (b.status == BookingStatus.cancelled) continue;
      final from = b.checkIn.isAfter(start) ? b.checkIn : start;
      final to = b.checkOut.isBefore(end) ? b.checkOut : end;
      final nights = to.difference(from).inDays;
      if (nights > 0) bookedNights += nights;
    }
    final capacity = totalRooms * windowDays;
    return (bookedNights / capacity).clamp(0, 1).toDouble();
  }

  void _onStarted(BookingStarted event, Emitter<BookingState> emit) {
    emit(state.copyWith(bookings: MockData.bookings()));
  }

  void _onCreateAndPay(
    BookingCreateAndPayRequested event,
    Emitter<BookingState> emit,
  ) {
    final booking = Booking(
      id: 'b-${const Uuid().v4().substring(0, 6).toUpperCase()}',
      roomId: event.roomId,
      roomName: event.roomName,
      customerId: event.customerId,
      customerName: event.customerName,
      checkIn: event.checkIn,
      checkOut: event.checkOut,
      guests: event.guests,
      totalPrice: event.totalPrice,
      createdAt: DateTime.now(),
    )..paymentStatus = PaymentStatus.paid;
    emit(state.copyWith(
      bookings: [...state.bookings, booking],
      lastCreatedBooking: booking,
    ));
  }

  void _onApprove(BookingApproveRequested event, Emitter<BookingState> emit) {
    _update(event.bookingId, (b) => b.status = BookingStatus.approved, emit);
  }

  void _onCancel(BookingCancelRequested event, Emitter<BookingState> emit) {
    _update(event.bookingId, (b) {
      b.status = BookingStatus.cancelled;
      if (b.paymentStatus == PaymentStatus.paid) {
        b.paymentStatus = PaymentStatus.refunded;
      }
    }, emit);
  }

  void _onReschedule(
    BookingRescheduleRequested event,
    Emitter<BookingState> emit,
  ) {
    final i = state.bookings.indexWhere((b) => b.id == event.bookingId);
    if (i == -1) return;
    final old = state.bookings[i];
    final nights = event.checkOut.difference(event.checkIn).inDays;
    final perNight =
        old.nights == 0 ? old.totalPrice : old.totalPrice / old.nights;
    final updated = Booking(
      id: old.id,
      roomId: old.roomId,
      roomName: old.roomName,
      customerId: old.customerId,
      customerName: old.customerName,
      checkIn: event.checkIn,
      checkOut: event.checkOut,
      guests: old.guests,
      totalPrice: perNight * nights,
      status: old.status,
      paymentStatus: old.paymentStatus,
      createdAt: old.createdAt,
    );
    final bookings = [...state.bookings];
    bookings[i] = updated;
    emit(state.copyWith(bookings: bookings));
  }

  void _update(
    String id,
    void Function(Booking) change,
    Emitter<BookingState> emit,
  ) {
    final i = state.bookings.indexWhere((b) => b.id == id);
    if (i != -1) {
      change(state.bookings[i]);
      emit(state.copyWith(bookings: [...state.bookings]));
    }
  }
}
