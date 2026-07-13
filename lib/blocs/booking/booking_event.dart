abstract class BookingEvent {
  const BookingEvent();
}

class BookingStarted extends BookingEvent {
  const BookingStarted();
}

/// Creates a booking and marks it paid in one step, run only after the
/// (simulated) payment charge succeeds.
class BookingCreateAndPayRequested extends BookingEvent {
  final String roomId;
  final String roomName;
  final String customerId;
  final String customerName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final double totalPrice;

  const BookingCreateAndPayRequested({
    required this.roomId,
    required this.roomName,
    required this.customerId,
    required this.customerName,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.totalPrice,
  });
}

class BookingApproveRequested extends BookingEvent {
  final String bookingId;
  const BookingApproveRequested(this.bookingId);
}

class BookingCancelRequested extends BookingEvent {
  final String bookingId;
  const BookingCancelRequested(this.bookingId);
}

class BookingRescheduleRequested extends BookingEvent {
  final String bookingId;
  final DateTime checkIn;
  final DateTime checkOut;
  const BookingRescheduleRequested(this.bookingId, this.checkIn, this.checkOut);
}
