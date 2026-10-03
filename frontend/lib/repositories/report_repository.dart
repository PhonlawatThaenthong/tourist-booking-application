import '../models/report.dart';

/// Back-office reports. Both ranges are inclusive calendar days.
///
/// Backend endpoints:
///  * `GET /api/staff/reports/revenue?from=&to=&groupBy=` — [fetchRevenue]
///  * `GET /api/staff/reports/occupancy?from=&to=`        — [fetchOccupancy]
abstract class ReportRepository {
  Future<RevenueReport> fetchRevenue({
    required DateTime from,
    required DateTime to,
    RevenueGroupBy groupBy = RevenueGroupBy.day,
  });

  Future<OccupancyReport> fetchOccupancy({
    required DateTime from,
    required DateTime to,
  });
}
