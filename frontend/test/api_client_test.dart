import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hotel_booking/models/user.dart';
import 'package:hotel_booking/repositories/api/api_booking_repository.dart';
import 'package:hotel_booking/repositories/api/api_client.dart';
import 'package:hotel_booking/repositories/repository_exception.dart';

/// ApiClient is the one place every request goes through, so its rules apply
/// app-wide: auth header, error mapping, and the silent token refresh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const base = 'https://api.test';

  Map<String, dynamic> session(String access, String refresh, {String role = 'customer'}) => {
        'accessToken': access,
        'refreshToken': refresh,
        'user': {
          'id': 'u-1',
          'name': 'Alice',
          'email': 'alice@example.com',
          'phone': null,
          'role': role,
        },
      };

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('requests', () {
    test('trailing slash on the base URL does not produce a double slash', () async {
      late Uri seen;
      final api = ApiClient(
        baseUrl: '$base/',
        httpClient: MockClient((r) async {
          seen = r.url;
          return json([]);
        }),
      );
      await api.get('/api/rooms', auth: false);
      expect(seen.toString(), '$base/api/rooms');
    });

    test('query parameters are encoded', () async {
      late Uri seen;
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          seen = r.url;
          return json([]);
        }),
      );
      await api.get('/api/rooms/availability',
          query: {'from': '2026-01-01', 'to': '2026-02-01'}, auth: false);
      expect(seen.queryParameters, {'from': '2026-01-01', 'to': '2026-02-01'});
    });

    test('a JSON body is sent with the right content type', () async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          seen = r;
          return json({'ok': true});
        }),
      );
      await api.post('/api/x', body: {'a': 1}, auth: false);
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {'a': 1});
    });

    test('the access token is attached once signed in, and only when auth is on', () async {
      final headers = <String?>[];
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          headers.add(r.headers['Authorization']);
          return json({});
        }),
      );
      await api.get('/api/a'); // before login
      await api.saveSession(session('ACCESS-1', 'REFRESH-1'));
      await api.get('/api/b');
      await api.get('/api/c', auth: false);
      expect(headers, [null, 'Bearer ACCESS-1', null]);
    });

    test('204 and empty bodies come back as null', () async {
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async => http.Response('', 204)),
      );
      expect(await api.post('/api/auth/logout', auth: false), isNull);
    });

    test('Thai text in a response is decoded as UTF-8', () async {
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async => json({'note': 'สแกน QR แล้วโอน'})),
      );
      final data = await api.get('/api/payment/info', auth: false) as Map;
      expect(data['note'], 'สแกน QR แล้วโอน');
    });
  });

  group('errors', () {
    ApiClient failing(http.Response response) =>
        ApiClient(baseUrl: base, httpClient: MockClient((_) async => response));

    test('the server message is surfaced', () async {
      final api = failing(json({'message': 'ห้องนี้ถูกจองในช่วงวันที่เลือกแล้ว'}, 409));
      await expectLater(
        api.post('/api/bookings', body: {}, auth: false),
        throwsA(isA<RepositoryException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', 'ห้องนี้ถูกจองในช่วงวันที่เลือกแล้ว')),
      );
    });

    test('validation errors (a list of messages) are joined line by line', () async {
      final api = failing(json({
        'message': ['checkIn ต้องอยู่ในรูปแบบ YYYY-MM-DD', 'guests must not be greater than 20'],
      }, 400));
      await expectLater(
        api.post('/api/bookings', body: {}, auth: false),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
            'checkIn ต้องอยู่ในรูปแบบ YYYY-MM-DD\nguests must not be greater than 20')),
      );
    });

    test('401 and 403 become AuthException', () async {
      for (final code in [401, 403]) {
        await expectLater(
          failing(json({'message': 'no'}, code)).get('/api/x', auth: false),
          throwsA(isA<AuthException>().having((e) => e.statusCode, 'statusCode', code)),
        );
      }
    });

    test('other failures are plain RepositoryException, not AuthException', () async {
      await expectLater(
        failing(json({'message': 'boom'}, 500)).get('/api/x', auth: false),
        throwsA(allOf(isA<RepositoryException>(), isNot(isA<AuthException>()))),
      );
    });

    test('a non-JSON error page (e.g. nginx 502) gives a generic message with the code', () async {
      final api = failing(http.Response('<html>502 Bad Gateway</html>', 502));
      await expectLater(
        api.get('/api/x', auth: false),
        throwsA(isA<RepositoryException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.message, 'message', contains('502'))),
      );
    });

    test('a network failure becomes a "cannot reach server" RepositoryException', () async {
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        api.get('/api/x', auth: false),
        throwsA(isA<RepositoryException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('ติดต่อเซิร์ฟเวอร์ไม่ได้'))),
      );
    });
  });

  group('token refresh', () {
    test('a 401 refreshes once, retries with the new token, and saves it', () async {
      final calls = <String>[];
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          calls.add('${r.method} ${r.url.path} ${r.headers['Authorization'] ?? '-'}');
          if (r.url.path == '/api/auth/refresh') {
            expect(jsonDecode(r.body), {'refreshToken': 'REFRESH-1'});
            return json(session('ACCESS-2', 'REFRESH-2'));
          }
          return r.headers['Authorization'] == 'Bearer ACCESS-2'
              ? json({'ok': true})
              : json({'message': 'expired'}, 401);
        }),
      );
      await api.saveSession(session('ACCESS-1', 'REFRESH-1'));

      expect(await api.get('/api/bookings/me'), {'ok': true});
      expect(calls, [
        'GET /api/bookings/me Bearer ACCESS-1',
        'POST /api/auth/refresh -', // refresh itself carries no access token
        'GET /api/bookings/me Bearer ACCESS-2',
      ]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_access_token'), 'ACCESS-2');
      expect(prefs.getString('auth_refresh_token'), 'REFRESH-2');
    });

    test('if the refresh is refused, the session is cleared and the 401 surfaces', () async {
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async => json({'message': 'nope'}, 401)),
      );
      await api.saveSession(session('ACCESS-1', 'REFRESH-1'));

      await expectLater(api.get('/api/bookings/me'), throwsA(isA<AuthException>()));
      expect(api.isSignedIn, isFalse);
      expect(api.currentUser, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_refresh_token'), isNull);
    });

    test('a request is retried at most once (no refresh loop)', () async {
      var refreshes = 0;
      var protectedCalls = 0;
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          if (r.url.path == '/api/auth/refresh') {
            refreshes++;
            return json(session('ACCESS-$refreshes', 'REFRESH-$refreshes'));
          }
          protectedCalls++;
          return json({'message': 'still no'}, 401); // even with a fresh token
        }),
      );
      await api.saveSession(session('ACCESS-0', 'REFRESH-0'));

      await expectLater(api.get('/api/x'), throwsA(isA<AuthException>()));
      expect(refreshes, 1);
      expect(protectedCalls, 2);
    });

    test('several requests failing together share ONE refresh', () async {
      // The backend revokes a refresh token on first use, so a second
      // concurrent refresh would log the user out.
      var refreshes = 0;
      final gate = Completer<void>();
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          if (r.url.path == '/api/auth/refresh') {
            refreshes++;
            await gate.future; // hold the refresh open until all 3 have failed
            return json(session('ACCESS-2', 'REFRESH-2'));
          }
          return r.headers['Authorization'] == 'Bearer ACCESS-2'
              ? json({'path': r.url.path})
              : json({'message': 'expired'}, 401);
        }),
      );
      await api.saveSession(session('ACCESS-1', 'REFRESH-1'));

      final results = Future.wait([api.get('/api/a'), api.get('/api/b'), api.get('/api/c')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete();

      expect(await results, [
        {'path': '/api/a'},
        {'path': '/api/b'},
        {'path': '/api/c'},
      ]);
      expect(refreshes, 1);
    });

    test('without a refresh token a 401 is not retried', () async {
      var calls = 0;
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          calls++;
          return json({'message': 'no'}, 401);
        }),
      );
      await expectLater(api.get('/api/x'), throwsA(isA<AuthException>()));
      expect(calls, 1);
    });
  });

  group('session storage', () {
    test('a saved session survives an app restart', () async {
      final first = ApiClient(baseUrl: base, httpClient: MockClient((_) async => json({})));
      await first.saveSession(session('ACCESS-1', 'REFRESH-1', role: 'staff'));

      // New client = app relaunched.
      final second = ApiClient(baseUrl: base, httpClient: MockClient((_) async => json({})));
      final user = await second.loadSession();
      expect(user?.email, 'alice@example.com');
      expect(user?.role, UserRole.staff);
      expect(second.isSignedIn, isTrue);
      expect(second.isStaffSide, isTrue);
      expect(second.refreshToken, 'REFRESH-1');
    });

    test('clearSession wipes memory and storage', () async {
      final api = ApiClient(baseUrl: base, httpClient: MockClient((_) async => json({})));
      await api.saveSession(session('ACCESS-1', 'REFRESH-1'));
      await api.clearSession();

      expect(api.isSignedIn, isFalse);
      expect(api.refreshToken, isNull);
      expect(await ApiClient(baseUrl: base).loadSession(), isNull);
    });

    test('nothing saved means no session', () async {
      final api = ApiClient(baseUrl: base, httpClient: MockClient((_) async => json({})));
      expect(await api.loadSession(), isNull);
      expect(api.isSignedIn, isFalse);
    });
  });

  group('media URLs', () {
    final api = ApiClient(baseUrl: base, httpClient: MockClient((_) async => json({})));

    test('API photo paths get the base URL, assets and full URLs do not', () {
      expect(api.resolveMediaUrl('/api/rooms/1/images/a.jpg'), '$base/api/rooms/1/images/a.jpg');
      expect(api.resolveMediaUrl('image/P1.jpg'), 'image/P1.jpg');
      expect(api.resolveMediaUrl('https://cdn.x/a.jpg'), 'https://cdn.x/a.jpg');
    });

    test('toStoredMediaUrl strips only this server\'s base URL', () {
      const path = '/api/rooms/1/images/a.jpg';
      expect(api.toStoredMediaUrl(api.resolveMediaUrl(path)), path);
      expect(api.toStoredMediaUrl('image/P1.jpg'), 'image/P1.jpg');
      expect(api.toStoredMediaUrl('https://cdn.x/a.jpg'), 'https://cdn.x/a.jpg');
    });
  });

  group('ApiBookingRepository request contract', () {
    test('createBooking sends only roomId, dates and guests — never a price', () async {
      // The backend rejects any extra field (forbidNonWhitelisted) and must
      // never trust a client price, so this body shape is a hard contract.
      late Map<String, dynamic> sent;
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          sent = jsonDecode(r.body) as Map<String, dynamic>;
          return json({
            'id': 'b-1', 'roomId': 'r-1', 'roomName': 'P1', 'customerId': 'u-1',
            'customerName': 'Alice', 'checkIn': '2026-12-24', 'checkOut': '2026-12-26',
            'nights': 2, 'guests': 2, 'totalPrice': 2501, 'status': 'pending',
            'paymentStatus': 'unpaid', 'createdAt': '2026-10-04T08:00:00.000Z',
          }, 201);
        }),
      );
      await api.saveSession(session('A', 'R'));

      final booking = await ApiBookingRepository(api).createBooking(
        roomId: 'r-1',
        roomName: 'P1',
        customerId: 'u-1',
        customerName: 'Alice',
        checkIn: DateTime(2026, 12, 24, 15, 30),
        checkOut: DateTime(2026, 12, 26),
        guests: 2,
        totalPrice: 1, // must be ignored
      );

      expect(sent, {
        'roomId': 'r-1',
        'checkIn': '2026-12-24',
        'checkOut': '2026-12-26',
        'guests': 2,
      });
      expect(booking.totalPrice, 2501); // the server's price wins
    });

    test('customers fetch their own bookings, staff fetch everyone\'s', () async {
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: base,
        httpClient: MockClient((r) async {
          paths.add(r.url.path);
          return json([]);
        }),
      );
      final repo = ApiBookingRepository(api);

      expect(await repo.fetchBookings(), isEmpty); // signed out: no request at all
      await api.saveSession(session('A', 'R'));
      await repo.fetchBookings();
      await api.saveSession(session('A', 'R', role: 'admin'));
      await repo.fetchBookings();

      expect(paths, ['/api/bookings/me', '/api/staff/bookings']);
    });
  });
}
