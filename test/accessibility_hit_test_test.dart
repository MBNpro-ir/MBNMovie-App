import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbnmovie/app.dart';
import 'package:mbnmovie/services/accessibility_service.dart';
import 'package:mbnmovie/services/device_performance.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevicePerformance.appleMobileWeb = true;
  });
  tearDown(() => DevicePerformance.appleMobileWeb = false);

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final dpr in [1.0, 3.0]) {
      testWidgets('paint and taps survive live zoom at $size / DPR $dpr', (
        tester,
      ) async {
        tester.view.physicalSize = size * dpr;
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final taps = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) => AccessibilityAppWrapper(child: child!),
            home: Scaffold(
              body: SafeArea(
                child: Stack(
                  children: [
                    for (final (name, alignment) in [
                      ('top', Alignment.topCenter),
                      ('middle', Alignment.center),
                      ('bottom', Alignment.bottomCenter),
                    ])
                      Align(
                        alignment: alignment,
                        child: ElevatedButton(
                          key: ValueKey(name),
                          onPressed: () => taps.add(name),
                          child: Text(name),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (final scale in [.6, .8, 1.0, 1.5, .85, .8]) {
          await AccessibilityService.instance.setUiScale(scale);
          await tester.pumpAndSettle();
          for (final name in ['top', 'middle', 'bottom']) {
            final finder = find.byKey(ValueKey(name));
            final rect = tester.getRect(finder);
            expect(rect.top, greaterThanOrEqualTo(-.01));
            expect(rect.bottom, lessThanOrEqualTo(size.height + .01));
            final before = taps.length;
            await tester.tapAt(rect.center);
            await tester.pump();
            expect(taps.length, before + 1, reason: '$name at scale $scale');
            expect(taps.last, name);
          }
        }
      });
    }
  }

  for (final (size, safe) in [
    (const Size(375, 812), const EdgeInsets.fromLTRB(0, 44, 0, 34)),
    (const Size(812, 375), const EdgeInsets.fromLTRB(44, 0, 44, 21)),
  ]) {
    testWidgets('safe areas stay inside the full viewport at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      final padding = FakeViewPadding(
        left: safe.left * 3,
        top: safe.top * 3,
        right: safe.right * 3,
        bottom: safe.bottom * 3,
      );
      tester.view.viewPadding = padding;
      tester.view.padding = padding;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => AccessibilityAppWrapper(child: child!),
          home: Scaffold(
            key: const Key('full-viewport'),
            body: SafeArea(
              child: SafeArea(
                child: Stack(
                  key: const Key('safe-content'),
                  children: [
                    for (final (name, alignment) in [
                      ('top', Alignment.topCenter),
                      ('bottom', Alignment.bottomCenter),
                    ])
                      Align(
                        alignment: alignment,
                        child: ElevatedButton(
                          key: ValueKey(name),
                          onPressed: () => taps++,
                          child: Text(name),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (final scale in [.6, .8, 1.0, 1.5, .85, .8]) {
        await AccessibilityService.instance.setUiScale(scale);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byKey(const Key('full-viewport')));
        expect(viewport.left, closeTo(0, .01));
        expect(viewport.top, closeTo(0, .01));
        expect(viewport.width, closeTo(size.width, .01));
        expect(viewport.height, closeTo(size.height, .01));
        final content = tester.getRect(find.byKey(const Key('safe-content')));
        expect(content.left, closeTo(safe.left, .01));
        expect(content.top, closeTo(safe.top, .01));
        expect(content.right, closeTo(size.width - safe.right, .01));
        expect(content.bottom, closeTo(size.height - safe.bottom, .01));
        for (final name in ['top', 'bottom']) {
          final rect = tester.getRect(find.byKey(ValueKey(name)));
          expect(content.contains(rect.center), isTrue);
          final before = taps;
          await tester.tapAt(rect.center);
          expect(taps, before + 1);
        }
      }
    });
  }

  testWidgets('bounded viewport overrides stale inherited screen dimensions', (
    tester,
  ) async {
    await AccessibilityService.instance.setUiScale(.8);
    final frame = GlobalKey();
    final button = GlobalKey();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            key: frame,
            width: 350,
            height: 400,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(390, 844)),
              child: AccessibilityAppWrapper(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        key: const Key('viewport'),
                        color: Colors.black,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ElevatedButton(
                        key: button,
                        onPressed: () => taps++,
                        child: const Text('tap'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('viewport'))),
      tester.getRect(find.byKey(frame)),
    );
    await tester.tapAt(tester.getCenter(find.byKey(button)));
    expect(taps, 1);
  });

  testWidgets('scaled web UI keeps the visual button hit target aligned', (
    tester,
  ) async {
    DevicePerformance.appleMobileWeb = true;
    await AccessibilityService.instance.setUiScale(.80);
    var taps = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: AccessibilityAppWrapper(
            child: Stack(
              children: [
                Positioned(
                  left: 200,
                  top: 200,
                  width: 50,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => taps++,
                    child: const Text('tap'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The logical button starts at 200x200 and is painted at 160x160 after
    // the 0.8 scale. A tap on its visible centre must activate it.
    await tester.tapAt(const Offset(180, 180));
    expect(taps, 1);
  });
}
