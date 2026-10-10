import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/player_speed_sheet.dart';
import 'package:mbnmovie/core/player_preferences.dart';
import 'package:mbnmovie/core/platform_ui.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'phone speed sheet keeps apply visible at $size with large text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        (SubtitlePreferences, double)? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(
              splashFactory: InkRipple.splashFactory,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    result =
                        await showModalBottomSheet<
                          (SubtitlePreferences, double)
                        >(
                          context: context,
                          isScrollControlled: true,
                          constraints: BoxConstraints(
                            maxWidth: playerSpeedSheetWidth(context),
                          ),
                          builder: (_) => PlayerSpeedSheet(
                            initial: SubtitlePreferences.withPlatformDefaults(),
                            initialRate: 1,
                          ),
                        );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomRight(find.text('اعمال سرعت')).dy,
          lessThan(size.height),
        );
        expect(find.text('سرعت زمان‌بندی زیرنویس'), findsNothing);
        await tester.tap(find.text('1.5×'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('زمان‌بندی زیرنویس'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomRight(find.text('اعمال سرعت')).dy,
          lessThan(size.height),
        );
        await tester.tap(find.text('اعمال سرعت'));
        await tester.pumpAndSettle();
        expect(result?.$2, 1.5);
      },
    );
  }
  testWidgets('TV keeps expanded timing controls and bounded sheet width', (
    tester,
  ) async {
    isAndroidTv = true;
    addTearDown(() => isAndroidTv = false);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: SizedBox(
                width: playerSpeedSheetWidth(context),
                child: PlayerSpeedSheet(
                  initial: SubtitlePreferences.withPlatformDefaults(),
                  initialRate: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('سرعت زمان‌بندی زیرنویس'), findsOneWidget);
    expect(tester.getSize(find.byType(PlayerSpeedSheet)).width, 760);
    expect(tester.takeException(), isNull);
  });
}
