import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/services/preference_batch.dart';

class _Paths extends PathProviderWindows {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(ready(), true);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    '1440p playback isolates large, delayed and unavailable sync',
    (tester) async {
      expect(Platform.isWindows, true);
      const source = String.fromEnvironment('MBN_QA_MEDIA');
      expect(File(source).existsSync(), true);
      final temp = await Directory.systemTemp.createTemp('mbn-sync-player-');
      SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
        ..pathProvider = _Paths(temp.path);
      final prefs = await SharedPreferences.getInstance();
      await writePreferenceBatch(
        prefs,
        values: {
          'player_gestures_introduced': true,
          'qa_history': 'x' * (2 * 1024 * 1024),
          for (var i = 0; i < 4000; i++) 'watch_pos_history_$i': i * 1000,
        },
      );
      final requested = Completer<void>(), delayed = Completer<void>();
      var requests = 0;
      final requestPaths = <String>[];
      var down = false;
      final auth = MbnAuth(
        client: MockClient((request) async {
          requests++;
          requestPaths.add('${request.method} ${request.url.path}');
          if (down) throw const SocketException('QA central outage');
          if (request.method == 'GET') {
            if (!requested.isCompleted) {
              requested.complete();
              await delayed.future;
            }
            return http.Response(
              jsonEncode({
                'progress': {
                  'updated_at': 1000,
                  'payload': {
                    for (var i = 0; i < 10000; i++) 'watch_pos_remote_$i': i,
                  },
                },
              }),
              200,
            );
          }
          final data = jsonDecode(request.body)['data'] as Map;
          return http.Response(
            jsonEncode({
              for (final e in data.entries)
                e.key: {'updated_at': 2000, 'payload': e.value},
            }),
            200,
          );
        }),
      )..token = 'isolated-qa';
      MbnSync.instance.configure(auth: auth);
      final pendingPull = MbnSync.instance.syncAll();
      await requested.future;
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      final episodes = [
        for (var i = 1; i <= 300; i++)
          MovieEpisode(id: '$i', name: 'قسمت $i', fileUrl: source),
      ];
      final content = MovieContent(
        id: 'qa',
        title: 'Playback QA',
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.series,
        colors: const [],
        genres: const [],
        seasons: [
          MovieSeason(id: 's1', name: 'فصل 1 1440p', episodes: episodes),
        ],
      );
      final frames = <FrameTiming>[];
      void timings(List<FrameTiming> values) => frames.addAll(values);
      Timer? heartbeat;
      StreamSubscription<String>? errorsSubscription;
      final errors = <String>[];
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: MovieTheme.dark,
            home: PlayerScreen(content: content, episode: episodes.first),
          ),
        );
        final prepareDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (find.byType(Video).evaluate().isEmpty &&
            DateTime.now().isBefore(prepareDeadline)) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(find.byType(Video), findsOneWidget);
        await tester.pump();
        final player = tester
            .widget<Video>(find.byType(Video))
            .controller
            .player;
        errorsSubscription = player.stream.error.listen(errors.add);
        await until(
          tester,
          () => player.state.position > const Duration(seconds: 2),
        );
        final native = player.platform as NativePlayer;
        expect(await native.getProperty('width'), '2560');
        expect(await native.getProperty('height'), '1440');
        final startDrops = await native.getProperty('frame-drop-count');
        final startDecoderDrops = await native.getProperty(
          'decoder-frame-drop-count',
        );
        binding.addTimingsCallback(timings);
        final clock = Stopwatch()..start();
        var last = 0, maxGap = 0;
        heartbeat = Timer.periodic(const Duration(milliseconds: 8), (_) {
          final now = clock.elapsedMicroseconds;
          if (last != 0 && now - last > maxGap) maxGap = now - last;
          last = now;
        });
        delayed.complete();
        await pendingPull;
        expect(prefs.getInt('watch_pos_remote_1'), isNull);
        final requestsAtStart = requests;
        for (var i = 0; i < 30; i++) {
          await MbnSync.instance.syncAll();
          await MbnSync.instance.pushProgressThrottled();
        }
        expect(requests, requestsAtStart, reason: requestPaths.toString());
        // Open the actual in-player 300-episode sheet while video keeps playing.
        var episodeButton = find
            .byIcon(Icons.video_library_rounded)
            .hitTestable();
        if (episodeButton.evaluate().isEmpty) {
          await tester.tapAt(const Offset(200, 200));
          await tester.pump();
        }
        await until(tester, () => episodeButton.evaluate().isNotEmpty);
        final beforeSheet = player.state.position;
        final uiClock = Stopwatch()..start();
        await tester.tap(episodeButton.first);
        await until(
          tester,
          () =>
              find.text('فصل 1').evaluate().isNotEmpty ||
              find.byType(BottomSheet).evaluate().isNotEmpty ||
              find.byType(Dialog).evaluate().isNotEmpty,
        );
        final sheetMs = uiClock.elapsedMilliseconds;
        await Future<void>.delayed(const Duration(seconds: 3));
        await tester.pump();
        expect(
          player.state.position,
          greaterThan(beforeSheet + const Duration(seconds: 2)),
        );
        Navigator.of(
          tester.element(episodeButton.first),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        for (final unavailable in [false, true]) {
          down = unavailable;
          for (var i = 0; i < 8; i++) {
            await MbnSync.instance.syncAll();
            await Future<void>.delayed(const Duration(seconds: 1));
            await tester.pump();
          }
        }
        final uninterruptedOutputDrops = await native.getProperty(
          'frame-drop-count',
        );
        final uninterruptedDecoderDrops = await native.getProperty(
          'decoder-frame-drop-count',
        );
        // Pausing captures a durable checkpoint, and may try one urgent upload.
        await player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final paused = player.state.position;
        await tester.pump();
        await player.play();
        await until(
          tester,
          () => player.state.position > paused + const Duration(seconds: 1),
        );
        heartbeat.cancel();
        final result = {
          'resolution': '2560x1440',
          'historyKeys': 4000,
          'delayedRemoteKeys': 10000,
          'requestPaths': requestPaths,
          'episodeCount': 300,
          'episodeSheetMs': sheetMs,
          'requests': requests,
          'maxEventLoopGapMs': maxGap / 1000,
          'frames': frames.length,
          'slowBuildFrames': frames
              .where((f) => f.buildDuration.inMicroseconds > 16667)
              .length,
          'slowRasterFrames': frames
              .where((f) => f.rasterDuration.inMicroseconds > 16667)
              .length,
          'decoderDropsBefore': startDecoderDrops,
          'decoderDropsAfter': uninterruptedDecoderDrops,
          'outputDropsBefore': startDrops,
          'outputDropsAfter': uninterruptedOutputDrops,
          'outputDropsAfterPauseResume': await native.getProperty(
            'frame-drop-count',
          ),
          'hwdec': await native.getProperty('hwdec-current'),
          'positionSeconds': player.state.position.inSeconds,
        };
        debugPrint('MBN_SYNC_PLAYBACK ${jsonEncode(result)}');
        expect(errors, isEmpty);
        expect(result['decoderDropsAfter'], startDecoderDrops);
        expect(result['outputDropsAfter'], startDrops);
        expect(sheetMs, lessThan(1000));
        expect(maxGap / 1000, lessThan(100));
        expect(tester.takeException(), isNull);
      } finally {
        if (!delayed.isCompleted) delayed.complete();
        heartbeat?.cancel();
        binding.removeTimingsCallback(timings);
        await errorsSubscription?.cancel();
        MbnSync.instance.clear();
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(seconds: 1));
        await windowManager.setFullScreen(false);
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
