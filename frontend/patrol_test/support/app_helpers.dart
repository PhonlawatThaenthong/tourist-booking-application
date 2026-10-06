// Shared helpers for the Patrol e2e suite.
//
// These tests run against the REAL NestJS backend. Before `patrol test`:
//   1. Start the API (and its DB/Redis) so the emulator can reach it.
//   2. Seed rooms (npm run seed:rooms) and create the two test accounts
//      below. seed:users no longer exists, so register them through the API
//      and promote the staff one — the CI workflow does exactly this, see
//      .github/workflows/frontend-e2e.yml ("Create e2e accounts").
//   3. Point the app at the host machine from the emulator:
//        patrol test --dart-define=API_BASE_URL=http://10.0.2.2:3000
//
// The account credentials default to the values below and can be overridden
// with --dart-define=E2E_CUSTOMER_EMAIL=... (and _PASSWORD, E2E_STAFF_*).
//
// Each test starts from a clean install (clearPackageData=true in
// build.gradle.kts), so every test launches the app signed out.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

import 'package:hotel_booking/main.dart' as app;
import 'package:hotel_booking/screens/auth/login_screen.dart';

/// Network-bound steps (login, fetching rooms, creating a booking) get more
/// time than Patrol's default wait.
const netTimeout = Duration(seconds: 20);

/// Test accounts the suite signs in with. They must already exist in the
/// backend (see the header comment).
class DemoAccount {
  const DemoAccount(this.email, this.password);
  final String email;
  final String password;
}

const customerAccount = DemoAccount(
  String.fromEnvironment('E2E_CUSTOMER_EMAIL',
      defaultValue: 'customer@hotel.com'),
  String.fromEnvironment('E2E_CUSTOMER_PASSWORD', defaultValue: 'customer123'),
);
const staffAccount = DemoAccount(
  String.fromEnvironment('E2E_STAFF_EMAIL', defaultValue: 'staff@hotel.com'),
  String.fromEnvironment('E2E_STAFF_PASSWORD', defaultValue: 'staff123'),
);

/// Boots the real app and waits until the signed-out login screen is shown.
Future<void> launchApp(PatrolIntegrationTester $) async {
  await app.main();
  await $(LoginScreen).waitUntilExists(timeout: netTimeout);
}

/// A form field located by its label text, e.g. `field($, 'Email')`.
PatrolFinder field(PatrolIntegrationTester $, String label) =>
    $(TextFormField).containing(label);

/// Dismisses the soft keyboard so buttons under it become tappable.
Future<void> hideKeyboard(PatrolIntegrationTester $) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pump(const Duration(milliseconds: 300));
}

/// Fills the login form and submits it. Does not wait for the result.
Future<void> submitLogin(
  PatrolIntegrationTester $,
  String email,
  String password,
) async {
  await field($, 'Email').enterText(email);
  await field($, 'Password').enterText(password);
  await hideKeyboard($);
  await $('Sign in').scrollTo().tap();
}

/// Signs in as the seeded customer and waits for the customer shell.
Future<void> signInAsCustomer(PatrolIntegrationTester $) async {
  await submitLogin($, customerAccount.email, customerAccount.password);
  await $(NavigationBar).waitUntilVisible(timeout: netTimeout);
}

/// An email that has never been registered, so register tests can re-run.
String uniqueEmail() =>
    'e2e_${DateTime.now().millisecondsSinceEpoch}@example.com';

/// A 2-night stay on a random future date, so repeated runs rarely collide
/// with a hold left by an earlier run (holds expire after
/// BOOKING_HOLD_MINUTES anyway). Check-in and check-out are in the same month
/// to keep calendar navigation simple.
DateTimeRange randomFutureStay() {
  final rnd = Random();
  final now = DateTime.now();
  final month = DateTime(now.year, now.month + 2 + rnd.nextInt(9));
  final checkIn = DateTime(month.year, month.month, 5 + rnd.nextInt(16));
  return DateTimeRange(
    start: checkIn,
    end: checkIn.add(const Duration(days: 2)),
  );
}

/// Drives DateSelectionScreen (must already be open, showing the current
/// month) to [stay] and confirms.
Future<void> pickStay(PatrolIntegrationTester $, DateTimeRange stay) async {
  final now = DateTime.now();
  final monthsAhead = (stay.start.year * 12 + stay.start.month) -
      (now.year * 12 + now.month);
  for (var i = 0; i < monthsAhead; i++) {
    await $(Icons.chevron_right).tap();
  }
  await $('${stay.start.day}').tap();
  await $('${stay.end.day}').tap();
  await $('Confirm dates').tap();
}

/// Taps the AppBar back arrow without waiting for the UI to settle — needed
/// on screens with a running timer (the payment countdown), which never
/// settle.
Future<void> tapBack(PatrolIntegrationTester $) async {
  await $(BackButton).tap(settlePolicy: SettlePolicy.noSettle);
  await $.pump(const Duration(milliseconds: 600));
}
