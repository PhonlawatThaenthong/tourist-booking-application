import '../../models/report.dart';
import '../report_repository.dart';
import 'api_client.dart';

class ApiReportRepository implements ReportRepository {
  ApiReportRepository(this._api);

  final ApiClient _api;

  @override
  Future<RevenueReport> fetchRevenue({
    required DateTime from,
    required DateTime to,
    RevenueGroupBy groupBy = RevenueGroupBy.day,
  }) async {
    final data =
        await _api.get(
              '/api/staff/reports/revenue',
              query: {
                'from': ymd(from),
                'to': ymd(to),
                'groupBy': groupBy.name,
              },
            )
            as Map<String, dynamic>;
    return RevenueReport.fromJson(data);
  }

  @override
  Future<OccupancyReport> fetchOccupancy({
    required DateTime from,
    required DateTime to,
  }) async {
    final data =
        await _api.get(
              '/api/staff/reports/occupancy',
              query: {'from': ymd(from), 'to': ymd(to)},
            )
            as Map<String, dynamic>;
    return OccupancyReport.fromJson(data);
  }
}
