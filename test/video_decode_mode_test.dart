import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/player_preferences.dart';
import 'package:mbnmovie/core/video_decode_mode.dart';
import 'package:mbnmovie/widgets/decoder_mode_builder.dart';
import 'package:mbnmovie/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('missing and malformed settings keep hardware default', () async {
    expect(
      await PlaybackPreferenceStore.decoderMode(),
      VideoDecodeMode.hardware,
    );
    final prefs = await SharedPreferences.getInstance();
    for (final value in ['invalid', '', 'Software']) {
      await prefs.setString(VideoDecodeMode.preferenceKey, value);
      expect(
        await PlaybackPreferenceStore.decoderMode(),
        VideoDecodeMode.hardware,
      );
    }
    await prefs.setBool(VideoDecodeMode.preferenceKey, true);
    expect(
      await PlaybackPreferenceStore.decoderMode(),
      VideoDecodeMode.hardware,
    );
    await PlaybackPreferenceStore.setDecoderMode(VideoDecodeMode.software);
    expect(
      await PlaybackPreferenceStore.decoderMode(),
      VideoDecodeMode.software,
    );
  });

  testWidgets('decoder is snapshotted per player and Back works', (
    tester,
  ) async {
    await PlaybackPreferenceStore.setDecoderMode(VideoDecodeMode.software);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DecoderModeBuilder(
                    builder: (mode) => Scaffold(body: Text(mode.name)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('software'), findsOneWidget);
    await PlaybackPreferenceStore.setDecoderMode(VideoDecodeMode.hardware);
    await tester.pumpAndSettle();
    expect(find.text('software'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('hardware'), findsOneWidget);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('decoder setting can change offline at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('player-decoder-mode'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('نرم‌افزاری').last);
      await tester.pumpAndSettle();
      expect(
        await PlaybackPreferenceStore.decoderMode(),
        VideoDecodeMode.software,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
