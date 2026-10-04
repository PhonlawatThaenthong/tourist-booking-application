import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ota_update/ota_update.dart';

import 'package:hotel_booking/services/update_service.dart';
import 'package:hotel_booking/widgets/update_gate.dart';

/// In-app update: the version comparison against GitHub Releases, and the
/// prompt → download → install (or browser fallback) flow.
void main() {
  const repo = 'owner/app';

  Map<String, dynamic> release(String tag, {List<String> assets = const ['app.apk']}) => {
        'tag_name': tag,
        'html_url': 'https://github.com/$repo/releases/tag/$tag',
        'assets': [
          for (final name in assets)
            {
              'name': name,
              'browser_download_url': 'https://github.com/$repo/releases/download/$tag/$name',
            },
        ],
      };

  UpdateService service(int current, Object body, {int status = 200}) => UpdateService(
        currentBuild: current,
        repo: repo,
        httpClient: MockClient((r) async {
          expect(r.url.toString(), 'https://api.github.com/repos/$repo/releases/latest');
          return http.Response(body is String ? body : jsonEncode(body), status);
        }),
      );

  group('UpdateService.parseBuildNumber', () {
    test('reads N from v<name>-build.<N>', () {
      expect(UpdateService.parseBuildNumber('v1.0.0-build.1'), 1);
      expect(UpdateService.parseBuildNumber('v1.2.3-build.47'), 47);
      expect(UpdateService.parseBuildNumber('v10.0.0-build.1234'), 1234);
    });

    test('ignores tags in any other shape', () {
      expect(UpdateService.parseBuildNumber('v2.0'), isNull);
      expect(UpdateService.parseBuildNumber('build.5'), isNull);
      expect(UpdateService.parseBuildNumber('v1.0.0-build.'), isNull);
      expect(UpdateService.parseBuildNumber('v1.0.0-build.7-beta'), isNull);
      expect(UpdateService.parseBuildNumber(''), isNull);
    });
  });

  group('UpdateService.check', () {
    test('a higher build on GitHub is an update', () async {
      final update = await service(3, release('v1.0.0-build.4')).check();
      expect(update, isNotNull);
      expect(update!.build, 4);
      expect(update.tag, 'v1.0.0-build.4');
      expect(update.apkName, 'app.apk');
      expect(update.apkUrl, endsWith('/v1.0.0-build.4/app.apk'));
    });

    test('build numbers compare as numbers, not text (10 > 9)', () async {
      expect(await service(9, release('v1.0.0-build.10')).check(), isNotNull);
    });

    test('the same or an older build is not an update', () async {
      expect(await service(4, release('v1.0.0-build.4')).check(), isNull);
      expect(await service(5, release('v1.0.0-build.4')).check(), isNull);
    });

    test('picks the .apk among several assets', () async {
      final update = await service(
        1,
        release('v1.0.0-build.2', assets: ['notes.txt', 'Resort.APK', 'symbols.zip']),
      ).check();
      expect(update!.apkName, 'Resort.APK');
    });

    test('a release with no APK attached is ignored', () async {
      expect(
        await service(1, release('v1.0.0-build.2', assets: ['notes.txt'])).check(),
        isNull,
      );
    });

    test('dev/CI builds (build 0) never check and never hit the network', () async {
      var called = false;
      final dev = UpdateService(
        currentBuild: 0,
        repo: repo,
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(dev.enabled, isFalse);
      expect(await dev.check(), isNull);
      expect(called, isFalse);
    });

    test('never throws: rate limit, 404, garbage and offline all mean "no update"', () async {
      expect(await service(1, {'message': 'API rate limit exceeded'}, status: 403).check(), isNull);
      expect(await service(1, {'message': 'Not Found'}, status: 404).check(), isNull);
      expect(await service(1, '<html>oops</html>').check(), isNull);
      expect(await service(1, [1, 2, 3]).check(), isNull);
      expect(await service(1, {'tag_name': 42, 'assets': 'nope'}).check(), isNull);

      final offline = UpdateService(
        currentBuild: 1,
        repo: repo,
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await offline.check(), isNull);
    });
  });

  group('UpdateGate', () {
    Future<void> pumpGate(
      WidgetTester tester, {
      required UpdateService service,
      UpdateInstaller? installer,
      UrlOpener? openUrl,
      bool platformSupported = true,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: UpdateGate(
          service: service,
          installer: installer,
          openUrl: openUrl,
          platformSupported: platformSupported,
          child: const Scaffold(body: Text('home')),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('up to date: no prompt', (tester) async {
      await pumpGate(tester, service: service(4, release('v1.0.0-build.4')));
      expect(find.text('Update available'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('not on Android: no prompt even if a newer build exists', (tester) async {
      await pumpGate(
        tester,
        service: service(1, release('v1.0.0-build.2')),
        platformSupported: false,
      );
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('newer build: prompts, and "Later" just closes it', (tester) async {
      var installs = 0;
      await pumpGate(
        tester,
        service: service(1, release('v1.0.0-build.2')),
        installer: (_) {
          installs++;
          return const Stream.empty();
        },
      );
      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('v1.0.0-build.2'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
      expect(installs, 0);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('"Update" downloads with progress, then hands over to the installer',
        (tester) async {
      final events = StreamController<OtaEvent>();
      AppUpdate? requested;
      var browserOpened = false;
      await pumpGate(
        tester,
        service: service(1, release('v1.0.0-build.2')),
        installer: (u) {
          requested = u;
          return events.stream;
        },
        openUrl: (_) async => browserOpened = true,
      );

      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Downloading update'), findsOneWidget);
      expect(requested?.apkUrl, endsWith('/v1.0.0-build.2/app.apk'));

      events.add(OtaEvent(OtaStatus.DOWNLOADING, '42'));
      await tester.pump();
      expect(find.textContaining('42%'), findsOneWidget);

      events.add(OtaEvent(OtaStatus.INSTALLING, null));
      await tester.pumpAndSettle();
      expect(find.text('Downloading update'), findsNothing);
      expect(browserOpened, isFalse);
      unawaited(events.close());
    });

    testWidgets('if the in-app install fails, the APK link opens in the browser',
        (tester) async {
      final events = StreamController<OtaEvent>();
      Uri? opened;
      await pumpGate(
        tester,
        service: service(1, release('v1.0.0-build.2')),
        installer: (_) => events.stream,
        openUrl: (url) async {
          opened = url;
          return true;
        },
      );

      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.pump();
      events.add(OtaEvent(OtaStatus.PERMISSION_NOT_GRANTED_ERROR, null));
      await tester.pumpAndSettle();

      expect(find.text('Downloading update'), findsNothing);
      expect(opened.toString(), endsWith('/v1.0.0-build.2/app.apk'));
      expect(find.textContaining('browser'), findsOneWidget);
      unawaited(events.close());
    });

    testWidgets('"Cancel" during download stops quietly, no browser fallback', (tester) async {
      final events = StreamController<OtaEvent>();
      var browserOpened = false;
      await pumpGate(
        tester,
        service: service(1, release('v1.0.0-build.2')),
        installer: (_) => events.stream,
        openUrl: (_) async => browserOpened = true,
      );

      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Downloading update'), findsNothing);
      expect(browserOpened, isFalse);
      expect(find.text('home'), findsOneWidget);
      unawaited(events.close());
    });
  });
}
