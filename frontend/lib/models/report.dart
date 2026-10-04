import 'room.dart';

enum RevenueGroupBy { day, month }

class RevenuePoint {
  /// `YYYY-MM-DD` for daily reports, `YYYY-MM` for monthly ones.
  final String period;
  final double revenue;

  const RevenuePoint({required this.period, required this.revenue});

  factory RevenuePoint.fromJson(Map<String, dynamic> json) => RevenuePoint(
    period: json['period'] as String,
    revenue: (json['revenue'] as num).toDouble(),
  );
}

/// `GET /api/staff/reports/revenue` — revenue from paid bookings, spread
/// evenly over the nights stayed.
class RevenueReport {
  final RevenueGroupBy groupBy;
  final double total;
  final int paidBookings;
  final List<RevenuePoint> series;

  const RevenueReport({
    required this.groupBy,
    required this.total,
    required this.paidBookings,
    required this.series,
  });

  factory RevenueReport.fromJson(Map<String, dynamic> json) => RevenueReport(
    groupBy: json['groupBy'] == 'month'
        ? RevenueGroupBy.month
        : RevenueGroupBy.day,
    total: (json['total'] as num).toDouble(),
    paidBookings: (json['paidBookings'] as num).toInt(),
    series: (json['series'] as List<dynamic>)
        .map((e) => RevenuePoint.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class OccupancyStat {
  final int rooms;
  final int availableNights;
  final int bookedNights;

  /// Percentage, 0–100.
  final double rate;

  const OccupancyStat({
    required this.rooms,
    required this.availableNights,
    required this.bookedNights,
    required this.rate,
  });

  factory OccupancyStat.fromJson(Map<String, dynamic> json) => OccupancyStat(
    rooms: (json['rooms'] as num).toInt(),
    availableNights: (json['availableNights'] as num).toInt(),
    bookedNights: (json['bookedNights'] as num).toInt(),
    rate: (json['rate'] as num).toDouble(),
  );
}

/// `GET /api/staff/reports/occupancy` — booked / sellable room-nights.
class OccupancyReport {
  final int days;
  final OccupancyStat overall;
  final Map<RoomType, OccupancyStat> byType;

  const OccupancyReport({
    required this.days,
    required this.overall,
    required this.byType,
  });

  factory OccupancyReport.fromJson(Map<String, dynamic> json) {
    final byType = <RoomType, OccupancyStat>{};
    for (final raw in json['byType'] as List<dynamic>) {
      final m = raw as Map<String, dynamic>;
      final type = RoomType.values.where((t) => t.name == m['type']);
      if (type.isNotEmpty) byType[type.first] = OccupancyStat.fromJson(m);
    }
    return OccupancyReport(
      days: (json['days'] as num).toInt(),
      overall: OccupancyStat.fromJson(json['overall'] as Map<String, dynamic>),
      byType: byType,
    );
  }
}
