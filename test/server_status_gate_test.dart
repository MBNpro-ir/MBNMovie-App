import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mbnmovie/widgets/server_status_gate.dart';

void main() {
  tearDown(() {
    ServerStatusGate.bypassForTesting = false;
  });

  testWidgets('does not block taps while the status probe is pending', (
    tester,
  ) async {
    var taps = 0;
    ServerStatusGate.bypassForTesting = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerStatusGate(
          // Port 1 has no listener in the test environment, so this remains
          // in `checking` long enough to exercise the first-frame behavior.
          baseUrl: 'http://127.0.0.1:1',
          child: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('لمس'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('لمس'));
    await tester.pump();
    expect(taps, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offers confirmed offline mode after a failed probe', (
    tester,
  ) async {
    final client = MockClient((_) async {
      throw http.ClientException('offline');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ServerStatusGate(client: client, child: const Text('local app')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('سرور در دسترس نیست'), findsOneWidget);
    expect(find.text('ادامه دادن'), findsOneWidget);
    await tester.tap(find.text('ادامه دادن'));
    await tester.pump();
    expect(find.text('ادامه در حالت آفلاین'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'ادامه دادن').last);
    await tester.pump();
    expect(find.text('local app'), findsOneWidget);
  });
}
