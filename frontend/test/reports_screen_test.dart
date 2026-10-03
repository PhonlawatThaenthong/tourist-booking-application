import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hotel_booking/blocs/booking/booking_bloc.dart';
import 'package:hotel_booking/blocs/room/room_bloc.dart';
import 'package:hotel_booking/repositories/api/api_repositories.dart';
import 'package:hotel_booking/repositories/mock/mock_repositories.dart';
import 'package:hotel_booking/repositories/repositories.dart';
import 'package:hotel_booking/screens/admin/reports_screen.dart';

void main() {
  final requested = <Uri>[];

  // Shapes copied from the live API's responses.
  final api = MockClient((request) async {
    requested.add(request.url);
    if (request.url.path.endsWith('/revenue')) {
      final days = List.generate(30, (i) => {
            'period': '2026-09-${(i + 1).toString().padLeft(2, '0')}',
            'revenue': i % 3 == 0 ? 1300.0 : 0.0,
          });
      return http.Response(
        jsonEncode({
          'from': '2026-09-01',
          'to': '2026-09-30',
          'groupBy': 'day',
          'total': 13000,
          'paidBookings': 4,
          'series': days,
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'from': '2026-09-01',
        'to': '2026-09-30',
        'days': 30,
        'overall': {'rooms': 6, 'availableNights': 180, 'bookedNights': 10, 'rate': 5.6},
        'byType': [
          {'type': 'single', 'rooms': 4, 'availableNights': 120, 'bookedNights': 8, 'rate': 6.7},
          {'type': 'twin', 'rooms': 2, 'availableNights': 60, 'bookedNights': 2, 'rate': 3.3},
        ],
      }),
      200,
    );
  });

  Widget harness() => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ReportRepository>(
            create: (_) => ApiReportRepository(ApiClient(httpClient: api)),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => BookingBloc(MockBookingRepository())),
            BlocProvider(create: (_) => RoomBloc(MockRoomRepository())),
          ],
          child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
        ),
      );

  testWidgets('shows server revenue, chart and occupancy by type on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(requested.map((u) => u.path), containsAll([
      '/api/staff/reports/revenue',
      '/api/staff/reports/occupancy',
    ]));
    expect(requested.first.queryParameters['groupBy'], 'day');

    expect(find.text('5.6%'), findsWidgets);
    expect(find.text('Daily revenue'), findsOneWidget);
    expect(find.textContaining('Peak'), findsOneWidget);

    // The chart scrolls sideways too, so name the page's vertical list.
    await tester.scrollUntilVisible(
      find.text('Occupancy by room type'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Single · 4 rooms'), findsOneWidget);
    expect(find.textContaining('Twin · 2 rooms'), findsOneWidget);
    expect(find.text('2 / 60 room-nights'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to Monthly re-requests with groupBy=month',
      (tester) async {
    requested.clear();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    expect(
      requested.where((u) => u.path.endsWith('/revenue')).last.queryParameters['groupBy'],
      'month',
    );
  });
}
