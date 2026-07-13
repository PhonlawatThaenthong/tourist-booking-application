import '../../models/booking.dart';

class BookingState {
  final List<Booking> bookings;

  /// Set only by the event that just created a booking, so screens can react
  /// to it via BlocListener without a return value. Null on every other
  /// transition.
  final Booking? lastCreatedBooking;

  const BookingState({this.bookings = const [], this.lastCreatedBooking});

  BookingState copyWith({
    List<Booking>? bookings,
    Booking? lastCreatedBooking,
  }) {
    return BookingState(
      bookings: bookings ?? this.bookings,
      lastCreatedBooking: lastCreatedBooking,
    );
  }
}
