import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/repository_exception.dart';
import 'booking_event.dart';
import 'booking_state.dart';

class BookingBloc extends Bloc<BookingEvent, BookingState> {
  BookingBloc(this._repository) : super(const BookingState()) {
    on<BookingStarted>(_onStarted);
    on<BookingCreateRequested>(_onCreate);
    on<BookingApproveRequested>(_onApprove);
    on<BookingCancelRequested>(_onCancel);
    on<BookingCustomerCancelRequested>(_onCustomerCancel);
    on<BookingCheckInRequested>(_onCheckIn);
    on<BookingCheckOutRequested>(_onCheckOut);
    on<BookingRescheduleRequested>(_onReschedule);
  }

  final BookingRepository _repository;

  List<Booking> get all {
    final sorted = [...state.bookings];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  List<Booking> forCustomer(String customerId) =>
      all.where((b) => b.customerId == customerId).toList();

  /// True if an active (non-cancelled) booking already covers the date range
  /// for the given room.
  ///
  /// Client-side pre-check for the search screen only. The authoritative check
  /// is the exclusion constraint in PostgreSQL — never rely on this to prevent
  /// a double booking.
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
  int get checkedInCount =>
      state.bookings.where((b) => b.status == BookingStatus.checkedIn).length;
  int get checkedOutCount =>
      state.bookings.where((b) => b.status == BookingStatus.checkedOut).length;

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

  // ---- Event handlers ---------------------------------------------------

  Future<void> _onStarted(
    BookingStarted event,
    Emitter<BookingState> emit,
  ) async {
    try {
      emit(state.copyWith(bookings: await _repository.fetchBookings()));
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onCreate(
    BookingCreateRequested event,
    Emitter<BookingState> emit,
  ) async {
    try {
      final booking = await _repository.createBooking(
        roomId: event.roomId,
        roomName: event.roomName,
        customerId: event.customerId,
        customerName: event.customerName,
        checkIn: event.checkIn,
        checkOut: event.checkOut,
        guests: event.guests,
        totalPrice: event.totalPrice,
      );
      emit(state.copyWith(
        bookings: [...state.bookings, booking],
        lastCreatedBooking: booking,
      ));
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onApprove(
    BookingApproveRequested event,
    Emitter<BookingState> emit,
  ) =>
      _transition(event.bookingId, BookingStatus.approved, emit);

  Future<void> _onCancel(
    BookingCancelRequested event,
    Emitter<BookingState> emit,
  ) =>
      _transition(event.bookingId, BookingStatus.cancelled, emit);

  Future<void> _onCustomerCancel(
    BookingCustomerCancelRequested event,
    Emitter<BookingState> emit,
  ) async {
    try {
      _replace(await _repository.cancelBooking(event.bookingId), emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onCheckIn(
    BookingCheckInRequested event,
    Emitter<BookingState> emit,
  ) async {
    try {
      _replace(await _repository.checkIn(event.bookingId), emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onCheckOut(
    BookingCheckOutRequested event,
    Emitter<BookingState> emit,
  ) async {
    try {
      _replace(await _repository.checkOut(event.bookingId), emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onReschedule(
    BookingRescheduleRequested event,
    Emitter<BookingState> emit,
  ) async {
    try {
      final updated = await _repository.reschedule(
        event.bookingId,
        event.checkIn,
        event.checkOut,
      );
      _replace(updated, emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _transition(
    String id,
    BookingStatus status,
    Emitter<BookingState> emit,
  ) async {
    try {
      _replace(await _repository.updateStatus(id, status), emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  void _replace(Booking booking, Emitter<BookingState> emit) {
    final i = state.bookings.indexWhere((b) => b.id == booking.id);
    if (i == -1) return;
    final bookings = [...state.bookings];
    bookings[i] = booking;
    emit(state.copyWith(bookings: bookings));
  }
}
