import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// A release newer than the one installed.
class AppUpdate {
  /// The `N` in the tag `v1.0.0-build.N`.
  final int build;

  /// The tag as published, e.g. `v1.0.0-build.7`. Shown to the user.
  final String tag;

  /// Direct download URL of the `.apk` attached to the release.
  final String apkUrl;

  /// File name of that asset, e.g. `poonsuk-resort-v1.0.0-build.7.apk`.
  final String apkName;

  /// The release page, used as a fallback when the in-app install fails.
  final String pageUrl;

  const AppUpdate({
    required this.build,
    required this.tag,
    required this.apkUrl,
    required this.apkName,
    required this.pageUrl,
  });
}

/// Outcome of asking GitHub whether a newer release exists.
enum UpdateStatus {
  /// A newer build is published; see [UpdateCheck.update].
  available,

  /// GitHub answered and this build is the newest.
  upToDate,

  /// This is a dev/CI build (build number 0), which never updates itself.
  disabled,

  /// GitHub could not be reached or answered something unusable (offline,
  /// rate limited, no release yet). Says nothing about being up to date.
  failed,
}

class UpdateCheck {
  final UpdateStatus status;

  /// Set only when [status] is [UpdateStatus.available].
  final AppUpdate? update;

  const UpdateCheck(this.status, [this.update]);
}

/// Asks GitHub Releases whether a newer APK than this one exists.
///
/// The app is distributed as an APK on GitHub Releases, not through an app
/// store, so nothing else would tell an installed copy that it is out of date.
/// The release pipeline tags every build `v<name>-build.<N>` and compiles the
/// same `N` into the APK ([AppConfig.appBuild]); a higher `N` on GitHub means
/// an update.
class UpdateService {
  UpdateService({http.Client? httpClient, int? currentBuild, String? repo})
      : _http = httpClient ?? http.Client(),
        _currentBuild = currentBuild ?? AppConfig.appBuild,
        _repo = repo ?? AppConfig.releasesRepo;

  final http.Client _http;
  final int _currentBuild;
  final String _repo;

  /// False for dev and CI builds (build number 0), which must never offer to
  /// replace themselves with a release build.
  bool get enabled => _currentBuild > 0;

  /// The newer release, or null when up to date, disabled, offline, rate
  /// limited, or anything else goes wrong. Never throws: a failed update check
  /// must not get in the way of using the app.
  Future<AppUpdate?> check() async => (await checkDetailed()).update;

  /// Like [check], but says *why* there is no update — for the manual check
  /// on the About row, where "you are up to date" and "could not check" must
  /// not look the same. Never throws.
  Future<UpdateCheck> checkDetailed() async {
    if (!enabled) return const UpdateCheck(UpdateStatus.disabled);
    const failed = UpdateCheck(UpdateStatus.failed);
    try {
      final response = await _http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return failed;

      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) return failed;

      final tag = json['tag_name'];
      if (tag is! String) return failed;
      final build = parseBuildNumber(tag);
      // A hand-made release in another tag shape tells us nothing either way.
      if (build == null) return failed;
      if (build <= _currentBuild) return const UpdateCheck(UpdateStatus.upToDate);

      final assets = json['assets'];
      if (assets is! List) return failed;
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is String && url is String && name.toLowerCase().endsWith('.apk')) {
          return UpdateCheck(
            UpdateStatus.available,
            AppUpdate(
              build: build,
              tag: tag,
              apkUrl: url,
              apkName: name,
              pageUrl: (json['html_url'] as String?) ??
                  'https://github.com/$_repo/releases/latest',
            ),
          );
        }
      }
      return failed; // a newer release without an APK is nothing we can install
    } on Object {
      return failed;
    }
  }

  /// `v1.0.0-build.12` → 12. Null for a tag in any other shape, so a
  /// hand-made release (say `v2.0`) is ignored rather than misread.
  static int? parseBuildNumber(String tag) {
    final match = RegExp(r'-build\.(\d+)$').firstMatch(tag.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
