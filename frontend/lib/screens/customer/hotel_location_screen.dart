import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config.dart';
import '../../services/maps_service.dart';

/// Hotel location page. Embeds the resort's Google Maps "Embed a map" iframe
/// for an interactive in-app preview and deep-links into Google Maps for
/// turn-by-turn directions.
///
/// The embed URL needs no API key (unlike the Static/JS Maps APIs), so the
/// preview always renders — no watermark, no billing account required.
class HotelLocationScreen extends StatefulWidget {
  const HotelLocationScreen({super.key});

  @override
  State<HotelLocationScreen> createState() => _HotelLocationScreenState();
}

class _HotelLocationScreenState extends State<HotelLocationScreen> {
  late final WebViewController _mapController = _buildMapController();

  // webview_flutter_web renders a plain <iframe>, which has no notion of a
  // separate "JavaScript mode" to toggle — its JS always runs — so calling
  // setJavaScriptMode there throws UnimplementedError. Android/iOS need it
  // set explicitly, since the Maps embed requires JS to render.
  static WebViewController _buildMapController() {
    final controller = WebViewController();
    if (!kIsWeb) controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.loadRequest(Uri.parse(AppConfig.hotelMapEmbedUrl));
    return controller;
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
              child: WebViewWidget(controller: _mapController),
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
              address: AppConfig.hotelPlaceName,
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
