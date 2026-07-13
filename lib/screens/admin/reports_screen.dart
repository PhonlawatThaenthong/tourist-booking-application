import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../models/room.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/room/room_bloc.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';

/// Basic reports & statistics: revenue, occupancy and a booking-status
/// breakdown drawn with simple bars (no external chart dependency).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingBloc>();
    final rooms = context.watch<RoomBloc>();
    final occupancy = bookings.occupancyRate(rooms.allRooms.length);

    final statusCounts = <BookingStatus, int>{
      BookingStatus.pending: bookings.pendingCount,
      BookingStatus.approved: bookings.approvedCount,
      BookingStatus.cancelled: bookings.cancelledCount,
    };
    final maxCount = statusCounts.values.fold(0, (a, b) => a > b ? a : b);

    final available = rooms.allRooms
        .where((r) => r.status == RoomStatus.available)
        .length;
    final maintenance = rooms.allRooms.length - available;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width >= 720 ? 3 : 2,
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
              icon: Icons.percent,
              label: 'Occupancy (30 days)',
              value: '${(occupancy * 100).toStringAsFixed(0)}%',
              color: Colors.purple,
            ),
            StatCard(
              icon: Icons.event_available,
              label: 'Total bookings',
              value: '${bookings.totalBookings}',
              color: Colors.blue,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Section(
          title: 'Bookings by status',
          child: Column(
            children: statusCounts.entries.map((e) {
              return _BarRow(
                label: e.key.label,
                value: e.value,
                maxValue: maxCount,
                color: _statusColor(e.key),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Occupancy rate (next 30 days)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: occupancy,
                  minHeight: 18,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 8),
              Text('${(occupancy * 100).toStringAsFixed(1)}% of room-nights '
                  'booked'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Room inventory',
          child: Column(
            children: [
              _kv('Total rooms', '${rooms.allRooms.length}'),
              _kv('Available', '$available'),
              _kv('Under maintenance', '$maintenance'),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(BookingStatus s) {
    switch (s) {
      case BookingStatus.approved:
        return Colors.green;
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.cancelled:
        return Colors.red;
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k),
            Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;

  const _BarRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue == 0 ? 0.0 : value / maxValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 14,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
