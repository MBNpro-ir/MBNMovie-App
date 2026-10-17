import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/widgets/ambient_background.dart';

void main() {
  tearDown(() {
    DevicePerformance.androidSdk = 0;
    DevicePerformance.emulator = false;
    DevicePerformance.lowRam = false;
    DevicePerformance.television = false;
    DevicePerformance.appleMobileWeb = false;
  });

  test('Android 6 through 12L use light UI, Android 13 keeps full UI', () {
    for (final sdk in [23, 24, 25, 26, 27, 28, 29, 30, 31, 32]) {
      expect(
        DevicePerformance.useLightweightUiFor(
          sdk: sdk,
          lowRam: false,
          television: false,
        ),
        isTrue,
      );
    }
    for (final sdk in [0, 33, 34, 35, 37]) {
      expect(
        DevicePerformance.useLightweightUiFor(
          sdk: sdk,
          lowRam: false,
          television: false,
        ),
        isFalse,
      );
    }
    expect(
      DevicePerformance.useLightweightUiFor(
        sdk: 35,
        lowRam: true,
        television: false,
      ),
      isTrue,
    );
    expect(
      DevicePerformance.useLightweightUiFor(
        sdk: 35,
        lowRam: false,
        television: true,
      ),
      isTrue,
    );
  });

  testWidgets('iPhone uses a smaller cache policy and no ambient ticker', (
    tester,
  ) async {
    DevicePerformance.appleMobileWeb = true;
    expect(
      DevicePerformance.useLightweightUiFor(
        sdk: 0,
        lowRam: false,
        television: false,
        appleMobileWeb: true,
      ),
      isTrue,
    );
    expect(DevicePerformance.artworkWidth(true), 240);
    expect(DevicePerformance.artworkWidth(false), 640);
    expect(DevicePerformance.routeDuration.inMilliseconds, 120);
    await tester.pumpWidget(
      const MaterialApp(
        home: AmbientBackground(animate: true, child: Text('iPhone')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 15));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('light background schedules no continuous frames', (
    tester,
  ) async {
    DevicePerformance.androidSdk = 23;
    await tester.pumpWidget(
      const MaterialApp(
        home: AmbientBackground(animate: true, child: Text('Content')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Content'), findsOneWidget);
    expect(DevicePerformance.artworkWidth(true), 320);
    expect(DevicePerformance.routeDuration.inMilliseconds, 180);
    await tester.pump(const Duration(seconds: 15));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
