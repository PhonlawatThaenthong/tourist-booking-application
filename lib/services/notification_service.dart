import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../utils/formatters.dart';

/// Sends booking confirmations by email / SMS.
///
/// This is a mock implementation: it composes the message and logs it (and
/// exposes it to the UI) instead of hitting a real provider. To go live, wire
/// [sendBookingConfirmation] to an email API (e.g. SendGrid) and an SMS gateway
/// (e.g. Twilio) — the call sites and message templates stay the same.
class NotificationService {
  /// Returns the human-readable confirmation text that was "sent", so the UI
  /// can show the user exactly what they would receive.
  static Future<String> sendBookingConfirmation({
    required Booking booking,
    required String email,
    required String phone,
  }) async {
    final message = _composeMessage(booking);

    // Simulate network latency of contacting the email/SMS providers.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (kDebugMode) {
      debugPrint('📧 EMAIL → $email\n$message');
      debugPrint('📱 SMS → $phone\nBooking ${booking.id} confirmed. '
          'Check-in ${Format.date(booking.checkIn)}.');
    }

    return message;
  }

  static String _composeMessage(Booking booking) {
    return 'Hello ${booking.customerName},\n\n'
        'Your booking is confirmed! 🎉\n\n'
        'Booking ref: ${booking.id}\n'
        'Room: ${booking.roomName}\n'
        'Check-in: ${Format.date(booking.checkIn)}\n'
        'Check-out: ${Format.date(booking.checkOut)}\n'
        'Guests: ${booking.guests}\n'
        'Nights: ${booking.nights}\n'
        'Total paid: ${Format.money(booking.totalPrice)}\n\n'
        'We look forward to welcoming you!';
  }
}
