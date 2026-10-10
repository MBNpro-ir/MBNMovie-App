import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/widgets/responsive_web_layout.dart';
import 'package:mbnmovie/widgets/player_speed_sheet.dart';
import 'package:mbnmovie/widgets/subtitle_appearance_panel.dart';
import 'package:mbnmovie/core/player_preferences.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('phone panels match speed width and top subtitles fit $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            splashFactory: InkRipple.splashFactory,
          ),
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
        ),
      );
      final expectedWidth = playerSpeedSheetWidth(context);
      for (final content in [
        PlayerSpeedSheet(initial: SubtitlePreferences(), initialRate: 1),
        const SizedBox(height: 280, child: Text('Audio and subtitles')),
        const SizedBox(height: 200, child: Text('Quality and episodes')),
      ]) {
        final closed = showResponsivePlayerPanel<void>(
          compactLayout: true,
          context: context,
          builder: (_) => content,
        );
        await tester.pumpAndSettle();
        final bounds = tester.getRect(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(bounds.width, closeTo(expectedWidth, .01));
        expect(
          bounds.height,
          lessThanOrEqualTo(math.min(520, (size.height - 36) * .9) + .01),
        );
        expect(bounds.left, greaterThanOrEqualTo(12));
        expect(bounds.right, lessThanOrEqualTo(size.width - 12));
        expect(tester.takeException(), isNull);
        Navigator.pop(tester.element(find.byType(BottomSheet)));
        await tester.pumpAndSettle();
        await closed;
      }
      SubtitlePreferences? liveValue;
      final closed = showTopPlayerPanel<void>(
        context: context,
        compactLayout: true,
        fullWidth: true,
        backgroundColor: Colors.black,
        builder: (_) => SubtitleAppearancePanel(
          initial: SubtitlePreferences(),
          compactLayout: true,
          twoColumnLayout: true,
          onChanged: (value) => liveValue = value,
        ),
      );
      await tester.pumpAndSettle();
      final top = tester.getRect(find.byKey(const Key('top-player-panel')));
      expect(top.top, closeTo(0, .01));
      expect(top.width, closeTo(size.width, .01));
      expect(
        find.byKey(const Key('subtitle-appearance-columns')),
        findsOneWidget,
      );
      final columns = tester.widget<Row>(
        find.byKey(const Key('subtitle-appearance-columns')),
      );
      expect(columns.children, hasLength(2));
      expect(
        top.height,
        lessThanOrEqualTo(math.min(340, size.height * .62) + .01),
      );
      expect(find.byTooltip('بستن پنل'), findsOneWidget);
      await tester.tap(find.byTooltip('پیش‌فرض'));
      await tester.pump();
      expect(liveValue, isNotNull);
      expect(liveValue!.size, SubtitlePreferences().size);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('بستن پنل'));
      await tester.pumpAndSettle();
      await closed;
    });
  }
  testWidgets(
    'subtitle appearance shrinks to content instead of reserving 560 pixels',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            splashFactory: InkRipple.splashFactory,
          ),
          home: Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 840,
                  maxHeight: 560,
                ),
                child: SubtitleAppearancePanel(
                  initial: SubtitlePreferences(),
                  compactLayout: true,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SubtitleAppearancePanel)).height,
        lessThan(530),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
