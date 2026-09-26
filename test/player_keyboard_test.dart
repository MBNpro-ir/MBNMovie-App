import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/player_keyboard.dart';

void main() {
  testWidgets(
    'RTL focused slider cannot reverse or consume ten-second seek keys',
    (tester) async {
      final commands = <PlayerCommand>[];
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var sliderChanges = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PlayerKeyboard(
                onCommand: commands.add,
                onSeekFraction: (_) {},
                onFocus: () {},
                child: Slider(
                  focusNode: focus,
                  value: .5,
                  onChanged: (_) => sliderChanges++,
                ),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(commands, [PlayerCommand.forward, PlayerCommand.back]);
      expect(sliderChanges, 0);
    },
  );
  testWidgets(
    'player keys dispatch commands without intercepting text in dialogs',
    (tester) async {
      final commands = <PlayerCommand>[];
      final positions = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerKeyboard(
              onCommand: commands.add,
              onSeekFraction: positions.add,
              onFocus: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      expect(commands, [
        PlayerCommand.toggle,
        PlayerCommand.forward,
        PlayerCommand.mute,
      ]);
      expect(positions, [.5]);
      final context = tester.element(find.byType(Scaffold));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mk f');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(commands.length, 3);
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pumpAndSettle();
    },
  );
}
