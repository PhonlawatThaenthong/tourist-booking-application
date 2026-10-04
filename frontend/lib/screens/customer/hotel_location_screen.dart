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

  /// Full-bleed iframe wrapper for [AppConfig.hotelMapEmbedUrl].
  ///
  /// The zeroed margin and `100vh` height stop the WebView's default body
  /// padding from letterboxing the map inside the 16:9 box below.
  static final String _mapFrameHtml =
      '''
<!DOCTYPE html>
<html>
  <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
  <body style="margin:0;padding:0;overflow:hidden">
    <iframe src="${AppConfig.hotelMapEmbedUrl}"
            style="border:0;width:100%;height:100vh"
            allowfullscreen loading="lazy"
            referrerpolicy="no-referrer-when-downgrade"></iframe>
  </body>
</html>
''';

  // The Maps embed refuses to render as a top-level document, answering "The
  // Google Maps Embed API must be used in an iframe" instead. On web the
  // plugin *is* an <iframe>, so the URL can be loaded straight in; on
  // Android/iOS the WebView is a full browser view, so the iframe has to be
  // supplied by hand.
  //
  // webview_flutter_web also has no notion of a separate "JavaScript mode" to
  // toggle — its JS always runs — so calling setJavaScriptMode there throws
  // UnimplementedError. Android/iOS need it set explicitly, since the embed
  // requires JS to render.
  static WebViewController _buildMapController() {
    final controller = WebViewController();
    if (kIsWeb) {
      controller.loadRequest(Uri.parse(AppConfig.hotelMapEmbedUrl));
      return controller;
    }
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // A real https base URL keeps the frame's referrer intact; the embed is
    // rejected when it is loaded from an opaque about:blank origin.
    controller.loadHtmlString(
      _mapFrameHtml,
      baseUrl: 'https://www.google.com/',
    );
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
          Text(
            AppConfig.hotelName,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
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
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Open in Google Maps'),
          ),
        ],
      ),
    );
  }
}
