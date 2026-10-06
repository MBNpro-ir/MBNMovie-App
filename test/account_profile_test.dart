import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/services/account_profile.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/widgets/account_profile_panel.dart';

Map<String, dynamic> profile() => {
  'name': 'نام کاربر',
  'gender': 'unset',
  'epoch': 0,
  'avatar_url': '',
  'ring_color': '#38BDF8',
  'stats': {'watch_ms': 3600000, 'movies': 1, 'episodes': 2, 'series': 1},
  'badges': [
    {'id': 'first_hour', 'title': 'شروع ماجراجویی', 'color': '#38BDF8'},
  ],
};
String token(int id) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': '$id'})))}.sig';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountProfile.configure(null);
  });
  test(
    'failed uploads retain receipts; retries preserve receipts and isolate accounts',
    () async {
      var failed = true;
      final received = <String>{};
      final client = MbnAuth(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            if (failed) return http.Response('{"error":"offline"}', 503);
            final body = jsonDecode(request.body) as Map;
            for (final e in body['events'] as List) {
              received.add('${e['id']}');
            }
          }
          return http.Response(
            jsonEncode({'profile': profile()}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..token = token(10);
      AccountProfile.configure(client);
      await AccountProfile.reload();
      await AccountProfile.record(
        'house',
        's1e2',
        'series',
        30000,
        expectedOwner: 10,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('mbn_watch_receipts_movie_10')!) as List,
        hasLength(1),
      );
      failed = false;
      await AccountProfile.flush();
      expect(received, hasLength(1));
      expect(
        jsonDecode(prefs.getString('mbn_watch_receipts_movie_10')!) as List,
        isEmpty,
      );
      client.token = token(11);
      AccountProfile.configure(client);
      await AccountProfile.reload();
      await AccountProfile.record(
        'house',
        's1e2',
        'series',
        30000,
        expectedOwner: 10,
      );
      expect(prefs.getString('mbn_watch_receipts_movie_11'), isNull);
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1440, 900),
  ]) {
    testWidgets('profile panel fits and saves optional gender at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = profile();
      final client = MbnAuth(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          if (request.method == 'PUT') {
            p.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return http.Response(
            jsonEncode({'profile': p}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..token = token(10);
      AccountProfile.configure(client);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(children: const [AccountProfilePanel()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('نام کاربر'), findsOneWidget);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('زن').last);
      await tester.pumpAndSettle();
      expect(AccountProfile.current.value['gender'], 'female');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
