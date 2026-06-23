enum BookingStatus { pending, approved, cancelled }

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.approved:
        return 'Approved';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }
}

enum PaymentStatus { unpaid, paid, refunded }

extension PaymentStatusX on PaymentStatus {
  String get label {
    switch (this) {
      case PaymentStatus.unpaid:
        return 'Unpaid';
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.refunded:
        return 'Refunded';
    }
  }
}

class Booking {
  final String id;
  final String roomId;
  final String roomName;
  final String customerId;
  final String customerName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final double totalPrice;
  BookingStatus status;
  PaymentStatus paymentStatus;
  final DateTime createdAt;

  Booking({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.customerId,
    required this.customerName,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.totalPrice,
    this.status = BookingStatus.pending,
    this.paymentStatus = PaymentStatus.unpaid,
    required this.createdAt,
  });

  int get nights => checkOut.difference(checkIn).inDays;

  /// Two date ranges overlap when each starts before the other ends. Used to
  /// prevent double-booking the same room.
  bool overlaps(DateTime otherCheckIn, DateTime otherCheckOut) {
    return checkIn.isBefore(otherCheckOut) && otherCheckIn.isBefore(checkOut);
  }
}
