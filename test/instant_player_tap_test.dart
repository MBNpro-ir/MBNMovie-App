import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/instant_player_tap.dart';

void main() {
  testWidgets(
    'player touch activates once immediately without toggling its backdrop',
    (tester) async {
      var actions = 0, backdrop = 0, seeks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            onTap: () => backdrop++,
            onDoubleTap: () => seeks++,
            child: Center(
              child: InstantPlayerTap(
                key: const Key('action'),
                activateOnPress: false,
                onTap: () => actions++,
                child: const Icon(Icons.settings),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('action')));
      expect(actions, 1); // No double-tap timeout before opening the panel.
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const Key('action')));
      expect(actions, 2);
      await tester.pump(const Duration(milliseconds: 500));
      expect(actions, 2);
      expect(backdrop, 0);
      expect(seeks, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('action'))),
      );
      await gesture.moveBy(const Offset(80, 0));
      await gesture.up();
      expect(actions, 2); // A cancelled touch must not open another panel.
      await tester.pumpAndSettle();
    },
  );
}
