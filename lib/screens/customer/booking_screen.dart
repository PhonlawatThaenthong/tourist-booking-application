import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/room.dart';
import '../../providers/booking_provider.dart';
import '../../utils/formatters.dart';
import 'payment_screen.dart';

/// Step where the customer confirms dates, guests and reviews the price before
/// paying.
class BookingScreen extends StatefulWidget {
  final Room room;
  final DateTimeRange? initialRange;
  final int initialGuests;

  const BookingScreen({
    super.key,
    required this.room,
    this.initialRange,
    this.initialGuests = 1,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTimeRange? _range;
  late int _guests;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _guests = widget.initialGuests.clamp(1, widget.room.capacity);
  }

  int get _nights => _range == null ? 0 : _range!.duration.inDays;
  double get _total => _nights * widget.room.pricePerNight;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _continue() {
    if (_range == null || _nights < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select valid dates first.')),
      );
      return;
    }

    final bookings = context.read<BookingProvider>();
    if (bookings.isRoomBooked(widget.room.id, _range!.start, _range!.end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This room is already booked for those dates.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PaymentScreen(
        room: widget.room,
        checkIn: _range!.start,
        checkOut: _range!.end,
        guests: _guests,
        total: _total,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Scaffold(
      appBar: AppBar(title: const Text('Review booking')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.king_bed_outlined),
              title: Text(room.name),
              subtitle: Text('${room.type.label} · '
                  '${Format.money(room.pricePerNight)}/night'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Dates',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDates,
            icon: const Icon(Icons.calendar_today),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50)),
            label: Text(_range == null
                ? 'Select check-in & check-out'
                : '${Format.date(_range!.start)} → '
                    '${Format.date(_range!.end)}  ($_nights nights)'),
          ),
          const SizedBox(height: 20),
          Text('Guests',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Number of guests (max ${room.capacity})'),
              const Spacer(),
              IconButton.outlined(
                onPressed: _guests > 1
                    ? () => setState(() => _guests--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('$_guests',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton.outlined(
                onPressed: _guests < room.capacity
                    ? () => setState(() => _guests++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_nights > 0)
            Card(
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _priceRow(
                        '${Format.money(room.pricePerNight)} × $_nights nights',
                        Format.money(_total)),
                    const Divider(),
                    _priceRow('Total', Format.money(_total), bold: true),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _continue,
          child: Text(_nights > 0
              ? 'Continue to payment · ${Format.money(_total)}'
              : 'Continue to payment'),
        ),
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
