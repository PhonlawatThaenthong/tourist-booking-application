import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:hotel_booking/screens/admin/admin_home.dart';
import 'package:hotel_booking/screens/auth/login_screen.dart';
import 'package:hotel_booking/screens/customer/customer_home.dart';

import 'support/app_helpers.dart';

// Authentication flows against the real API. See support/app_helpers.dart
// for the backend prerequisites.
void main() {
  patrolTest('login: empty form shows client-side validation', ($) async {
    await launchApp($);

    await $('Sign in').scrollTo().tap();

    expect($('Enter a valid email'), findsOneWidget);
    expect($('Enter your password'), findsOneWidget);
    expect($(CustomerHome), findsNothing);
  });

  patrolTest('login: wrong password shows the API error and stays signed out',
      ($) async {
    await launchApp($);

    await submitLogin($, customerAccount.email, 'wrong-password');

    await $('อีเมลหรือรหัสผ่านไม่ถูกต้อง').waitUntilVisible(timeout: netTimeout);
    expect($(LoginScreen), findsOneWidget);
    expect($(CustomerHome), findsNothing);
  });

  patrolTest('login: customer signs in, sees own profile, then signs out',
      ($) async {
    await launchApp($);

    await signInAsCustomer($);
    expect($(CustomerHome), findsOneWidget);

    await $(NavigationBar).$('Profile').tap();
    await $(customerAccount.email).waitUntilVisible();

    await $('Sign out').scrollTo().tap();
    await $(LoginScreen).waitUntilExists(timeout: netTimeout);
    expect($(CustomerHome), findsNothing);
  });

  patrolTest('login: staff account is routed to the back-office', ($) async {
    await launchApp($);

    await submitLogin($, staffAccount.email, staffAccount.password);

    await $(AdminHome).waitUntilExists(timeout: netTimeout);
    expect($(CustomerHome), findsNothing);
  });

  patrolTest('register: mismatched confirmation is rejected on the client',
      ($) async {
    await launchApp($);
    await $("Don't have an account? Sign up").scrollTo().tap();
    await $('Create account').first.waitUntilVisible();

    await field($, 'Full name').enterText('E2E Mismatch');
    await field($, 'Email').enterText(uniqueEmail());
    await field($, 'Phone number').enterText('0812345678');
    await field($, 'Password').enterText('e2ePass123');
    await field($, 'Confirm password').enterText('different123');
    await hideKeyboard($);
    await $(FilledButton).$('Create account').scrollTo().tap();

    expect($('Passwords do not match'), findsOneWidget);
    expect($(CustomerHome), findsNothing);
  });

  patrolTest('register: new customer account is created and signed in',
      ($) async {
    final email = uniqueEmail();
    await launchApp($);
    await $("Don't have an account? Sign up").scrollTo().tap();
    await $('Create account').first.waitUntilVisible();

    await field($, 'Full name').enterText('E2E Customer');
    await field($, 'Email').enterText(email);
    await field($, 'Phone number').enterText('0812345678');
    // Backend requires >= 8 characters (RegisterDto).
    await field($, 'Password').enterText('e2ePass123');
    await field($, 'Confirm password').enterText('e2ePass123');
    await hideKeyboard($);
    await $(FilledButton).$('Create account').scrollTo().tap();

    await $(CustomerHome).waitUntilExists(timeout: netTimeout);
    await $(NavigationBar).$('Profile').tap();
    await $(email).waitUntilVisible();
    expect($('E2E Customer'), findsOneWidget);
  });

  patrolTest('forgot password: request code, then a wrong code is rejected',
      ($) async {
    // An unregistered address: the API answers the same either way (no
    // account enumeration), and no real mail is sent to a demo user.
    const email = 'nobody-e2e@example.com';
    await launchApp($);

    await $('Forgot password?').scrollTo().tap();
    await field($, 'Email').enterText(email);
    await hideKeyboard($);
    await $('Send code').tap();

    await $('Reset password').first.waitUntilVisible(timeout: netTimeout);
    expect($(RegExp(RegExp.escape(email))), findsOneWidget);

    await field($, 'Verification code').enterText('000000');
    await field($, 'New password').enterText('newPass1234');
    await field($, 'Confirm new password').enterText('newPass1234');
    await hideKeyboard($);
    await $(FilledButton).$('Reset password').scrollTo().tap();

    await $('รหัสยืนยันไม่ถูกต้องหรือหมดอายุ')
        .waitUntilVisible(timeout: netTimeout);
  });
}
