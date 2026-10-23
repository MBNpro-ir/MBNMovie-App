import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/services/network_gate.dart';
import 'package:mbnmovie/widgets/server_status_gate.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native outage warning cancels and resumes the existing app', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: MovieTheme.dark,
        navigatorKey: navigatorKey,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: ServerStatusGate(
            client: MockClient((_) => response.future),
            child: child!,
          ),
        ),
        home: const Scaffold(body: Center(child: Text('local app'))),
      ),
    );
    await tester.pumpAndSettle();
    final originalNavigator = navigatorKey.currentState!;
    var taps = 0;
    unawaited(
      originalNavigator.push(
        MaterialPageRoute<void>(
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => setState(() => taps++),
                  child: Text('local page: $taps'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('local page: 0'));
    await tester.pumpAndSettle();

    response.completeError(http.ClientException('simulated central outage'));
    await tester.pumpAndSettle();
    expect(find.text('سرور در دسترس نیست'), findsOneWidget);
    expect(find.text('local page: 1'), findsNothing);
    await tester.tap(find.text('ادامه دادن'));
    await tester.pumpAndSettle();
    expect(find.text('ادامه در حالت آفلاین'), findsOneWidget);
    expect(find.textContaining('ذخیره یا همگام نشوند'), findsOneWidget);
    expect(OfflineMode.active, isFalse);
    await tester.tap(find.text('لغو'));
    await tester.pumpAndSettle();
    expect(find.text('سرور در دسترس نیست'), findsOneWidget);
    expect(OfflineMode.active, isFalse);

    await tester.tap(find.text('ادامه دادن'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('ادامه دادن'),
      ),
    );
    await tester.pumpAndSettle();
    expect(OfflineMode.active, isTrue);
    expect(navigatorKey.currentState, same(originalNavigator));
    expect(find.text('local page: 1'), findsOneWidget);
    await tester.tap(find.text('local page: 1'));
    await tester.pumpAndSettle();
    expect(find.text('local page: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(OfflineMode.active, isFalse);
  });
}
