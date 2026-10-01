import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/adaptive_player_header.dart';

void main() {
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
