import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../utils/formatters.dart';

/// Staff view to approve, cancel and reschedule bookings, filtered by status.
class ManageBookingsScreen extends StatefulWidget {
  const ManageBookingsScreen({super.key});

  @override
  State<ManageBookingsScreen> createState() => _ManageBookingsScreenState();
}

class _ManageBookingsScreenState extends State<ManageBookingsScreen> {
  BookingStatus? _filter; // null = all

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookingBloc>();
    final all = provider.all;
    final list = _filter == null
        ? all
        : all.where((b) => b.status == _filter).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _chip('All', null),
              _chip('Pending', BookingStatus.pending),
              _chip('Approved', BookingStatus.approved),
              _chip('Cancelled', BookingStatus.cancelled),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No bookings in this category'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _AdminBookingCard(booking: list[i]),
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, BookingStatus? status) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = status),
      ),
    );
  }
}

class _AdminBookingCard extends StatelessWidget {
  final Booking booking;
  const _AdminBookingCard({required this.booking});

  Color _color() {
    switch (booking.status) {
      case BookingStatus.approved:
        return Colors.green;
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.cancelled:
        return Colors.red;
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange:
          DateTimeRange(start: booking.checkIn, end: booking.checkOut),
    );
    if (picked != null && context.mounted) {
      context
          .read<BookingBloc>()
          .add(BookingRescheduleRequested(booking.id, picked.start, picked.end));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking rescheduled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<BookingBloc>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${booking.roomName}  (${booking.id})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _color().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(booking.status.label,
                      style: TextStyle(
                          color: _color(),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Guest: ${booking.customerName} · ${booking.guests} guests'),
            Text('${Format.date(booking.checkIn)} → '
                '${Format.date(booking.checkOut)} (${booking.nights} nights)'),
            Text('${Format.money(booking.totalPrice)} · '
                '${booking.paymentStatus.label}'),
            const SizedBox(height: 8),
            if (booking.status != BookingStatus.cancelled)
              Wrap(
                spacing: 8,
                children: [
                  if (booking.status == BookingStatus.pending)
                    FilledButton.icon(
                      onPressed: () =>
                          provider.add(BookingApproveRequested(booking.id)),
                      icon: const Icon(Icons.check, size: 18),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40)),
                      label: const Text('Approve'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _reschedule(context),
                    icon: const Icon(Icons.edit_calendar, size: 18),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40)),
                    label: const Text('Reschedule'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        provider.add(BookingCancelRequested(booking.id)),
                    icon: const Icon(Icons.close, size: 18),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        minimumSize: const Size(0, 40)),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
