import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../models/room.dart';
import '../../models/user.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/room/room_bloc.dart';
import '../../utils/formatters.dart';

/// Month calendar view of room bookings — lets staff/admin see, per room,
/// which rooms are booked on a given day. The grid fits the screen without
/// scrolling; tapping a day opens a sheet with that day's room/booking info.
class BookingCalendarScreen extends StatefulWidget {
  const BookingCalendarScreen({super.key});

  @override
  State<BookingCalendarScreen> createState() => _BookingCalendarScreenState();
}

class _BookingCalendarScreenState extends State<BookingCalendarScreen> {
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late DateTime _month; // first day of the displayed month

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Booking> _bookingsOn(DateTime day, List<Booking> all) {
    final d = _dateOnly(day);
    return all.where((b) {
      if (b.status == BookingStatus.cancelled) return false;
      final checkIn = _dateOnly(b.checkIn);
      final checkOut = _dateOnly(b.checkOut);
      return !d.isBefore(checkIn) && d.isBefore(checkOut);
    }).toList();
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  void _showBookingDetails(BuildContext context, Room room, Booking booking) {
    final users = context.read<AuthBloc>().state.users;
    AppUser? customer;
    for (final u in users) {
      if (u.id == booking.customerId) {
        customer = u;
        break;
      }
    }

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(room.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Guest', customer?.name ?? booking.customerName),
            _infoRow('Email', customer?.email ?? '—'),
            _infoRow('Phone', customer?.phone ?? '—'),
            const Divider(height: 20),
            _infoRow('Booking', booking.id),
            _infoRow('Dates',
                '${Format.date(booking.checkIn)} → ${Format.date(booking.checkOut)}'),
            _infoRow('Guests', '${booking.guests}'),
            _infoRow('Status', booking.status.label),
            _infoRow('Payment',
                '${booking.paymentStatus.label} · ${Format.money(booking.totalPrice)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  void _showDayBookings(BuildContext context, DateTime day) {
    final bookings = context.read<BookingBloc>().all;
    final rooms = [...context.read<RoomBloc>().allRooms]
      ..sort((a, b) => a.name.compareTo(b.name));
    final dayBookings = _bookingsOn(day, bookings);

    Booking? bookingForRoom(String roomId) {
      for (final b in dayBookings) {
        if (b.roomId == roomId) return b;
      }
      return null;
    }

    final bookedRooms = <Room>[];
    final availableRooms = <Room>[];
    for (final r in rooms) {
      (bookingForRoom(r.id) != null ? bookedRooms : availableRooms).add(r);
    }
    final ordered = [...bookedRooms, ...availableRooms];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      Format.date(day),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Text(
                    '${bookedRooms.length}/${rooms.length} room(s) booked',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rooms.isEmpty
                  ? const Center(child: Text('No rooms in inventory'))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: ordered.length,
                      itemBuilder: (_, i) {
                        final room = ordered[i];
                        final booking = bookingForRoom(room.id);
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: booking != null
                                  ? Colors.orange.shade100
                                  : Colors.green.shade100,
                              child: Icon(
                                Icons.king_bed_outlined,
                                color: booking != null
                                    ? Colors.orange.shade700
                                    : Colors.green.shade700,
                              ),
                            ),
                            title: Text(room.name),
                            subtitle: Text(
                              booking == null
                                  ? 'Available'
                                  : 'Booked · ${booking.customerName} (${booking.status.label})',
                            ),
                            trailing: booking != null
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: booking == null
                                ? null
                                : () => _showBookingDetails(
                                    sheetContext, room, booking),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingBloc>().all;
    final today = _dateOnly(DateTime.now());

    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday = 1 ... Sunday = 7; shift so the grid starts on Monday.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final trailingBlanks = (7 - (totalCells % 7)) % 7;
    final cellCount = totalCells + trailingBlanks;
    final rowCount = cellCount ~/ 7;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Expanded(
                    child: Text(
                      '${_monthName(_month.month)} ${_month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _weekdayLabels
                    .map((w) => Expanded(
                          child: Center(
                            child: Text(w,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cellWidth = constraints.maxWidth / 7;
                    final cellHeight = constraints.maxHeight / rowCount;
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cellCount,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: cellWidth / cellHeight,
                      ),
                      itemBuilder: (_, i) {
                        final dayNum = i - leadingBlanks + 1;
                        if (dayNum < 1 || dayNum > daysInMonth) {
                          return const SizedBox.shrink();
                        }
                        final day =
                            DateTime(_month.year, _month.month, dayNum);
                        final count = _bookingsOn(day, bookings).length;
                        final isToday = day == today;

                        return Padding(
                          padding: const EdgeInsets.all(3),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showDayBookings(context, day),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isToday ? Colors.teal.shade50 : null,
                                border: isToday
                                    ? Border.all(color: Colors.teal.shade300)
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  if (count > 0) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.orange.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}
