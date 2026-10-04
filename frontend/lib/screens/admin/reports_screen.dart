import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/room/room_bloc.dart';
import '../../models/booking.dart';
import '../../models/report.dart';
import '../../models/room.dart';
import '../../repositories/repositories.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';

/// Must match MAX_RANGE_DAYS in backend/src/modules/reports/reports.service.ts.
const _maxRangeDays = 366;

/// Revenue and occupancy for a chosen date range, computed by the API
/// (`/api/staff/reports/*`), plus booking-status and inventory summaries from
/// the already-loaded blocs. Charts are plain widgets — no chart dependency.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTimeRange _range;
  RevenueGroupBy _groupBy = RevenueGroupBy.day;

  RevenueReport? _revenue;
  OccupancyReport? _occupancy;
  bool _loading = false;
  String? _error;

  /// Discards responses from a superseded request when the range changes
  /// faster than the API answers.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    );
    _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<ReportRepository>();
    try {
      final results = await Future.wait([
        repo.fetchRevenue(
          from: _range.start,
          to: _range.end,
          groupBy: _groupBy,
        ),
        repo.fetchOccupancy(from: _range.start, to: _range.end),
      ]);
      if (!mounted || id != _requestId) return;
      setState(() {
        _revenue = results[0] as RevenueReport;
        _occupancy = results[1] as OccupancyReport;
      });
    } on RepositoryException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    if (picked.duration.inDays + 1 > _maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a range of $_maxRangeDays days or less'),
        ),
      );
      return;
    }
    _range = picked;
    _load();
  }

  void _setGroupBy(RevenueGroupBy value) {
    if (value == _groupBy) return;
    _groupBy = value;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final revenue = _revenue;
    final occupancy = _occupancy;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _Filters(
            range: _range,
            groupBy: _groupBy,
            onPickRange: _pickRange,
            onGroupBy: _setGroupBy,
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
          const SizedBox(height: 12),
          if (revenue != null && occupancy != null) ...[
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width >= 720 ? 3 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                StatCard(
                  icon: Icons.payments,
                  label: 'Revenue',
                  value: Format.money(revenue.total),
                  color: Colors.green,
                ),
                StatCard(
                  icon: Icons.percent,
                  label: 'Occupancy',
                  value: '${occupancy.overall.rate.toStringAsFixed(1)}%',
                  color: Colors.purple,
                ),
                StatCard(
                  icon: Icons.receipt_long,
                  label: 'Paid bookings',
                  value: '${revenue.paidBookings}',
                  color: Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: revenue.groupBy == RevenueGroupBy.month
                  ? 'Monthly revenue'
                  : 'Daily revenue',
              child: _RevenueChart(report: revenue),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Occupancy by room type',
              child: _OccupancyBreakdown(report: occupancy),
            ),
            const SizedBox(height: 16),
          ],
          const _BookingStatusSection(),
          const SizedBox(height: 16),
          const _InventorySection(),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final DateTimeRange range;
  final RevenueGroupBy groupBy;
  final VoidCallback onPickRange;
  final ValueChanged<RevenueGroupBy> onGroupBy;

  const _Filters({
    required this.range,
    required this.groupBy,
    required this.onPickRange,
    required this.onGroupBy,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onPickRange,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(
            '${Format.date(range.start)} – ${Format.date(range.end)}',
          ),
        ),
        SegmentedButton<RevenueGroupBy>(
          segments: const [
            ButtonSegment(value: RevenueGroupBy.day, label: Text('Daily')),
            ButtonSegment(value: RevenueGroupBy.month, label: Text('Monthly')),
          ],
          selected: {groupBy},
          onSelectionChanged: (s) => onGroupBy(s.first),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
        title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
}

/// Vertical bars, one per period. Scrolls sideways when the bars would be
/// thinner than [_minSlot] (e.g. a long range grouped by day).
class _RevenueChart extends StatelessWidget {
  final RevenueReport report;

  const _RevenueChart({required this.report});

  static const _chartHeight = 160.0;
  static const _minSlot = 14.0;
  static const _labelWidth = 44.0;

  String _shortLabel(String period) => report.groupBy == RevenueGroupBy.month
      ? DateFormat('MMM yy').format(DateTime.parse('$period-01'))
      : DateFormat('d MMM').format(DateTime.parse(period));

  String _longLabel(String period) => report.groupBy == RevenueGroupBy.month
      ? DateFormat('MMMM yyyy').format(DateTime.parse('$period-01'))
      : Format.date(DateTime.parse(period));

  @override
  Widget build(BuildContext context) {
    final points = report.series;
    final maxRevenue = points.fold<double>(0, (m, p) => math.max(m, p.revenue));
    if (maxRevenue == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No paid stays in this range')),
      );
    }
    final barColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Peak ${Format.money(maxRevenue)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final slot = math.max(
              _minSlot,
              constraints.maxWidth / points.length,
            );
            final labelEvery = math.max(1, (_labelWidth / slot).ceil());
            final width = slot * points.length;

            final chart = SizedBox(
              width: width,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < points.length; i++)
                    SizedBox(
                      width: slot,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message:
                                '${_longLabel(points[i].period)}\n'
                                '${Format.money(points[i].revenue)}',
                            child: Container(
                              height: _chartHeight,
                              alignment: Alignment.bottomCenter,
                              padding: EdgeInsets.symmetric(
                                horizontal: math.min(4, slot * 0.15),
                              ),
                              child: Container(
                                height:
                                    _chartHeight *
                                    points[i].revenue /
                                    maxRevenue,
                                decoration: BoxDecoration(
                                  color: barColor,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          SizedBox(
                            height: 20,
                            child: i % labelEvery == 0
                                ? OverflowBox(
                                    maxWidth: _labelWidth * 1.5,
                                    child: Text(
                                      _shortLabel(points[i].period),
                                      style: const TextStyle(fontSize: 10),
                                      maxLines: 1,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );

            return width > constraints.maxWidth
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: chart,
                  )
                : chart;
          },
        ),
      ],
    );
  }
}

class _OccupancyBreakdown extends StatelessWidget {
  final OccupancyReport report;

  const _OccupancyBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RateRow(label: 'All rooms', stat: report.overall, bold: true),
        const Divider(),
        for (final type in RoomType.values)
          if (report.byType[type] != null)
            _RateRow(label: type.label, stat: report.byType[type]!),
        const SizedBox(height: 4),
        Text(
          'Booked room-nights ÷ sellable room-nights over ${report.days} '
          'days. Rooms under maintenance are excluded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _RateRow extends StatelessWidget {
  final String label;
  final OccupancyStat stat;
  final bool bold;

  const _RateRow({required this.label, required this.stat, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.bold : FontWeight.normal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$label · ${stat.rooms} '
                  '${stat.rooms == 1 ? 'room' : 'rooms'}',
                  style: TextStyle(fontWeight: weight),
                ),
              ),
              Text(
                '${stat.rate.toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stat.rate / 100,
              minHeight: 12,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Colors.purple),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stat.bookedNights} / ${stat.availableNights} room-nights',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BookingStatusSection extends StatelessWidget {
  const _BookingStatusSection();

  Color _statusColor(BookingStatus s) {
    switch (s) {
      case BookingStatus.approved:
        return Colors.green;
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.cancelled:
        return Colors.red;
      case BookingStatus.checkedIn:
        return Colors.blue;
      case BookingStatus.checkedOut:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingBloc>();
    final statusCounts = <BookingStatus, int>{
      BookingStatus.pending: bookings.pendingCount,
      BookingStatus.approved: bookings.approvedCount,
      BookingStatus.cancelled: bookings.cancelledCount,
      BookingStatus.checkedIn: bookings.checkedInCount,
      BookingStatus.checkedOut: bookings.checkedOutCount,
    };
    final maxCount = statusCounts.values.fold(0, (a, b) => a > b ? a : b);

    return _Section(
      title: 'Bookings by status (all time)',
      child: Column(
        children: statusCounts.entries.map((e) {
          return _BarRow(
            label: e.key.label,
            value: e.value,
            maxValue: maxCount,
            color: _statusColor(e.key),
          );
        }).toList(),
      ),
    );
  }
}

class _InventorySection extends StatelessWidget {
  const _InventorySection();

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomBloc>().allRooms;
    final available = rooms
        .where((r) => r.status == RoomStatus.available)
        .length;

    return _Section(
      title: 'Room inventory',
      child: Column(
        children: [
          _kv('Total rooms', '${rooms.length}'),
          _kv('Available', '$available'),
          _kv('Under maintenance', '${rooms.length - available}'),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;

  const _BarRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue == 0 ? 0.0 : value / maxValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 14,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
