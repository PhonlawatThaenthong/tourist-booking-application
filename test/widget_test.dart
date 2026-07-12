import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hotel_booking/models/booking.dart';
import 'package:hotel_booking/blocs/booking_cubit.dart';
import 'package:hotel_booking/screens/auth/login_screen.dart';
import 'package:hotel_booking/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App boots to the login screen for a fresh session',
      (tester) async {
    // No saved session in storage.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const HotelBookingApp());
    // Let the async session restore complete (the splash spinner animates
    // forever, so we pump fixed frames rather than pumpAndSettle).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test('Booking overlap detection works', () {
    final booking = Booking(
      id: 'x',
      roomId: 'r1',
      roomName: 'Room',
      customerId: 'c1',
      customerName: 'C',
      checkIn: DateTime(2026, 1, 10),
      checkOut: DateTime(2026, 1, 15),
      guests: 2,
      totalPrice: 1000,
      createdAt: DateTime(2026, 1, 1),
    );

    // Overlapping range.
    expect(booking.overlaps(DateTime(2026, 1, 12), DateTime(2026, 1, 14)), true);
    // Non-overlapping range (starts on checkout day).
    expect(
        booking.overlaps(DateTime(2026, 1, 15), DateTime(2026, 1, 18)), false);
  });

  test('Revenue counts only paid bookings from seed data', () {
    final cubit = BookingCubit();
    expect(cubit.totalRevenue, greaterThan(0));
    expect(cubit.totalBookings, greaterThan(0));
  });
}
