import '../models/booking.dart';

/// Data access for bookings. Backend: `/api/bookings` and
/// `/api/staff/bookings`.
abstract class BookingRepository {
  /// Backend: `GET /api/bookings/me` for customers,
  /// `GET /api/staff/bookings` for staff.
  Future<List<Booking>> fetchBookings();

  /// Backend: `POST /api/bookings`. Creates a PENDING/UNPAID booking — payment
  /// is a separate step (upload a slip via [PaymentRepository], staff confirm).
  ///
  /// The server rejects an overlapping range with 409 (exclusion constraint);
  /// the implementation surfaces that as a [RepositoryException].
  Future<Booking> createBooking({
    required String roomId,
    required String roomName,
    required String customerId,
    required String customerName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
    required double totalPrice,
  });

  /// Backend: `POST /api/bookings/:id/cancel` — the customer's own cancel.
  /// Allowed only before the check-in day; a paid booking comes back
  /// REFUNDED. Staff cancel through [updateStatus] instead.
  Future<Booking> cancelBooking(String id);

  /// Backend: `POST /api/staff/bookings/:id/check-in`. Only an approved
  /// booking, from its check-in day until the day before check-out.
  Future<Booking> checkIn(String id);

  /// Backend: `POST /api/staff/bookings/:id/check-out` — closes the booking.
  /// Only a checked-in one.
  Future<Booking> checkOut(String id);

  /// Backend: `PATCH /api/staff/bookings/:id` — status transition. Refuses
  /// checked-in/out, which go through [checkIn] and [checkOut].
  Future<Booking> updateStatus(String id, BookingStatus status);

  /// Backend: `PATCH /api/staff/bookings/:id` — new date range.
  /// The total price is recalculated from the stored nightly rate.
  Future<Booking> reschedule(String id, DateTime checkIn, DateTime checkOut);
}
