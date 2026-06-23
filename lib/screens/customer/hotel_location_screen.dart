import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/maps_service.dart';

/// Hotel location page. Uses the Google Maps Static API for a preview image and
/// deep-links into Google Maps for an interactive map and directions.
///
/// Note: the static map renders fully once a Google Maps API key is supplied
/// (see [_staticMapUrl]); without a key Google returns a "for development only"
/// watermarked tile, and the buttons below still open the full Google Maps app.
class HotelLocationScreen extends StatelessWidget {
  const HotelLocationScreen({super.key});

  static const String _mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  String get _staticMapUrl {
    final base = 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=${AppConfig.hotelLat},${AppConfig.hotelLng}'
        '&zoom=15&size=640x360&scale=2'
        '&markers=color:red%7C${AppConfig.hotelLat},${AppConfig.hotelLng}';
    return _mapsApiKey.isEmpty ? base : '$base&key=$_mapsApiKey';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find us')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                _staticMapUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.teal.shade50,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map, size: 56, color: Colors.teal),
                        SizedBox(height: 8),
                        Text('Map preview'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(AppConfig.hotelName,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(AppConfig.hotelAddress)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: MapsService.directionsToHotel,
            icon: const Icon(Icons.directions),
            label: const Text('Get directions'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => MapsService.openLocation(
              lat: AppConfig.hotelLat,
              lng: AppConfig.hotelLng,
              label: AppConfig.hotelName,
            ),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Open in Google Maps'),
          ),
        ],
      ),
    );
  }
}
