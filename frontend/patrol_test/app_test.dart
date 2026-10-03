import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:hotel_booking/main.dart' as app;

// Smoke test: app boots and lands on the login screen (no session restored).
// Extend with real flows (login, booking, forgot/reset password, hotel
// location) once this passes locally with `patrol test`.
void main() {
  patrolTest(
    'app launches and shows the login screen',
    ($) async {
      await app.main();
      await $.pumpAndSettle();

      expect($('Sign in'), findsOneWidget);
      expect($('Email'), findsOneWidget);
      expect($('Password'), findsOneWidget);
    },
  );
}
