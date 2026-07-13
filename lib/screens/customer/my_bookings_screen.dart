import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../utils/formatters.dart';

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final bookings = context.watch<BookingBloc>().forCustomer(
      auth.currentUser!.id,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: bookings.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.luggage_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Text('No bookings yet'),
                  Text(
                    'Find a room to get started',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              itemBuilder: (_, i) => _BookingTile(booking: bookings[i]),
            ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking booking;
  const _BookingTile({required this.booking});

  Color _statusColor() {
    switch (booking.status) {
      case BookingStatus.approved:
        return Colors.green;
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.cancelled:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.roomName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    booking.status.label,
                    style: TextStyle(
                      color: _statusColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _line(
              Icons.calendar_today,
              '${Format.date(booking.checkIn)} → ${Format.date(booking.checkOut)}',
            ),
            _line(
              Icons.nights_stay,
              '${booking.nights} nights · '
              '${booking.guests} guests',
            ),
            _line(Icons.confirmation_number_outlined, 'Ref: ${booking.id}'),
            const Divider(),
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(booking.paymentStatus.label),
                  avatar: Icon(
                    booking.paymentStatus == PaymentStatus.paid
                        ? Icons.check_circle
                        : Icons.pending,
                    size: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  Format.money(booking.totalPrice),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
