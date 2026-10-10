import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/player_tracks_panel.dart';
import 'package:mbnmovie/widgets/player_track_card.dart';
import 'package:mbnmovie/widgets/responsive_web_layout.dart';
import 'package:mbnmovie/widgets/audio_sync_control.dart';
import 'package:mbnmovie/widgets/player_speed_sheet.dart';
import 'package:mbnmovie/core/player_preferences.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(568, 320),
    const Size(1366, 768),
    const Size(1920, 1080),
  ]) {
    testWidgets('track selection and imports remain reachable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      Widget tracks(String language, IconData icon) => ListView.builder(
        itemCount: 24,
        itemBuilder: (_, index) => PlayerTrackCard(
          title: '$language $index — عنوان طولانی برای انتخاب زبان فیلم',
          detail: 'AAC · stereo',
          icon: icon,
          selected: index == 0,
          onTap: () => selected = index,
        ),
      );
      Widget actions(String label) => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text('فایل $label'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.link, size: 18),
              label: Text('لینک $label'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            splashFactory: InkRipple.splashFactory,
          ),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showResponsivePlayerPanel<void>(
                    context: context,
                    compactLayout: size.shortestSide < 600,
                    desktopDialog: true,
                    containsCloseButton: true,
                    showDragHandle: false,
                    constraints: const BoxConstraints(maxWidth: 780),
                    builder: (_) => PlayerTracksPanel(
                      audio: tracks('صدا', Icons.graphic_eq),
                      subtitles: tracks('زیرنویس', Icons.subtitles),
                      audioActions: actions(''),
                      subtitleActions: actions(''),
                      trackCount: 24,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final wide = size.shortestSide >= 600;
      expect(
        find.byKey(const Key('track-columns')),
        wide ? findsOneWidget : findsNothing,
      );
      expect(find.byTooltip('بستن پنل'), findsOneWidget);
      final footer = find.byType(OutlinedButton).hitTestable().first;
      final rect = tester.getRect(footer);
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.left, greaterThanOrEqualTo(0));
      await tester.tap(find.byType(PlayerTrackCard).hitTestable().first);
      expect(selected, 0);
      if (!wide) {
        await tester.tap(find.text('زیرنویس'));
        await tester.pumpAndSettle();
      }
      final list = find.byType(ListView).hitTestable().last;
      await tester.drag(list, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(OutlinedButton).hitTestable(),
        wide ? findsNWidgets(4) : findsNWidgets(2),
      );
      await tester.tap(find.byTooltip('بستن پنل'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerTracksPanel), findsNothing);
    });
  }
  testWidgets('remote keyboard can focus and select a track', (tester) async {
    int selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          splashFactory: InkRipple.splashFactory,
        ),
        home: Scaffold(
          body: PlayerTrackCard(
            title: 'فارسی',
            icon: Icons.subtitles,
            selected: false,
            onTap: () => selections++,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selections, 1);
  });
  testWidgets('audio reset applies to player and updates its displayed value', (
    tester,
  ) async {
    double? applied;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          splashFactory: InkRipple.splashFactory,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: PlayerSpeedSheet(
                initial: SubtitlePreferences(),
                initialRate: 1.5,
                initialAudioDelay: .3,
                onAudioDelayChanged: (v) async => applied = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('افزایش هماهنگی'));
    await tester.pumpAndSettle();
    expect(applied, closeTo(.35, .001));
    expect(find.text('350 ms'), findsOneWidget);
    await tester.tap(find.text('بازنشانی'));
    await tester.pumpAndSettle();
    expect(applied, 0);
    expect(find.text('0 ms'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(AudioSyncControl), findsOneWidget);
  });
}
