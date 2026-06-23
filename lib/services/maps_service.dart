import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Thin wrapper around the Google Maps URL API. Using deep links keeps the app
/// dependency-free of native map SDK keys while still leveraging Google Maps for
/// viewing locations and turn-by-turn directions.
///
/// To embed an interactive in-app map instead, add the `google_maps_flutter`
/// package and a Maps API key — see README for the steps.
class MapsService {
  MapsService._();

  /// Opens a Google Maps pin for the given coordinates.
  static Future<void> openLocation({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final query = label != null ? Uri.encodeComponent(label) : '$lat,$lng';
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng&query_place_id=$query',
    );
    await _launch(uri);
  }

  /// Opens turn-by-turn directions from the user's current location to the
  /// destination.
  static Future<void> openDirections({
    required double destLat,
    required double destLng,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving',
    );
    await _launch(uri);
  }

  /// Directions to the hotel itself (used on the customer home / location page).
  static Future<void> directionsToHotel() =>
      openDirections(destLat: AppConfig.hotelLat, destLng: AppConfig.hotelLng);

  static Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fall back to the platform default handler if the external app fails.
      await launchUrl(uri);
    }
  }
}
