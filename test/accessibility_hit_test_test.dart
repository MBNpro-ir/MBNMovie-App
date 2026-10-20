import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mbnmovie/app.dart';
import 'package:mbnmovie/services/accessibility_service.dart';
import 'package:mbnmovie/services/device_performance.dart';

void main() {
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
          data: const MediaQueryData(size: Size(200, 200)),
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

    await tester.tapAt(const Offset(180, 180));
    expect(taps, 1);
  });
}
