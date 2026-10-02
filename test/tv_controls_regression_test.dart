import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/services/accessibility_service.dart';
import 'package:mbnmovie/widgets/tv_navigation.dart';

void main() {
  setUp(() => isAndroidTv = true);
  tearDown(() => isAndroidTv = false);
  test('TV default scale is 80 and explicit preference is preserved', () async {
    SharedPreferences.setMockInitialValues({});
    await AccessibilityService.instance.reloadFromStore();
    expect(AccessibilityService.instance.uiScale, .8);
    SharedPreferences.setMockInitialValues({'access_ui_scale': .95});
    await AccessibilityService.instance.reloadFromStore();
    expect(AccessibilityService.instance.uiScale, .95);
  });
  testWidgets(
    'TV fills viewport and down leaves slider without changing volume',
    (tester) async {
      final sliderFocus = FocusNode(), nextFocus = FocusNode();
      addTearDown(sliderFocus.dispose);
      addTearDown(nextFocus.dispose);
      var volume = .5;
      await tester.pumpWidget(
        MaterialApp(
          home: TvNavigation(
            child: Scaffold(
              key: const Key('full-tv-frame'),
              body: Column(
                children: [
                  Slider(
                    value: volume,
                    focusNode: sliderFocus,
                    onChanged: (v) => volume = v,
                  ),
                  FilledButton(
                    focusNode: nextFocus,
                    onPressed: () {},
                    child: const Text('Next setting'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('full-tv-frame'))),
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
      );
      sliderFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(volume, .5);
      expect(nextFocus.hasFocus, isTrue);
    },
  );
}
