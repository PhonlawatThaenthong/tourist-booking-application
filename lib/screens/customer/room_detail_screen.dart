import 'package:flutter/material.dart';

import '../../models/room.dart';
import '../../utils/formatters.dart';
import 'booking_screen.dart';

class RoomDetailScreen extends StatefulWidget {
  final Room room;
  final DateTimeRange? initialRange;
  final int initialGuests;

  const RoomDetailScreen({
    super.key,
    required this.room,
    this.initialRange,
    this.initialGuests = 1,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  final _pageController = PageController();
  int _imageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final images = room.imageUrls.isEmpty ? [''] : room.imageUrls;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _imageIndex = i),
                    itemBuilder: (_, i) => _Image(url: images[i]),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          images.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _imageIndex == i ? 18 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                  alpha: _imageIndex == i ? 1 : 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(room.name,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      Chip(
                        label: Text(room.type.label),
                        backgroundColor: Colors.teal.shade50,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.people_outline,
                          size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 4),
                      Text('Up to ${room.capacity} guests'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('About this room',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(room.description,
                      style: TextStyle(
                          color: Colors.grey.shade800, height: 1.4)),
                  const SizedBox(height: 20),
                  Text('Amenities',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: room.amenities
                        .map((a) => Chip(
                              avatar: const Icon(Icons.check, size: 16),
                              label: Text(a),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: _BookingBar(
        room: room,
        onBook: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookingScreen(
              room: room,
              initialRange: widget.initialRange,
              initialGuests: widget.initialGuests,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingBar extends StatelessWidget {
  final Room room;
  final VoidCallback onBook;
  const _BookingBar({required this.room, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Format.money(room.pricePerNight),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Color(0xFF00796B))),
                Text('per night',
                    style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: onBook,
                child: const Text('Book now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  final String url;
  const _Image({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.king_bed, size: 64, color: Colors.grey),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image, size: 64, color: Colors.grey),
      ),
    );
  }
}
