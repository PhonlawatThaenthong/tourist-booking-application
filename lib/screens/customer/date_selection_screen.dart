import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../models/room.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/room/room_bloc.dart';
import '../../utils/formatters.dart';

/// Month calendar the customer uses to pick check-in/check-out dates before
/// browsing rooms. Mirrors the admin booking calendar: each day shows how
/// many rooms are already booked, and tapping a day lists room availability.
class DateSelectionScreen extends StatefulWidget {
  final DateTimeRange? initialRange;

  const DateSelectionScreen({super.key, this.initialRange});

  @override
  State<DateSelectionScreen> createState() => _DateSelectionScreenState();
}

class _DateSelectionScreenState extends State<DateSelectionScreen> {
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late DateTime _month;
  late DateTime _today;
  DateTime? _checkIn;
  DateTime? _checkOut;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _checkIn = widget.initialRange != null
        ? _dateOnly(widget.initialRange!.start)
        : null;
    _checkOut = widget.initialRange != null
        ? _dateOnly(widget.initialRange!.end)
        : null;
    _month = DateTime(
      (_checkIn ?? now).year,
      (_checkIn ?? now).month,
    );
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
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _onDayTap(DateTime day) {
    if (day.isBefore(_today)) return;
    setState(() {
      if (_checkIn == null || (_checkOut != null)) {
        _checkIn = day;
        _checkOut = null;
      } else if (day.isBefore(_checkIn!)) {
        _checkIn = day;
      } else if (day == _checkIn) {
        _checkIn = null;
        _checkOut = null;
      } else {
        _checkOut = day;
      }
    });
  }

  void _showDayRooms(BuildContext context, DateTime day) {
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
      builder: (_) => DraggableScrollableSheet(
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
                                booking == null ? 'Available' : 'Booked'),
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

  bool _inRange(DateTime day) {
    if (_checkIn == null || _checkOut == null) return false;
    return day.isAfter(_checkIn!) && day.isBefore(_checkOut!);
  }

  void _confirm() {
    if (_checkIn == null || _checkOut == null) return;
    Navigator.of(context).pop(DateTimeRange(start: _checkIn!, end: _checkOut!));
  }

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingBloc>().all;
    final totalRooms = context.watch<RoomBloc>().allRooms.length;

    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final trailingBlanks = (7 - (totalCells % 7)) % 7;
    final cellCount = totalCells + trailingBlanks;
    final rowCount = cellCount ~/ 7;

    return Scaffold(
      appBar: AppBar(title: const Text('Select dates')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _DateBox(
                      label: 'Check-in',
                      value: _checkIn == null ? '—' : Format.date(_checkIn!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.grey.shade500, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateBox(
                      label: 'Check-out',
                      value: _checkOut == null ? '—' : Format.date(_checkOut!),
                    ),
                  ),
                ],
              ),
            ),
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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
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
                        final bookedCount = _bookingsOn(day, bookings).length;
                        final fullyBooked =
                            totalRooms > 0 && bookedCount >= totalRooms;
                        final isPast = day.isBefore(_today);
                        final isCheckIn = _checkIn != null && day == _checkIn;
                        final isCheckOut =
                            _checkOut != null && day == _checkOut;
                        final inRange = _inRange(day);

                        Color? bg;
                        Border? border;
                        Color textColor = Colors.black87;
                        if (isPast) {
                          textColor = Colors.grey.shade400;
                        }
                        if (isCheckIn || isCheckOut) {
                          bg = Colors.teal.shade600;
                          textColor = Colors.white;
                        } else if (inRange) {
                          bg = Colors.teal.shade50;
                        } else if (day == _today) {
                          border = Border.all(color: Colors.teal.shade300);
                        }

                        return Padding(
                          padding: const EdgeInsets.all(3),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: isPast ? null : () => _onDayTap(day),
                            onLongPress:
                                isPast ? null : () => _showDayRooms(context, day),
                            child: Container(
                              decoration: BoxDecoration(
                                color: bg,
                                border: border,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                  if (!isPast && bookedCount > 0) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: fullyBooked
                                            ? Colors.red.shade400
                                            : Colors.orange.shade600,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Tap a day to set check-in / check-out · hold to see room availability',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _checkIn != null && _checkOut != null ? _confirm : null,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('Confirm dates'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final String value;
  const _DateBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
