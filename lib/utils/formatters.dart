import 'package:intl/intl.dart';

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
}
