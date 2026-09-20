/// App-wide configuration. In a real deployment most of these would come from
/// environment variables or a remote config service.
class AppConfig {
  AppConfig._();

  static const String hotelName = 'Poonsuk Resort';

  /// Base URL of the NestJS API.
  ///
  /// Default assumes the API is reachable on the same host as the app
  /// (desktop/web build, or the API port forwarded out of the VM). Override
  /// without touching this file:
  ///
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000
  ///
  /// Android emulator cannot see the host on `localhost` — it needs
  /// `http://10.0.2.2:3000`; a physical device needs the host's LAN IP.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Hotel coordinates, taken from the "Poonsuk Resort@Sadao" Google Maps
  /// place pin. Used to centre the static map preview and to anchor the
  /// "Open in Google Maps" / "Get directions" links (alongside
  /// [hotelAddress], which Google geocodes for the final result).
  static const double hotelLat = 6.639990393354523;
  static const double hotelLng = 100.42643307476759;
  static const String hotelAddress =
      '53/33 11 ถ.เลียบคลองท่าพรุ ต.สะเดา อ.สะเดา สงขลา 90120';

  /// Exact Google Maps business listing name. Searching/routing by this
  /// (rather than [hotelAddress]) is what lands on the actual place page —
  /// reviews, photos, availability — instead of a bare address pin.
  static const String hotelPlaceName = 'Poonsuk Resort@Sadao';

  /// Google Maps "Embed a map" src for the hotel location — free, no API key
  /// required (unlike the Static Maps API previously used on this screen).
  static const String hotelMapEmbedUrl =
      'https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d3963.0558225675804!2d100.42643307476759!3d6.639990393354523!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x304cc73cb1b3011f%3A0x329cb1163e8ad962!2sPoonsuk%20Resort%40Sadao!5e0!3m2!1sth!2sth!4v1789916784415!5m2!1sth!2sth';
}
