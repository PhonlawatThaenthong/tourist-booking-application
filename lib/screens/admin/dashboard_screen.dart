import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/booking.dart';
import '../../providers/booking_provider.dart';
import '../../providers/room_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';

/// Central overview: key metrics plus the most recent bookings needing action.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingProvider>();
    final rooms = context.watch<RoomProvider>();
    final occupancy = bookings.occupancyRate(rooms.allRooms.length);
    final recent = bookings.all.take(5).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width >= 720 ? 4 : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            StatCard(
              icon: Icons.payments,
              label: 'Total revenue',
              value: Format.money(bookings.totalRevenue),
              color: Colors.green,
            ),
            StatCard(
              icon: Icons.event_available,
              label: 'Total bookings',
              value: '${bookings.totalBookings}',
              color: Colors.blue,
            ),
            StatCard(
              icon: Icons.hourglass_top,
              label: 'Pending approval',
              value: '${bookings.pendingCount}',
              color: Colors.orange,
            ),
            StatCard(
              icon: Icons.percent,
              label: 'Occupancy (30d)',
              value: '${(occupancy * 100).toStringAsFixed(0)}%',
              color: Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Recent bookings',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No bookings yet')),
          )
        else
          ...recent.map((b) => _RecentTile(booking: b)),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  final Booking booking;
  const _RecentTile({required this.booking});

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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color().withValues(alpha: 0.15),
          child: Icon(Icons.bed, color: _color()),
        ),
        title: Text(booking.roomName),
        subtitle: Text(
          '${booking.customerName} · '
          '${Format.date(booking.checkIn)} → ${Format.date(booking.checkOut)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Format.money(booking.totalPrice),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              booking.status.label,
              style: TextStyle(color: _color(), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
