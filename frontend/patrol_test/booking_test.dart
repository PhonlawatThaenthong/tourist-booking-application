import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:hotel_booking/models/room.dart';
import 'package:hotel_booking/screens/customer/date_selection_screen.dart';
import 'package:hotel_booking/screens/customer/room_search_screen.dart';
import 'package:hotel_booking/utils/formatters.dart';
import 'package:hotel_booking/widgets/room_card.dart';

import 'support/app_helpers.dart';

// Customer booking flow against the real API. Needs `npm run seed:rooms` so
// there is inventory to book. See support/app_helpers.dart.
//
// The flow stops at the payment screen: uploading a slip opens the system
// gallery, and approving it is a staff action — both outside this suite.
// The pending hold it creates is released by the backend after
// BOOKING_HOLD_MINUTES.
void main() {
  patrolTest('search: rooms are only listed after dates are chosen', ($) async {
    await launchApp($);
    await signInAsCustomer($);

    await $(RoomSearchScreen).waitUntilExists();
    expect($('Select your dates to see available rooms'), findsOneWidget);
    expect($(RoomCard), findsNothing);

    await $('Select dates').first.tap();
    await $(DateSelectionScreen).waitUntilExists();
    await pickStay($, randomFutureStay());

    await $(RoomCard).first.waitUntilVisible(timeout: netTimeout);
    expect($(RegExp(r'room\(s\) available')), findsOneWidget);
  });

  patrolTest('booking: customer books a room and sees it pending', ($) async {
    final stay = randomFutureStay();
    final dateLine = '${Format.date(stay.start)} → ${Format.date(stay.end)}';

    await launchApp($);
    await signInAsCustomer($);

    // 1. Search: choose dates.
    await $('Select dates').first.tap();
    await pickStay($, stay);
    await $(RoomCard).first.waitUntilVisible(timeout: netTimeout);

    // Remember which room we pick so later screens can be checked against it.
    final Room room =
        $.tester.widget<RoomCard>(find.byType(RoomCard).first).room;
    final total = Format.money(room.pricePerNight * 2);

    // 2. Room detail.
    await $(RoomCard).first.tap();
    await $('About this room').waitUntilVisible();
    expect($(room.name), findsWidgets);
    await $('Book now').tap();

    // 3. Review booking: dates carried over, 2 nights priced correctly.
    await $('Review booking').waitUntilVisible();
    expect($(RegExp(r'\(2 nights\)')), findsOneWidget);
    expect($(total), findsWidgets);
    await $(RegExp('^Continue to payment'))
        .tap(settlePolicy: SettlePolicy.noSettle);

    // 4. Payment: the booking is created on the API and a hold starts.
    //    The countdown ticks every second, so nothing here may wait to settle.
    await $('Amount due').waitUntilVisible(timeout: netTimeout);
    await $('Upload payment slip').waitUntilVisible();
    expect($('Pay and upload your slip within'), findsOneWidget);
    expect($(total), findsWidgets);

    // 5. Back out to the customer shell.
    await tapBack($); // Payment -> Review booking
    await tapBack($); // Review booking -> Room detail
    await tapBack($); // Room detail -> Search
    await $(RoomSearchScreen).waitUntilExists();

    // 6. My bookings lists the new booking as Pending / Unpaid.
    await $('Bookings').tap();
    final card = $(Card).containing(dateLine).containing(room.name);
    await $('My bookings').waitUntilVisible();
    await card.waitUntilExists(timeout: netTimeout);
    await card.scrollTo();
    expect(card.containing('Pending'), findsOneWidget);
    expect(card.containing('Unpaid'), findsOneWidget);
    expect(card.containing('Pay / upload slip'), findsOneWidget);
  });
}
