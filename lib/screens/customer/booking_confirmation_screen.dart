import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../utils/formatters.dart';

/// Shown after a successful payment. Confirms the booking and surfaces the
/// auto-sent email/SMS content.
class BookingConfirmationScreen extends StatelessWidget {
  final Booking booking;
  final String confirmationMessage;
  final String sentToEmail;
  final String sentToPhone;

  const BookingConfirmationScreen({
    super.key,
    required this.booking,
    required this.confirmationMessage,
    required this.sentToEmail,
    required this.sentToPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking confirmed'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle,
                  color: Colors.green.shade600, size: 72),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('Thank you! Your stay is booked.',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Center(
            child: Text('Booking reference: ${booking.id}',
                style: TextStyle(color: Colors.grey.shade700)),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Room', booking.roomName),
                  _row('Check-in', Format.date(booking.checkIn)),
                  _row('Check-out', Format.date(booking.checkOut)),
                  _row('Guests', '${booking.guests}'),
                  _row('Nights', '${booking.nights}'),
                  const Divider(),
                  _row('Total paid', Format.money(booking.totalPrice),
                      bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mark_email_read,
                          color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Confirmation sent automatically',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('📧 Email → $sentToEmail'),
                  Text('📱 SMS → $sentToPhone'),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(confirmationMessage,
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }
}
