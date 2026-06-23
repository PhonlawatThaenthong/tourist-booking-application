import 'package:flutter/material.dart';

import '../models/room.dart';
import '../utils/formatters.dart';

class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  const RoomCard({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _RoomImage(url: room.primaryImage),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Chip(
                        label: Text(room.type.label),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.teal.shade50,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people_outline,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('Up to ${room.capacity} guests',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Format.money(room.pricePerNight),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF00796B),
                        ),
                      ),
                      Text(' / night',
                          style: TextStyle(color: Colors.grey.shade600)),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Network image with graceful loading and error states (room images come from
/// remote URLs in the demo data).
class _RoomImage extends StatelessWidget {
  final String url;
  const _RoomImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _placeholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.king_bed_outlined, size: 48, color: Colors.grey),
        ),
      );
}
