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

  /// Opens a Google Maps pin. Prefers [address] (lets Google geocode the
  /// exact spot) and falls back to the raw coordinates when no address is
  /// given.
  static Future<void> openLocation({
    required double lat,
    required double lng,
    String? label,
    String? address,
  }) async {
    final query = Uri.encodeComponent(address ?? label ?? '$lat,$lng');
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    await _launch(uri);
  }

  /// Opens turn-by-turn directions from the user's current location to the
  /// destination. Prefers [destAddress] over raw coordinates for the same
  /// reason as [openLocation].
  static Future<void> openDirections({
    required double destLat,
    required double destLng,
    String? destAddress,
  }) async {
    final destination = Uri.encodeComponent(destAddress ?? '$destLat,$destLng');
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving',
    );
    await _launch(uri);
  }

  /// Directions to the hotel itself (used on the customer home / location page).
  /// Routes by the exact business name, not the postal address, so Google
  /// Maps opens the actual "Poonsuk Resort@Sadao" place page (reviews,
  /// photos, availability) instead of a bare address pin.
  static Future<void> directionsToHotel() => openDirections(
        destLat: AppConfig.hotelLat,
        destLng: AppConfig.hotelLng,
        destAddress: AppConfig.hotelPlaceName,
      );

  static Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fall back to the platform default handler if the external app fails.
      await launchUrl(uri);
    }
  }
}
