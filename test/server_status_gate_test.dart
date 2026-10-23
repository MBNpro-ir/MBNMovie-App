import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mbnmovie/services/network_gate.dart';
import 'package:mbnmovie/widgets/server_status_gate.dart';

const _continue = 'ادامه دادن';
const _warning = 'ادامه در حالت آفلاین';

Finder _continueButtons() => find.ancestor(
  of: find.text(_continue),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

http.Client _offlineClient() => MockClient((_) async {
  throw http.ClientException('offline');
});

Widget _app(
  http.Client client, {
  Widget? home,
  GlobalKey<NavigatorState>? key,
}) {
  // Match production: the status gate wraps, rather than lives inside, the
  // app Navigator. A home-only harness misses the missing-Navigator failure.
  return MaterialApp(
    navigatorKey: key,
    builder: (context, child) =>
        ServerStatusGate(client: client, child: child!),
    home: home ?? const Scaffold(body: Text('local app')),
  );
}

Future<void> _confirmOffline(WidgetTester tester) async {
  await tester.tap(find.text(_continue));
  await tester.pumpAndSettle();
  expect(find.text(_warning), findsOneWidget);
  await tester.tap(_continueButtons().last);
  await tester.pumpAndSettle();
  expect(OfflineMode.active, isTrue);
}

void main() {
  tearDown(() {
    ServerStatusGate.bypassForTesting = false;
    OfflineMode.leave();
  });

  testWidgets('does not block taps while a real status probe is pending', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        MockClient((_) => response.future),
        home: Scaffold(
          body: TextButton(onPressed: () => taps++, child: const Text('tap')),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    expect(taps, 1);
    response.complete(http.Response('{"maintenance":{"enabled":false}}', 200));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('production builder opens a red warning and confirms entry', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_offlineClient()));
    await tester.pumpAndSettle();

    final continueButton = tester.widget<FilledButton>(_continueButtons());
    expect(
      continueButton.style!.backgroundColor!.resolve({}),
      const Color(0xFFEF4444),
    );
    await tester.tap(find.text(_continue));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(_warning), findsOneWidget);
    expect(find.textContaining('ذخیره یا همگام نشوند'), findsOneWidget);
    expect(OfflineMode.active, isFalse);
    final confirmation = tester.widget<FilledButton>(_continueButtons().last);
    expect(
      confirmation.style!.backgroundColor!.resolve({}),
      const Color(0xFFEF4444),
    );
    await tester.tap(_continueButtons().last);
    await tester.pumpAndSettle();
    expect(find.text('local app'), findsOneWidget);
    expect(find.text(_warning), findsNothing);
    expect(OfflineMode.active, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(OfflineMode.active, isFalse);
  }, skip: kIsWeb);

  testWidgets('cancel and back leave the outage screen usable', (tester) async {
    await tester.pumpWidget(_app(_offlineClient()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_continue));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لغو'));
    await tester.pumpAndSettle();
    expect(OfflineMode.active, isFalse);
    expect(find.text('سرور در دسترس نیست'), findsOneWidget);

    await tester.tap(find.text(_continue));
    await tester.pumpAndSettle();
    final warningContext = tester.element(find.byType(AlertDialog));
    await Navigator.of(warningContext).maybePop();
    await tester.pumpAndSettle();
    expect(find.text(_warning), findsNothing);
    expect(OfflineMode.active, isFalse);
    await _confirmOffline(tester);
    await tester.pumpWidget(const SizedBox());
  }, skip: kIsWeb);

  testWidgets('rapid repeated taps only open one warning', (tester) async {
    await tester.pumpWidget(_app(_offlineClient()));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(_continueButtons());
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('لغو'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, skip: kIsWeb);

  testWidgets('offline entry preserves the app Navigator and current route', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final appNavigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(MockClient((_) => response.future), key: appNavigator),
    );
    final originalNavigator = appNavigator.currentState!;
    var position = 20;
    unawaited(
      originalNavigator.push(
        MaterialPageRoute<void>(
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: TextButton(
                onPressed: () => setState(() => position++),
                child: Text('watching $position'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('watching 20'));
    await tester.pumpAndSettle();

    response.completeError(http.ClientException('offline'));
    await tester.pumpAndSettle();
    expect(find.text('watching 21'), findsNothing);
    expect(appNavigator.currentState, same(originalNavigator));
    await _confirmOffline(tester);
    expect(appNavigator.currentState, same(originalNavigator));
    expect(find.text('watching 21'), findsOneWidget);
    await tester.tap(find.text('watching 21'));
    await tester.pumpAndSettle();
    expect(find.text('watching 22'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, skip: kIsWeb);

  for (final succeeds in [false, true]) {
    testWidgets('a late retry (success=$succeeds) cannot undo offline entry', (
      tester,
    ) async {
      var requests = 0;
      final retryResponse = Completer<http.Response>();
      final client = MockClient((_) {
        requests++;
        if (requests == 1) throw http.ClientException('offline');
        return retryResponse.future;
      });
      await tester.pumpWidget(_app(client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تلاش مجدد'));
      await tester.pump();
      expect(requests, 2);
      await _confirmOffline(tester);

      if (succeeds) {
        retryResponse.complete(
          http.Response('{"maintenance":{"enabled":false}}', 200),
        );
      } else {
        retryResponse.completeError(http.ClientException('still offline'));
      }
      await tester.pumpAndSettle();
      expect(OfflineMode.active, isTrue);
      expect(find.text('local app'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    }, skip: kIsWeb);
  }

  testWidgets('offline polls are sparse and only resume sync after recovery', (
    tester,
  ) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      if (requests == 1) throw http.ClientException('offline');
      if (requests == 2) {
        return http.Response(
          '{"maintenance":{"enabled":true,"ends_at":0}}',
          503,
        );
      }
      return http.Response('{"maintenance":{"enabled":false}}', 200);
    });
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();
    await _confirmOffline(tester);
    await tester.pump(const Duration(seconds: 59));
    expect(requests, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(OfflineMode.active, isTrue);
    expect(find.text('local app'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(requests, 3);
    expect(OfflineMode.active, isFalse);
    expect(find.text('local app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, skip: kIsWeb);

  testWidgets('server recovery safely removes an open warning', (tester) async {
    var requests = 0;
    final client = MockClient((_) async {
      if (++requests == 1) throw http.ClientException('offline');
      return http.Response('{"maintenance":{"enabled":false}}', 200);
    });
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_continue));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(_warning), findsNothing);
    expect(find.text('local app'), findsOneWidget);
    expect(OfflineMode.active, isFalse);
    await tester.pumpWidget(const SizedBox());
  }, skip: kIsWeb);

  testWidgets('warning also works when the gate is inside the app Navigator', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerStatusGate(
          client: _offlineClient(),
          child: const Text('local app'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _confirmOffline(tester);
    expect(find.text('local app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, skip: kIsWeb);

  testWidgets(
    'compact landscape keeps Continue and warning actions reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(568, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(_offlineClient()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(_continue));
      await _confirmOffline(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('local app'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip: kIsWeb,
  );

  testWidgets('maintenance cannot be bypassed as an outage', (tester) async {
    await tester.pumpWidget(
      _app(
        MockClient(
          (_) async => http.Response(
            '{"maintenance":{"enabled":true,"ends_at":0}}',
            503,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('حالت تعمیرات و بروزرسانی'), findsOneWidget);
    expect(find.text(_continue), findsNothing);
    expect(OfflineMode.active, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('web has no offline Continue action', (tester) async {
    await tester.pumpWidget(_app(_offlineClient()));
    await tester.pumpAndSettle();
    expect(find.text('سرور در دسترس نیست'), findsOneWidget);
    expect(find.text(_continue), findsNothing);
    expect(OfflineMode.active, isFalse);
    await tester.pumpWidget(const SizedBox());
  }, skip: !kIsWeb);
}
