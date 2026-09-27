abstract class BookingEvent {
  const BookingEvent();
}

class BookingStarted extends BookingEvent {
  const BookingStarted();
}

/// Creates a PENDING/UNPAID booking. Payment (QR slip upload + staff
/// confirmation) happens afterwards through the payment flow.
class BookingCreateRequested extends BookingEvent {
  final String roomId;
  final String roomName;
  final String customerId;
  final String customerName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final double totalPrice;

  const BookingCreateRequested({
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

/// Front desk marking the guest as arrived.
class BookingCheckInRequested extends BookingEvent {
  final String bookingId;
  const BookingCheckInRequested(this.bookingId);
}

/// Front desk marking the guest as departed, which closes the booking.
class BookingCheckOutRequested extends BookingEvent {
  final String bookingId;
  const BookingCheckOutRequested(this.bookingId);
}

/// The customer cancelling their own booking. Separate from
/// [BookingCancelRequested], which goes through the staff-only endpoint.
class BookingCustomerCancelRequested extends BookingEvent {
  final String bookingId;
  const BookingCustomerCancelRequested(this.bookingId);
}

class BookingRescheduleRequested extends BookingEvent {
  final String bookingId;
  final DateTime checkIn;
  final DateTime checkOut;
  const BookingRescheduleRequested(this.bookingId, this.checkIn, this.checkOut);
}
