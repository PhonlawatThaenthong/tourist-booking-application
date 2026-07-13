import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config.dart';
import '../../models/room.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/room/room_bloc.dart';
import '../../utils/formatters.dart';
import '../../widgets/room_card.dart';
import 'hotel_location_screen.dart';
import 'room_detail_screen.dart';

/// Real-time room search with date, type and price filters. The list updates
/// instantly as the user changes any filter.
class RoomSearchScreen extends StatefulWidget {
  const RoomSearchScreen({super.key});

  @override
  State<RoomSearchScreen> createState() => _RoomSearchScreenState();
}

class _RoomSearchScreenState extends State<RoomSearchScreen> {
  DateTimeRange? _dateRange;
  final Set<RoomType> _types = {};
  int _guests = 1;
  RangeValues? _priceRange;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomBloc>();
    final bookings = context.watch<BookingBloc>();

    final minPrice = roomProvider.minRoomPrice;
    final maxPrice = roomProvider.maxRoomPrice;
    final price = _priceRange ?? RangeValues(minPrice, maxPrice);

    final filter = RoomFilter(
      checkIn: _dateRange?.start,
      checkOut: _dateRange?.end,
      types: _types,
      minPrice: price.start,
      maxPrice: price.end,
      guests: _guests,
      query: _query,
    );

    final results =
        roomProvider.search(filter, isRoomBooked: bookings.isRoomBooked);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.hotelName),
        actions: [
          IconButton(
            tooltip: 'Hotel location',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HotelLocationScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            dateRange: _dateRange,
            types: _types,
            guests: _guests,
            price: price,
            minPrice: minPrice,
            maxPrice: maxPrice,
            onSearchChanged: (v) => setState(() => _query = v),
            onPickDates: _pickDates,
            onToggleType: (t) => setState(() {
              _types.contains(t) ? _types.remove(t) : _types.add(t);
            }),
            onGuestsChanged: (g) => setState(() => _guests = g),
            onPriceChanged: (r) => setState(() => _priceRange = r),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('${results.length} room(s) available',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_dateRange != null)
                  Text(
                    '${Format.date(_dateRange!.start)} → '
                    '${Format.date(_dateRange!.end)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final room = results[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RoomCard(
                          room: room,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RoomDetailScreen(
                                room: room,
                                initialRange: _dateRange,
                                initialGuests: _guests,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }
}

class _FilterBar extends StatelessWidget {
  final DateTimeRange? dateRange;
  final Set<RoomType> types;
  final int guests;
  final RangeValues price;
  final double minPrice;
  final double maxPrice;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDates;
  final ValueChanged<RoomType> onToggleType;
  final ValueChanged<int> onGuestsChanged;
  final ValueChanged<RangeValues> onPriceChanged;

  const _FilterBar({
    required this.dateRange,
    required this.types,
    required this.guests,
    required this.price,
    required this.minPrice,
    required this.maxPrice,
    required this.onSearchChanged,
    required this.onPickDates,
    required this.onToggleType,
    required this.onGuestsChanged,
    required this.onPriceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            TextField(
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search rooms…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDates,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      dateRange == null
                          ? 'Select dates'
                          : '${Format.date(dateRange!.start)} - '
                              '${Format.date(dateRange!.end)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _GuestStepper(guests: guests, onChanged: onGuestsChanged),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: RoomType.values.map((t) {
                  final selected = types.contains(t);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t.label),
                      selected: selected,
                      onSelected: (_) => onToggleType(t),
                    ),
                  );
                }).toList(),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${Format.money(price.start)} - ${Format.money(price.end)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            RangeSlider(
              values: price,
              min: minPrice,
              max: maxPrice,
              divisions: 20,
              labels: RangeLabels(
                Format.money(price.start),
                Format.money(price.end),
              ),
              onChanged: onPriceChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestStepper extends StatelessWidget {
  final int guests;
  final ValueChanged<int> onChanged;
  const _GuestStepper({required this.guests, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove),
            onPressed: guests > 1 ? () => onChanged(guests - 1) : null,
          ),
          Text('$guests', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: guests < 10 ? () => onChanged(guests + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No rooms match your filters'),
          Text('Try widening your dates or price range',
              style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
