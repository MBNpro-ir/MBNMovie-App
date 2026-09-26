import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/widgets/pressable.dart';
import 'package:mbnmovie/widgets/player_keyboard.dart';
import 'package:mbnmovie/widgets/tv_navigation.dart';
import 'package:mbnmovie/screens/episode_picker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'episode_picker_test.dart' as fixtures;

void main() {
  setUp(() => isAndroidTv = true);
  tearDown(() => isAndroidTv = false);

  testWidgets('remote can focus and activate a poster without touch', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvNavigation(
            child: Center(
              child: Pressable(
                onTap: () => opened++,
                child: const SizedBox(
                  width: 150,
                  height: 220,
                  child: Text('Poster'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV hidden controls seek and OK toggles; visible controls navigate',
    (tester) async {
      final commands = <PlayerCommand>[];
      var navigations = 0;
      var activated = 0;
      final buttonFocus = FocusNode();
      addTearDown(buttonFocus.dispose);
      Widget page(bool visible) => MaterialApp(
        home: Scaffold(
          body: TvNavigation(
            child: PlayerKeyboard(
              isTelevision: true,
              controlsVisible: visible,
              onRemoteNavigation: () => navigations++,
              onCommand: commands.add,
              onSeekFraction: (_) {},
              onFocus: () {},
              child: TextButton(
                focusNode: buttonFocus,
                onPressed: () => activated++,
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(false));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(commands, [PlayerCommand.forward, PlayerCommand.toggle]);
      expect(navigations, 1);
      await tester.pumpWidget(page(true));
      buttonFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(commands.length, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(activated, 1);
    },
  );

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('TV episode picker fits $size with readable text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: MovieTheme.dark,
          home: TvNavigation(
            child: EpisodePickerScreen(
              content: fixtures.content,
              onPlay: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('قسمت اول'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
