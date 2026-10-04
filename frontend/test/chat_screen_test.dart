import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hotel_booking/blocs/chat/chat_bloc.dart';
import 'package:hotel_booking/repositories/api/api_repositories.dart';
import 'package:hotel_booking/screens/customer/chat_screen.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late http.Response Function() respond;

  final api = MockClient((request) async {
    sent.add(jsonDecode(request.body) as Map<String, dynamic>);
    return respond();
  });

  setUp(() {
    sent = [];
    respond = () => http.Response(
          jsonEncode({
            'sessionId': 'sess-1',
            'answer': 'มีห้องว่าง 2 ห้องค่ะ',
            'answered': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
  });

  Widget harness() => MaterialApp(
        home: BlocProvider(
          create: (_) =>
              ChatBloc(ApiChatbotRepository(ApiClient(httpClient: api))),
          child: const ChatScreen(),
        ),
      );

  testWidgets('asks the backend and shows the answer, reusing the session',
      (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('สวัสดีค่ะ มีอะไรให้ช่วยไหมคะ'), findsOneWidget);

    await tester.tap(find.text(ChatScreen.suggestions.first));
    await tester.pumpAndSettle();

    expect(find.text(ChatScreen.suggestions.first), findsOneWidget);
    expect(find.text('มีห้องว่าง 2 ห้องค่ะ'), findsOneWidget);
    expect(sent.single, {
      'message': ChatScreen.suggestions.first,
      'language': 'th',
    });

    await tester.enterText(find.byType(TextField), 'Is there a pool?');
    await tester.pump(); // the send button enables on the next frame
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent.last, {
      'message': 'Is there a pool?',
      'sessionId': 'sess-1',
      'language': 'en',
    });
  });

  testWidgets('shows the backend error and lets the question be retried',
      (tester) async {
    respond = () => http.Response(
          jsonEncode({
            'statusCode': 503,
            'message': 'แชทบอทไม่พร้อมใช้งานชั่วคราว',
          }),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'ห้องว่างไหม');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('แชทบอทไม่พร้อมใช้งานชั่วคราว'), findsOneWidget); // snackbar
    expect(find.text('ส่งไม่สำเร็จ แตะเพื่อลองใหม่'), findsOneWidget);

    respond = () => http.Response(
          jsonEncode({'sessionId': 's', 'answer': 'ว่างค่ะ', 'answered': true}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    await tester.tap(find.text('ส่งไม่สำเร็จ แตะเพื่อลองใหม่'));
    await tester.pumpAndSettle();

    expect(find.text('ส่งไม่สำเร็จ แตะเพื่อลองใหม่'), findsNothing);
    expect(find.text('ว่างค่ะ'), findsOneWidget);
    expect(sent.length, 2);
  });

  test('languageOf picks th for any Thai letter, en otherwise', () {
    expect(languageOf('ห้องว่างไหม'), 'th');
    expect(languageOf('room ว่าง?'), 'th');
    expect(languageOf('Is there a pool?'), 'en');
  });
}
