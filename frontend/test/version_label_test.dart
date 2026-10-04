import 'package:flutter_test/flutter_test.dart';

import 'package:hotel_booking/config.dart';

/// The version shown on the profile screen's About row. It must name the
/// installed build the same way the GitHub release does, so a user (or
/// whoever is helping them) can tell which APK is on the phone.
void main() {
  test('a release build shows the version name and build number', () {
    expect(AppConfig.versionLabelFor('1.0.0', 4), 'v1.0.0 (build 4)');
    expect(AppConfig.versionLabelFor('2.3.1', 128), 'v2.3.1 (build 128)');
  });

  test('a dev/CI build (build 0) is labelled as such, never as a release', () {
    expect(AppConfig.versionLabelFor('1.0.0', 0), 'v1.0.0 (dev build)');
  });

  test('under flutter test there is no compiled-in build, so it reads as dev', () {
    expect(AppConfig.appBuild, 0);
    expect(AppConfig.versionLabel, contains('dev build'));
  });
}
