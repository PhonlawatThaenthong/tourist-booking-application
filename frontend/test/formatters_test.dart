import 'package:flutter_test/flutter_test.dart';

import 'package:hotel_booking/config.dart';
import 'package:hotel_booking/utils/formatters.dart';

/// Formatting shown to guests: prices, dates and distances.
void main() {
  group('Format.money', () {
    test('baht, thousands separator, no decimals', () {
      final s = Format.money(12500);
      expect(s, contains('฿'));
      expect(s, contains('12,500'));
      expect(s, isNot(contains('.')));
    });

    test('fractions are rounded to whole baht', () {
      expect(Format.money(1250.5), contains('1,251'));
      expect(Format.money(1250.4), contains('1,250'));
    });

    test('zero is still shown as a price', () {
      expect(Format.money(0), contains('0'));
      expect(Format.money(0), contains('฿'));
    });
  });

  group('Format.date / dateTime', () {
    test('date is day, short month, year', () {
      expect(Format.date(DateTime(2026, 11, 20)), '20 Nov 2026');
    });

    test('dateTime adds a 24-hour time', () {
      expect(Format.dateTime(DateTime(2026, 11, 20, 14, 5)), '20 Nov 2026, 14:05');
    });
  });

  group('Format.checkIn / checkOut', () {
    test('use the resort\'s published check-in and check-out times', () {
      final day = DateTime(2026, 11, 20);
      expect(Format.checkIn(day), '20 Nov 2026, ${AppConfig.checkInTime}');
      expect(Format.checkOut(day), '20 Nov 2026, ${AppConfig.checkOutTime}');
    });
  });

  group('Format.distance', () {
    test('under a kilometre is metres rounded to the nearest 10', () {
      expect(Format.distance(0.214), '210 m');
      expect(Format.distance(0.216), '220 m');
      expect(Format.distance(0.0), '0 m');
    });

    test('a kilometre or more is km with one decimal', () {
      expect(Format.distance(1.0), '1.0 km');
      expect(Format.distance(1.44), '1.4 km');
      expect(Format.distance(12.35), contains('km'));
    });
  });
}
