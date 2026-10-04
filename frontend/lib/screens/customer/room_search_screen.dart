import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config.dart';
import '../../models/room.dart';
import '../../blocs/room/room_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../blocs/room/room_event.dart';
import '../../utils/formatters.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/room_card.dart';
import 'date_selection_screen.dart';
import 'hotel_location_screen.dart';
import 'room_detail_screen.dart';

/// Home tab: a hero photo of the resort above a real-time room search with
/// date and type filters. The list updates instantly as the user changes any
/// filter.
///
/// There is deliberately no price or guest filter: every room costs the same
/// and sleeps the same party, so either control would never change the
/// results. The guest count is still asked for, at booking time.
class RoomSearchScreen extends StatefulWidget {
  const RoomSearchScreen({super.key});

  @override
  State<RoomSearchScreen> createState() => _RoomSearchScreenState();
}

class _RoomSearchScreenState extends State<RoomSearchScreen> {
  DateTimeRange? _dateRange;
  final Set<RoomType> _types = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomBloc>();

    final filter = RoomFilter(
      checkIn: _dateRange?.start,
      checkOut: _dateRange?.end,
      types: _types,
      query: _query,
    );

    final results = roomProvider.search(
      filter,
      isRoomBooked: roomProvider.isRoomBooked,
    );

    // Hero figures come from the live inventory rather than being written into
    // the copy, so they stay true when rooms are added or repriced.
    final bookable = roomProvider.allRooms
        .where((r) => r.status == RoomStatus.available)
        .toList();

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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _ResortHero(
                roomCount: bookable.length,
                fromPrice: bookable.isEmpty
                    ? null
                    : bookable
                          .map((r) => r.pricePerNight)
                          .reduce((a, b) => a < b ? a : b),
              ),
            ),
            SliverToBoxAdapter(
              child: _FilterBar(
                dateRange: _dateRange,
                types: _types,
                onSearchChanged: (v) => setState(() => _query = v),
                onPickDates: _pickDates,
                onToggleType: (t) => setState(() {
                  _types.contains(t) ? _types.remove(t) : _types.add(t);
                }),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      '${results.length} room(s) available',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_dateRange != null)
                      Text(
                        '${Format.date(_dateRange!.start)} → '
                        '${Format.date(_dateRange!.end)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
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

  /// Re-fetch rooms and bookings so a slot released by an expired hold shows as
  /// available again. Availability here is computed client-side from both.
  Future<void> _refresh() async {
    await Future.wait([
      reloadBloc(context.read<RoomBloc>(), const RoomStarted()),
      reloadBloc(context.read<BookingBloc>(), const BookingStarted()),
    ]);
  }
}

/// Every photo in `image/` carries a "Galaxy S24 Ultra" stamp in the
/// bottom-left corner. The 2:1 hero frame is wider than the 16:9 photo, so
/// anchoring the crop to the top trims that strip off the bottom.
const _photoAlignment = Alignment.topCenter;

const _heroImage = 'image/view.jpg';

class _ResortHero extends StatelessWidget {
  final int roomCount;
  final double? fromPrice;

  const _ResortHero({required this.roomCount, required this.fromPrice});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final price = fromPrice;
    return AspectRatio(
      aspectRatio: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _heroImage,
            fit: BoxFit.cover,
            alignment: _photoAlignment,
          ),
          // Darkens the lower half so the white caption stays legible over
          // the lit cottage fronts.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Stay in Sadao, Songkhla',
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (roomCount > 0 && price != null)
                  Text(
                    '${_plural(roomCount, 'room')} · '
                    'from ${Format.money(price)} / night',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _plural(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

class _FilterBar extends StatelessWidget {
  final DateTimeRange? dateRange;
  final Set<RoomType> types;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDates;
  final ValueChanged<RoomType> onToggleType;

  const _FilterBar({
    required this.dateRange,
    required this.types,
    required this.onSearchChanged,
    required this.onPickDates,
    required this.onToggleType,
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
            Icon(
              Icons.calendar_month_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'Select your dates to see available rooms',
              textAlign: TextAlign.center,
            ),
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
          Text(
            'Try different dates or another room type',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
