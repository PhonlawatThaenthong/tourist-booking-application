/// App-wide configuration. In a real deployment most of these would come from
/// environment variables or a remote config service.
class AppConfig {
  AppConfig._();

  static const String hotelName = 'Azure Bay Hotel';

  /// Hotel coordinates (sample location: Pattaya Beach, Thailand). Used to
  /// centre maps and compute "directions to the hotel" links.
  static const double hotelLat = 12.9276;
  static const double hotelLng = 100.8770;
  static const String hotelAddress =
      'Beach Road, Pattaya, Chonburi 20150, Thailand';
}
