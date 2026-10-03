enum BookingStatus { pending, approved, cancelled, checkedIn, checkedOut }

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.approved:
        return 'Approved';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.checkedIn:
        return 'Checked in';
      case BookingStatus.checkedOut:
        return 'Checked out';
    }
  }

  /// The value the API sends and expects. Same as [name] except for the
  /// two-word states, which the API spells in snake_case — matching on [name]
  /// alone would read every checked-in stay back as the fallback status.
  String get wireName {
    switch (this) {
      case BookingStatus.pending:
      case BookingStatus.approved:
      case BookingStatus.cancelled:
        return name;
      case BookingStatus.checkedIn:
        return 'checked_in';
      case BookingStatus.checkedOut:
        return 'checked_out';
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

  /// Whether the customer may still cancel: only a booking that has not
  /// started, and only before the check-in day. Mirrors the server rule in
  /// BookingsService.cancel, which stays the one that counts — this only
  /// decides whether to offer the button.
  bool get customerCanCancel {
    if (status != BookingStatus.pending && status != BookingStatus.approved) {
      return false;
    }
    return checkIn.isAfter(_today());
  }

  /// Whether the front desk may check the guest in now: a paid (approved)
  /// booking, from its check-in day until the day before check-out. Mirrors
  /// BookingsService.checkIn on the server.
  bool get staffCanCheckIn {
    if (status != BookingStatus.approved) return false;
    final today = _today();
    return !today.isBefore(checkIn) && today.isBefore(checkOut);
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Two date ranges overlap when each starts before the other ends. Used to
  /// prevent double-booking the same room.
  bool overlaps(DateTime otherCheckIn, DateTime otherCheckOut) {
    return checkIn.isBefore(otherCheckOut) && otherCheckIn.isBefore(checkOut);
  }
}
