import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mbnmovie/core/native_playback_policy.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/services/device_performance.dart';

// Local synthetic H.264/AAC/ASS fixture; no user credentials or account data.
// Emulator runs validate software fallback, native subtitles and player
// lifecycle. Direct MediaCodec, throughput and battery use need a physical
// device; REQUIRE_MEDIACODEC makes that additional hardware check mandatory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const sourceUrl = String.fromEnvironment(
    'MBN_QA_MEDIA',
    defaultValue: 'http://10.0.2.2:8766/mbn-legacy-h264.mkv',
  );
  late String source;
  late String fallbackSource;
  Future<String> localFixture(String value, String name) async {
    final uri = Uri.parse(value);
    if (uri.scheme != 'http' && uri.scheme != 'https') return value;
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, HttpStatus.ok);
      final file = File('${(await getTemporaryDirectory()).path}/$name');
      await response.pipe(file.openWrite());
      return file.uri.toString();
    } finally {
      client.close(force: true);
    }
  }

  setUpAll(() async {
    await DevicePerformance.initialize();
    // Decode from app-private files: transport and storage permissions must not
    // distort a comparison of native decoder paths.
    source = await localFixture(sourceUrl, 'mbn-legacy-h264.mkv');
    fallbackSource = await localFixture(
      const String.fromEnvironment(
        'MBN_QA_FALLBACK_MEDIA',
        defaultValue: 'http://10.0.2.2:8766/mbn-legacy-fallback.mkv',
      ),
      'mbn-legacy-fallback.mkv',
    );
  });
  Future<void> advance(
    WidgetTester tester,
    Player player,
    Duration target,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (player.state.position < target &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(player.state.position, greaterThanOrEqualTo(target));
  }

  testWidgets(
    'decoder policy preserves playback, ASS and seek with fallback',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      MediaKit.ensureInitialized();
      final snapshots = <Map<String, Object?>>[];
      for (final hwdec in ['auto-safe', 'mediacodec,mediacodec-copy']) {
        final player = Player(
          configuration: const PlayerConfiguration(
            libass: true,
            libassAndroidFont: 'assets/fonts/Vazirmatn-Regular.ttf',
            libassAndroidFontName: 'Vazirmatn',
          ),
        );
        // Explicit test override exercises the Android codec API even on an
        // emulator; production preserves media_kit's software emulator default.
        final controller = VideoController(
          player,
          configuration: VideoControllerConfiguration(hwdec: hwdec),
        );
        final errors = <String>[];
        final sub = player.stream.error.listen(errors.add);
        final logs = player.stream.log.listen((log) {
          if (log.level == 'error') debugPrint('MBN_DECODE_LOG $hwdec $log');
        });
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Video(
                  controller: controller,
                  controls: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          await player.open(Media(source));
          await advance(tester, player, const Duration(seconds: 3));
          final native = player.platform as NativePlayer;
          expect(player.state.tracks.subtitle, isNotEmpty);
          expect(await native.getProperty('sub-text'), contains('Android'));
          final decoder = await native.getProperty('hwdec-current');
          if (hwdec.startsWith('mediacodec') &&
              const bool.fromEnvironment('MBN_QA_REQUIRE_MEDIACODEC')) {
            expect(decoder, 'mediacodec');
          }
          final before = await native.getProperty('frame-drop-count');
          await advance(tester, player, const Duration(seconds: 9));
          snapshots.add({
            'requested': hwdec,
            'actual': decoder,
            'mpvVersion': await native.getProperty('mpv-version'),
            'output': await native.getProperty('current-vo'),
            'decoderDrops': await native.getProperty(
              'decoder-frame-drop-count',
            ),
            'outputDropsStart': before,
            'outputDropsEnd': await native.getProperty('frame-drop-count'),
            'probeErrors': List<String>.of(errors),
          });
          debugPrint('MBN_ANDROID_DECODE ${jsonEncode(snapshots.last)}');
          await player.pause();
          final paused = player.state.position;
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(
            (player.state.position - paused).inMilliseconds.abs(),
            lessThan(400),
          );
          await player.seek(const Duration(seconds: 15));
          await player.play();
          await advance(tester, player, const Duration(seconds: 17));
          // The emulator cannot provide this native hardware path. Its codec
          // probes can fail before successful software fallback; accept only
          // that exact probe message there, with all playback assertions kept.
          // Physical-device runs remain strict; REQUIRE_MEDIACODEC additionally
          // verifies that the direct path was really selected.
          if (hwdec.startsWith('mediacodec')) {
            if (DevicePerformance.emulator && decoder == 'no') {
              expect(errors, everyElement('Could not open codec.'));
            } else {
              expect(errors, isEmpty);
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await sub.cancel();
          await logs.cancel();
          await player.dispose();
        }
      }
      debugPrint('MBN_ANDROID_DECODE ${jsonEncode(snapshots)}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'unsupported hardware codec still plays with software fallback',
    (tester) async {
      final player = Player();
      final controller = VideoController(
        player,
        configuration: NativePlaybackPolicy.videoConfiguration(
          android: true,
          sdk: 27,
          emulator: false,
        ),
      );
      final errors = player.stream.log.listen((log) {
        if (log.level == 'error') debugPrint('MBN_FALLBACK_LOG $log');
      });
      try {
        await tester.pumpWidget(
          MaterialApp(home: Video(controller: controller)),
        );
        await player.open(Media(fallbackSource));
        await advance(tester, player, const Duration(seconds: 2));
        expect(
          await (player.platform as NativePlayer).getProperty('hwdec-current'),
          'no',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await errors.cancel();
        await player.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'real player uses old-device policy and exits after seek',
    (tester) async {
      await DevicePerformance.initialize();
      final sdk = DevicePerformance.androidSdk;
      final emulator = DevicePerformance.emulator;
      // Run the production PlayerScreen with an explicit physical API 27 profile.
      // Only this test overrides the detected emulator; no production define does.
      DevicePerformance.androidSdk = 27;
      DevicePerformance.emulator = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('player_gestures_introduced', true);
      await prefs.setBool('sub_original_ass', true);
      final item = MovieContent(
        id: 'legacy-decoder-qa',
        title: 'Legacy decoder QA',
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.movie,
        colors: const [],
        genres: const [],
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: MovieTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        content: item,
                        episode: MovieEpisode(
                          id: 'one',
                          name: '1',
                          fileUrl: source,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open player'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open player'));
        final ready = DateTime.now().add(const Duration(seconds: 10));
        while (find.byType(Video).evaluate().isEmpty &&
            DateTime.now().isBefore(ready)) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final player = tester
            .widget<Video>(find.byType(Video))
            .controller
            .player;
        await advance(tester, player, const Duration(seconds: 3));
        final native = player.platform as NativePlayer;
        expect(
          await native.getProperty('hwdec'),
          NativePlaybackPolicy.videoConfiguration(
            android: true,
            sdk: 27,
            emulator: false,
          ).hwdec,
        );
        expect(await native.getProperty('current-vo'), 'gpu');
        expect(await native.getProperty('sub-visibility'), 'yes');
        expect(await native.getProperty('sub-ass-override'), 'no');
        expect(await native.getProperty('sub-text'), contains('Android'));
        await player.seek(const Duration(seconds: 20));
        await player.setRate(1.25);
        await advance(tester, player, const Duration(seconds: 22));
        await player.setRate(1);
        await tester.binding.handlePopRoute();
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (find.byType(PlayerScreen).evaluate().isNotEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(find.byType(PlayerScreen), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        DevicePerformance.androidSdk = sdk;
        DevicePerformance.emulator = emulator;
        await prefs.remove('sub_original_ass');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
