import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/models/movie_content.dart';

class _TestPaths extends PathProviderWindows {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

// Local H.264 1080p30 clip, >=60s. Never writes into the user's preferences.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'native Windows playback with periodic progress and disk writes',
    (tester) async {
      expect(Platform.isWindows, true);
      const source = String.fromEnvironment('MBN_QA_MEDIA');
      expect(File(source).existsSync(), true);
      final temp = await Directory.systemTemp.createTemp('mbn-player-perf-');
      SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
        ..pathProvider = _TestPaths(temp.path);
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('player_gestures_introduced', true);
      final item = MovieContent(
        id: 'qa',
        title: 'Playback performance QA',
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.movie,
        colors: const [],
        genres: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: MovieTheme.dark,
          home: PlayerScreen(
            content: item,
            episode: const MovieEpisode(id: 'one', name: '1', fileUrl: source),
          ),
        ),
      );
      await tester.pump();
      final player = tester.widget<Video>(find.byType(Video)).controller.player;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (player.state.position < const Duration(seconds: 2) &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(player.state.position, greaterThan(const Duration(seconds: 1)));
      final native = player.platform as NativePlayer;
      final dropsAtStart = await native.getProperty('frame-drop-count');
      final errors = <String>[];
      final subscription = player.stream.error.listen(errors.add);
      final results = <Map<String, Object?>>[];
      try {
        // The first phase has no synthetic writes: distinguish ordinary
        // Windows timer scheduling from a playback/persistence stall.
        for (final bytes in [0, 32768, 2 * 1024 * 1024]) {
          await prefs.setString('qa_history', 'x' * bytes);
          final frames = <FrameTiming>[];
          void timings(List<FrameTiming> values) => frames.addAll(values);
          binding.addTimingsCallback(timings);
          final clock = Stopwatch()..start();
          var last = 0, maxGap = 0;
          final heartbeat = Timer.periodic(const Duration(milliseconds: 8), (
            _,
          ) {
            final now = clock.elapsedMicroseconds;
            if (now - last > maxGap) maxGap = now - last;
            last = now;
          });
          final bursts = <double>[];
          for (var round = 0; round < 4; round++) {
            await Future<void>.delayed(const Duration(seconds: 2));
            final watch = Stopwatch()..start();
            if (bytes > 0) {
              await Future.wait([
                for (var i = 0; i < 6; i++)
                  prefs.setInt('qa_progress_$i', round),
              ]);
            }
            bursts.add(watch.elapsedMicroseconds / 1000);
            await tester.pump();
          }
          heartbeat.cancel();
          binding.removeTimingsCallback(timings);
          final runtimeProperties = <String, String?>{};
          for (final name in const [
            'cache-on-disk',
            'framedrop',
            'interpolation',
            'vd-lavc-threads',
          ]) {
            runtimeProperties[name] = await native.getProperty(name);
          }
          results.add({
            'syntheticWrites': bytes > 0,
            'preferenceBytes': bytes,
            'maxEventLoopGapMs': maxGap / 1000,
            'writeBurstMs': bursts,
            'frames': frames.length,
            'slowBuildFrames': frames
                .where((f) => f.buildDuration.inMicroseconds > 16667)
                .length,
            'slowRasterFrames': frames
                .where((f) => f.rasterDuration.inMicroseconds > 16667)
                .length,
            'decoderDrops': await native.getProperty(
              'decoder-frame-drop-count',
            ),
            'outputDrops': await native.getProperty('frame-drop-count'),
            'hwdec': await native.getProperty('hwdec-current'),
            'runtimeProperties': runtimeProperties,
            'positionSeconds': player.state.position.inSeconds,
          });
          final data =
              jsonDecode(
                    await File(
                      '${temp.path}/shared_preferences.json',
                    ).readAsString(),
                  )
                  as Map;
          if (bytes > 0) {
            for (var i = 0; i < 6; i++) {
              expect(data['flutter.qa_progress_$i'], 3);
            }
          }
        }
        debugPrint('MBN_WINDOWS_PERFORMANCE ${jsonEncode(results)}');
        expect(await native.getProperty('decoder-frame-drop-count'), '0');
        expect(await native.getProperty('cache-on-disk'), 'no');
        expect(await native.getProperty('framedrop'), 'vo');
        expect(await native.getProperty('interpolation'), 'no');
        // mpv exposes the `auto` value as numeric zero through libmpv.
        expect(await native.getProperty('vd-lavc-threads'), '0');
        expect(
          await native.getProperty('frame-drop-count'),
          dropsAtStart,
          reason: 'No output frames may be dropped during measured playback',
        );
        expect(errors, isEmpty);
        expect(player.state.position, greaterThan(const Duration(seconds: 15)));
        expect(tester.takeException(), isNull);
      } finally {
        await subscription.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(seconds: 1));
        await windowManager.setFullScreen(false);
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
