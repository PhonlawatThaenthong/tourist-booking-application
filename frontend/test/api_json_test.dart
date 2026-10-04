import 'package:flutter_test/flutter_test.dart';

import 'package:hotel_booking/models/booking.dart';
import 'package:hotel_booking/models/room.dart';
import 'package:hotel_booking/models/user.dart';
import 'package:hotel_booking/repositories/api/api_booking_repository.dart';
import 'package:hotel_booking/repositories/api/api_client.dart';
import 'package:hotel_booking/repositories/api/api_room_repository.dart';

/// Parsing of the JSON the backend sends. The shapes here are copied from the
/// real responses (backend/src/modules/*/..response.ts); if the API changes a
/// field, these are the tests that should fail first.
void main() {
  Map<String, dynamic> bookingJson([Map<String, dynamic> overrides = const {}]) => {
        'id': 'b-1',
        'roomId': 'r-1',
        'roomName': 'P1',
        'customerId': 'u-1',
        'customerName': 'Alice',
        'checkIn': '2026-12-24',
        'checkOut': '2026-12-27',
        'nights': 3,
        'guests': 2,
        'totalPrice': 3751.5,
        'status': 'pending',
        'paymentStatus': 'unpaid',
        'createdAt': '2026-10-04T08:15:00.000Z',
        ...overrides,
      };

  group('bookingFromJson', () {
    test('reads every field', () {
      final b = bookingFromJson(bookingJson());
      expect(b.id, 'b-1');
      expect(b.roomId, 'r-1');
      expect(b.roomName, 'P1');
      expect(b.customerName, 'Alice');
      expect(b.checkIn, DateTime(2026, 12, 24));
      expect(b.checkOut, DateTime(2026, 12, 27));
      expect(b.nights, 3);
      expect(b.guests, 2);
      expect(b.totalPrice, 3751.5);
      expect(b.status, BookingStatus.pending);
      expect(b.paymentStatus, PaymentStatus.unpaid);
    });

    test('dates are calendar days at local midnight (no timezone shift)', () {
      final b = bookingFromJson(bookingJson());
      expect(b.checkIn.hour, 0);
      expect(b.checkIn.day, 24);
    });

    test('snake_case statuses map to the right enum value', () {
      expect(bookingFromJson(bookingJson({'status': 'checked_in'})).status,
          BookingStatus.checkedIn);
      expect(bookingFromJson(bookingJson({'status': 'checked_out'})).status,
          BookingStatus.checkedOut);
    });

    test('every status the API can send round-trips through wireName', () {
      for (final s in BookingStatus.values) {
        expect(bookingFromJson(bookingJson({'status': s.wireName})).status, s);
      }
    });

    test('payment statuses parse', () {
      expect(bookingFromJson(bookingJson({'paymentStatus': 'paid'})).paymentStatus,
          PaymentStatus.paid);
      expect(bookingFromJson(bookingJson({'paymentStatus': 'refunded'})).paymentStatus,
          PaymentStatus.refunded);
    });

    test('an unknown status falls back instead of crashing', () {
      final b = bookingFromJson(bookingJson({'status': 'teleported', 'paymentStatus': '?'}));
      expect(b.status, BookingStatus.pending);
      expect(b.paymentStatus, PaymentStatus.unpaid);
    });

    test('a whole-number price sent as an int still parses', () {
      expect(bookingFromJson(bookingJson({'totalPrice': 3000})).totalPrice, 3000.0);
    });

    test('missing room/customer names become empty strings', () {
      final json = bookingJson()
        ..remove('roomName')
        ..remove('customerName');
      final b = bookingFromJson(json);
      expect(b.roomName, '');
      expect(b.customerName, '');
    });
  });

  group('roomFromJson', () {
    Map<String, dynamic> roomJson([Map<String, dynamic> o = const {}]) => {
          'id': 'r-1',
          'name': 'P1',
          'type': 'twin',
          'pricePerNight': 1250.5,
          'capacity': 2,
          'description': 'Sea view',
          'imageUrls': ['image/P1.jpg', '/api/rooms/r-1/images/a.jpg'],
          'amenities': ['Wi-Fi', 'Aircon'],
          'status': 'available',
          ...o,
        };

    String resolve(String url) => url.startsWith('/api/') ? 'https://api.test$url' : url;

    test('reads every field and resolves uploaded photo URLs only', () {
      final r = roomFromJson(roomJson(), resolve);
      expect(r.type, RoomType.twin);
      expect(r.pricePerNight, 1250.5);
      expect(r.capacity, 2);
      expect(r.amenities, ['Wi-Fi', 'Aircon']);
      // Bundled asset stays as-is; API path gets the base URL.
      expect(r.imageUrls, ['image/P1.jpg', 'https://api.test/api/rooms/r-1/images/a.jpg']);
      expect(r.status, RoomStatus.available);
    });

    test('maintenance status parses', () {
      expect(roomFromJson(roomJson({'status': 'maintenance'}), resolve).status,
          RoomStatus.maintenance);
    });

    test('int price, null lists and unknown type are all tolerated', () {
      final r = roomFromJson(
        roomJson({
          'pricePerNight': 2500,
          'imageUrls': null,
          'amenities': null,
          'description': null,
          'type': 'penthouse',
        }),
        resolve,
      );
      expect(r.pricePerNight, 2500.0);
      expect(r.imageUrls, isEmpty);
      expect(r.amenities, isEmpty);
      expect(r.description, '');
      expect(r.type, RoomType.single);
    });
  });

  group('userFromJson / roleFromString', () {
    test('reads the user and never carries a password', () {
      final u = userFromJson({
        'id': 'u-1',
        'name': 'Alice',
        'email': 'alice@example.com',
        'phone': '0812345678',
        'role': 'admin',
      });
      expect(u.role, UserRole.admin);
      expect(u.phone, '0812345678');
      expect(u.password, '');
    });

    test('a null phone becomes an empty string', () {
      final u = userFromJson({
        'id': 'u-1', 'name': 'A', 'email': 'a@b.c', 'phone': null, 'role': 'customer',
      });
      expect(u.phone, '');
    });

    test('an unknown or missing role is treated as customer (least privilege)', () {
      expect(roleFromString('superuser'), UserRole.customer);
      expect(roleFromString(null), UserRole.customer);
      expect(roleFromString('staff'), UserRole.staff);
    });
  });

  group('ymd', () {
    test('zero-pads month and day', () {
      expect(ymd(DateTime(2026, 3, 7)), '2026-03-07');
      expect(ymd(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('ignores the time of day', () {
      expect(ymd(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    });
  });
}
