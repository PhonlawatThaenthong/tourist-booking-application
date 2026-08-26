import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config.dart';
import '../../models/room.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/room/room_bloc.dart';
import '../../utils/formatters.dart';
import '../../widgets/room_card.dart';
import 'date_selection_screen.dart';
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
  final int _guests = 1;
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _FilterBar(
              dateRange: _dateRange,
              types: _types,
              price: price,
              minPrice: minPrice,
              maxPrice: maxPrice,
              onSearchChanged: (v) => setState(() => _query = v),
              onPickDates: _pickDates,
              onToggleType: (t) => setState(() {
                _types.contains(t) ? _types.remove(t) : _types.add(t);
              }),
              onPriceChanged: (r) => setState(() => _priceRange = r),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
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
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          if (_dateRange == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _NeedDatesState(onPickDates: _pickDates),
            )
          else if (results.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.builder(
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
    final picked = await Navigator.of(context).push<DateTimeRange>(
      MaterialPageRoute(
        builder: (_) => DateSelectionScreen(initialRange: _dateRange),
      ),
    );
    if (picked != null) setState(() => _dateRange = picked);
  }
}

class _FilterBar extends StatelessWidget {
  final DateTimeRange? dateRange;
  final Set<RoomType> types;
  final RangeValues price;
  final double minPrice;
  final double maxPrice;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDates;
  final ValueChanged<RoomType> onToggleType;
  final ValueChanged<RangeValues> onPriceChanged;

  const _FilterBar({
    required this.dateRange,
    required this.types,
    required this.price,
    required this.minPrice,
    required this.maxPrice,
    required this.onSearchChanged,
    required this.onPickDates,
    required this.onToggleType,
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
            OutlinedButton.icon(
              onPressed: onPickDates,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                dateRange == null
                    ? 'Select dates'
                    : '${Format.date(dateRange!.start)} - '
                        '${Format.date(dateRange!.end)}',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
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

class _NeedDatesState extends StatelessWidget {
  final VoidCallback onPickDates;
  const _NeedDatesState({required this.onPickDates});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Select your dates to see available rooms',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPickDates,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: const Text('Select dates'),
            ),
          ],
        ),
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
