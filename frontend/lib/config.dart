/// App-wide configuration. In a real deployment most of these would come from
/// environment variables or a remote config service.
class AppConfig {
  AppConfig._();

  static const String hotelName = 'Poonsuk Resort';

  /// Published check-in and check-out hours, shown next to a stay's dates.
  /// Display only: nothing enforces them, since letting a guest in early or
  /// out late is the front desk's call.
  static const String checkInTime = '14:00';
  static const String checkOutTime = '12:00';

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

  /// Sentry DSN. Empty by default, which switches Sentry off entirely — that
  /// is what `flutter run` and CI use, so crashes from a dev machine never
  /// reach the project. The release pipeline compiles the real value in:
  ///
  ///   flutter build apk --dart-define=SENTRY_DSN=https://...
  ///
  /// A DSN is a public value by design (it only permits sending events, never
  /// reading them), so shipping it inside the binary is safe.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Tags every event, so noise from test builds can be filtered out of the
  /// issue list instead of being mistaken for something real users hit.
  static const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Build number of this APK, compiled in by the release pipeline
  /// (.github/workflows/frontend-release.yml) and equal to the `N` in the
  /// release tag `v1.0.0-build.N`. It is what the in-app update check compares
  /// against the newest GitHub Release.
  ///
  /// 0 everywhere else (`flutter run`, CI test builds), which switches the
  /// update check off — a dev build must never offer to replace itself.
  static const int appBuild = int.fromEnvironment('APP_BUILD');

  /// Version name of this APK (the `1.0.0` of `v1.0.0-build.N`). The release
  /// pipeline compiles in the value from pubspec.yaml; the default only shows
  /// up in dev builds.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  /// What the About row shows, e.g. `v1.0.0 (build 12)` — the same name the
  /// release carries on GitHub, so a user can tell which APK they have.
  static String get versionLabel => appBuild > 0
      ? 'v$appVersion (build $appBuild)'
      : 'v$appVersion (dev build)';

  /// GitHub repository whose Releases hold the APKs (owner/name). Public, so
  /// the app can read the latest release without a token.
  static const String releasesRepo = String.fromEnvironment(
    'RELEASES_REPO',
    defaultValue: 'PhonlawatThaenthong/tourist-booking-application',
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
