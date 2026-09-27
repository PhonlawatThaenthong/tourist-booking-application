import 'package:intl/intl.dart';

import '../config.dart';

/// Centralised formatting so currency and dates look consistent app-wide.
class Format {
  Format._();

  static final NumberFormat _currency =
      NumberFormat.currency(locale: 'th_TH', symbol: '฿', decimalDigits: 0);
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');

  static String money(num value) => _currency.format(value);
  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);

  /// A stay's scheduled arrival / departure, e.g. "20 Nov 2026, 14:00" —
  /// the same shape as [dateTime].
  static String checkIn(DateTime day) =>
      '${date(day)}, ${AppConfig.checkInTime}';
  static String checkOut(DateTime day) =>
      '${date(day)}, ${AppConfig.checkOutTime}';
}
