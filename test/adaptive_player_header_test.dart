import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/adaptive_player_header.dart';

void main() {
  testWidgets('fullscreen and fit stay leftmost; rightmost settings overflow', (
    tester,
  ) async {
    const labels = [
      'صدا و زیرنویس',
      'تنظیم زیرنویس',
      'تنظیم سرعت',
      'اندازهٔ تصویر (V)',
      'تمام‌صفحه (F)',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: AdaptivePlayerHeader(
                back: const Icon(Icons.arrow_back),
                title: const Text('Title'),
                actions: [
                  for (final label in labels)
                    PlayerHeaderAction(
                      icon: Icons.settings,
                      label: label,
                      priority: playerHeaderActionPriority(label),
                      onTap: () {},
                      button: TextButton(onPressed: () {}, child: Text(label)),
                    ),
                ],
                onMenuOpened: () {},
                onMenuClosed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('تمام‌صفحه (F)'), findsOneWidget);
    expect(find.text('اندازهٔ تصویر (V)'), findsOneWidget);
    expect(
      tester.getCenter(find.text('تمام‌صفحه (F)')).dx,
      lessThan(tester.getCenter(find.text('اندازهٔ تصویر (V)')).dx),
    );
    expect(find.text('صدا و زیرنویس'), findsNothing);
    await tester.tap(find.byKey(const Key('player-header-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('صدا و زیرنویس'), findsOneWidget);
    expect(find.text('تنظیم زیرنویس'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [280.0, 320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('one row with only overflowing actions at $width', (
      tester,
    ) async {
      var selected = -1;
      var opened = false;
      final actions = List.generate(
        7,
        (i) => PlayerHeaderAction(
          icon: Icons.settings,
          label: 'Action $i',
          onTap: () => selected = i,
          button: TextButton(onPressed: () => selected = i, child: Text('$i')),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: AdaptivePlayerHeader(
                    back: const Icon(Icons.arrow_back),
                    title: const Text('Episode', maxLines: 1),
                    actions: actions,
                    onMenuOpened: () => opened = true,
                    onMenuClosed: () => opened = false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final overflow = find.byKey(const Key('player-header-overflow'));
      if (width < 768) {
        expect(overflow, findsOneWidget);
        final visibleCount = find.byType(TextButton).evaluate().length;
        expect(visibleCount, greaterThan(0));
        expect(visibleCount, lessThan(actions.length));
        for (var i = 1; i < visibleCount; i++) {
          expect(
            tester.getCenter(find.text('${i - 1}')).dx,
            lessThan(tester.getCenter(find.text('$i')).dx),
          );
        }
        expect(
          tester.getCenter(overflow).dx,
          greaterThan(tester.getCenter(find.text('${visibleCount - 1}')).dx),
        );
        // Back and all visible actions are in the same single row.
        final top = tester.getTopLeft(find.byIcon(Icons.arrow_back)).dy;
        for (final button in find.byType(TextButton).evaluate()) {
          expect(
            tester.getTopLeft(find.byWidget(button.widget)).dy,
            closeTo(top, 30),
          );
        }
        await tester.tap(overflow);
        await tester.pumpAndSettle();
        expect(opened, isTrue);
        for (var i = 0; i < actions.length; i++) {
          expect(
            find.text('Action $i'),
            i < visibleCount ? findsNothing : findsOneWidget,
          );
        }
        await tester.tap(find.text('Action 6'));
        await tester.pumpAndSettle();
        expect(selected, 6);
        expect(opened, isFalse);
      } else {
        expect(overflow, findsNothing);
        expect(find.byType(TextButton), findsNWidgets(7));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
