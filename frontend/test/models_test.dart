import 'package:flutter_test/flutter_test.dart';

import 'package:hotel_booking/models/booking.dart';
import 'package:hotel_booking/models/room.dart';
import 'package:hotel_booking/models/user.dart';

/// Client-side rules on the models. The server stays authoritative for each
/// of these, but the app uses them to decide which buttons to show, so a
/// mismatch means offering an action the server will refuse (or hiding one
/// it would allow).
void main() {
  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Booking booking({
    required DateTime checkIn,
    required DateTime checkOut,
    BookingStatus status = BookingStatus.pending,
  }) =>
      Booking(
        id: 'b1',
        roomId: 'r1',
        roomName: 'P1',
        customerId: 'u1',
        customerName: 'Alice',
        checkIn: checkIn,
        checkOut: checkOut,
        guests: 2,
        totalPrice: 3000,
        status: status,
        createdAt: DateTime(2026, 1, 1),
      );

  group('Booking.nights', () {
    test('counts nights, not days', () {
      expect(
        booking(checkIn: DateTime(2026, 5, 1), checkOut: DateTime(2026, 5, 4)).nights,
        3,
      );
    });

    test('works across a month boundary', () {
      expect(
        booking(checkIn: DateTime(2026, 1, 30), checkOut: DateTime(2026, 2, 2)).nights,
        3,
      );
    });
  });

  group('Booking.overlaps (half-open ranges)', () {
    final b = booking(checkIn: DateTime(2026, 5, 10), checkOut: DateTime(2026, 5, 13));

    test('same range overlaps', () {
      expect(b.overlaps(DateTime(2026, 5, 10), DateTime(2026, 5, 13)), isTrue);
    });

    test('a range inside overlaps', () {
      expect(b.overlaps(DateTime(2026, 5, 11), DateTime(2026, 5, 12)), isTrue);
    });

    test('a range that wraps around overlaps', () {
      expect(b.overlaps(DateTime(2026, 5, 1), DateTime(2026, 5, 30)), isTrue);
    });

    test('partial overlap at either end overlaps', () {
      expect(b.overlaps(DateTime(2026, 5, 8), DateTime(2026, 5, 11)), isTrue);
      expect(b.overlaps(DateTime(2026, 5, 12), DateTime(2026, 5, 15)), isTrue);
    });

    test('back-to-back stays do NOT overlap', () {
      // Arrive the day the previous guest leaves.
      expect(b.overlaps(DateTime(2026, 5, 13), DateTime(2026, 5, 15)), isFalse);
      // Leave the day the next guest arrives.
      expect(b.overlaps(DateTime(2026, 5, 7), DateTime(2026, 5, 10)), isFalse);
    });
  });

  group('Booking.customerCanCancel', () {
    final t = today();

    test('pending or approved, starting tomorrow or later: yes', () {
      for (final s in [BookingStatus.pending, BookingStatus.approved]) {
        final b = booking(
          checkIn: t.add(const Duration(days: 1)),
          checkOut: t.add(const Duration(days: 3)),
          status: s,
        );
        expect(b.customerCanCancel, isTrue, reason: s.name);
      }
    });

    test('starting today: no (server refuses on the check-in day)', () {
      final b = booking(checkIn: t, checkOut: t.add(const Duration(days: 2)));
      expect(b.customerCanCancel, isFalse);
    });

    test('already cancelled, checked in or checked out: no', () {
      for (final s in [
        BookingStatus.cancelled,
        BookingStatus.checkedIn,
        BookingStatus.checkedOut,
      ]) {
        final b = booking(
          checkIn: t.add(const Duration(days: 5)),
          checkOut: t.add(const Duration(days: 7)),
          status: s,
        );
        expect(b.customerCanCancel, isFalse, reason: s.name);
      }
    });
  });

  group('Booking.staffCanCheckIn', () {
    final t = today();

    test('approved, from the check-in day: yes', () {
      final b = booking(
        checkIn: t,
        checkOut: t.add(const Duration(days: 2)),
        status: BookingStatus.approved,
      );
      expect(b.staffCanCheckIn, isTrue);
    });

    test('approved, mid-stay: yes', () {
      final b = booking(
        checkIn: t.subtract(const Duration(days: 1)),
        checkOut: t.add(const Duration(days: 1)),
        status: BookingStatus.approved,
      );
      expect(b.staffCanCheckIn, isTrue);
    });

    test('approved but arriving tomorrow: no', () {
      final b = booking(
        checkIn: t.add(const Duration(days: 1)),
        checkOut: t.add(const Duration(days: 3)),
        status: BookingStatus.approved,
      );
      expect(b.staffCanCheckIn, isFalse);
    });

    test('approved but today is the check-out day: no', () {
      final b = booking(
        checkIn: t.subtract(const Duration(days: 2)),
        checkOut: t,
        status: BookingStatus.approved,
      );
      expect(b.staffCanCheckIn, isFalse);
    });

    test('not approved (still unpaid): no', () {
      final b = booking(checkIn: t, checkOut: t.add(const Duration(days: 2)));
      expect(b.staffCanCheckIn, isFalse);
    });
  });

  group('BookingStatus.wireName matches the API spelling', () {
    test('two-word statuses are snake_case', () {
      expect(BookingStatus.checkedIn.wireName, 'checked_in');
      expect(BookingStatus.checkedOut.wireName, 'checked_out');
    });

    test('one-word statuses are unchanged', () {
      expect(BookingStatus.pending.wireName, 'pending');
      expect(BookingStatus.approved.wireName, 'approved');
      expect(BookingStatus.cancelled.wireName, 'cancelled');
    });

    test('every status has a distinct wire name', () {
      final names = BookingStatus.values.map((s) => s.wireName).toSet();
      expect(names.length, BookingStatus.values.length);
    });
  });

  group('BookedRange', () {
    final r = BookedRange(
      roomId: 'r1',
      checkIn: DateTime(2026, 5, 10),
      checkOut: DateTime(2026, 5, 13),
    );

    test('covers the check-in day and the nights in between', () {
      expect(r.covers(DateTime(2026, 5, 10)), isTrue);
      expect(r.covers(DateTime(2026, 5, 12)), isTrue);
    });

    test('does not cover the check-out day (room is free that night)', () {
      expect(r.covers(DateTime(2026, 5, 13)), isFalse);
      expect(r.covers(DateTime(2026, 5, 9)), isFalse);
    });

    test('overlaps uses the same half-open rule as Booking', () {
      expect(r.overlaps(DateTime(2026, 5, 12), DateTime(2026, 5, 14)), isTrue);
      expect(r.overlaps(DateTime(2026, 5, 13), DateTime(2026, 5, 14)), isFalse);
    });

    test('fromJson reads the API shape', () {
      final parsed = BookedRange.fromJson({
        'roomId': 'abc',
        'checkIn': '2026-05-10',
        'checkOut': '2026-05-13',
      });
      expect(parsed.roomId, 'abc');
      expect(parsed.checkIn, DateTime(2026, 5, 10));
      expect(parsed.checkOut, DateTime(2026, 5, 13));
    });
  });

  group('Room', () {
    test('primaryImage is the first image, or empty when there are none', () {
      Room room(List<String> images) => Room(
            id: 'r',
            name: 'R',
            type: RoomType.single,
            pricePerNight: 1000,
            capacity: 2,
            description: '',
            imageUrls: images,
            amenities: const [],
          );
      expect(room(['a.jpg', 'b.jpg']).primaryImage, 'a.jpg');
      expect(room(const []).primaryImage, '');
    });
  });

  group('UserRole.isStaffSide', () {
    test('staff and admin use the back office, customers do not', () {
      expect(UserRole.customer.isStaffSide, isFalse);
      expect(UserRole.staff.isStaffSide, isTrue);
      expect(UserRole.admin.isStaffSide, isTrue);
    });
  });
}
