import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/services/playback_activity.dart';
import 'package:mbnmovie/widgets/player_subtitle_text.dart';
import '../test/fixtures/subtitle_bidi_cases.dart';

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(ready(), true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const origin = String.fromEnvironment(
    'MBN_QA_ORIGIN',
    defaultValue: 'http://127.0.0.1:8766',
  );
  for (final sample in [
    (file: 'mbn-legacy-h264.mkv', width: 1280, height: 720, original: false),
    (file: 'mbn-1080-h264.mkv', width: 1920, height: 1080, original: false),
    (file: 'mbn-main-h264.mkv', width: 1280, height: 720, original: true),
    (file: 'mbn-legacy-fallback.mkv', width: 640, height: 360, original: false),
  ]) {
    const only = String.fromEnvironment('MBN_QA_ONLY');
    if (only.isNotEmpty && sample.file != only) continue;
    testWidgets(
      'production ${sample.file} native ASS=${sample.original}',
      (tester) async {
        expect(Platform.isAndroid, true);
        await DevicePerformance.initialize();
        MediaKit.ensureInitialized();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('player_gestures_introduced', true);
        await prefs.setBool('sub_original_ass', sample.original);
        final file = File(
          '${(await getTemporaryDirectory()).path}/${sample.file}',
        );
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(
            Uri.parse('$origin/${sample.file}'),
          )).close();
          expect(response.statusCode, 200);
          await response.pipe(file.openWrite());
        } finally {
          client.close(force: true);
        }
        final episodes = [
          for (var i = 1; i <= 300; i++)
            MovieEpisode(
              id: '$i',
              name: 'قسمت $i',
              fileUrl: file.uri.toString(),
            ),
        ];
        final content = MovieContent(
          id: 'production-qa-${sample.file}-${sample.original}',
          title: 'Production playback QA',
          subtitle: '',
          description: '',
          year: 2026,
          rating: 0,
          kind: ContentKind.series,
          colors: const [],
          genres: const [],
          seasons: [MovieSeason(id: 's1', name: 'فصل 1', episodes: episodes)],
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
                          content: content,
                          episode: episodes.first,
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
          await until(tester, () => find.byType(Video).evaluate().isNotEmpty);
          expect(PlaybackActivity.active, isTrue);
          final player = tester
              .widget<Video>(find.byType(Video))
              .controller
              .player;
          final diagnostic = player.stream.log.listen((log) {
            debugPrint('MBN_PRODUCTION_LOG $log');
          });
          addTearDown(diagnostic.cancel);
          await Future<void>.delayed(const Duration(seconds: 2));
          final native = player.platform as NativePlayer;
          debugPrint(
            'MBN_PRODUCTION_STATE ${jsonEncode({
              for (final key in ['path', 'vo', 'hwdec', 'video-codec', 'pause', 'idle-active', 'vid']) key: await native.getProperty(key),
            })}',
          );
          await until(
            tester,
            () => player.state.position >= const Duration(seconds: 3),
          );
          final decoder = await native.getProperty('hwdec-current');
          final output = await native.getProperty('current-vo');
          // MediaCodec may expose padded coded height (1088 for 1080p).
          // Check the display dimensions used by the production texture.
          expect(player.state.videoParams.dw, sample.width);
          expect(player.state.videoParams.dh, sample.height);
          if (sample.file.contains('fallback')) {
            expect(output, 'gpu');
            expect(decoder, 'no');
          } else if (!sample.original &&
              const bool.fromEnvironment('MBN_QA_REQUIRE_MEDIACODEC')) {
            expect(decoder, 'mediacodec');
            expect(output, 'mediacodec_embed');
          }
          if (sample.original) {
            expect(output, 'gpu');
            expect(await native.getProperty('sub-visibility'), 'yes');
            expect(await native.getProperty('sub-ass-override'), 'no');
          } else {
            await until(
              tester,
              () => find.byType(PlayerSubtitleText).evaluate().isNotEmpty,
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find
                  .descendant(
                    of: find.byType(PlayerSubtitleText),
                    matching: find.byType(RichText),
                  )
                  .first,
            );
            final text = paragraph.text.toPlainText();
            final fixture = subtitleBidiCases.firstWhere(
              (s) => s.id == 'huawei-android-mixed',
            );
            final positions = <String, Map<String, double>>{};
            Rect box(String token) {
              final (start, end) = subtitleTokenRange(text, token);
              final rect = paragraph
                  .getBoxesForSelection(
                    TextSelection(baseOffset: start, extentOffset: end),
                  )
                  .first
                  .toRect();
              positions[token] = {'x': rect.center.dx, 'y': rect.top};
              return rect;
            }

            for (final (rtl, pairs) in [
              (true, fixture.rtl),
              (false, fixture.ltr),
            ]) {
              for (final (first, second) in pairs) {
                final a = box(first), b = box(second);
                expect(
                  (a.top - b.top).abs() > 1
                      ? a.top < b.top
                      : rtl
                      ? a.center.dx > b.center.dx
                      : a.center.dx < b.center.dx,
                  true,
                  reason: '$first before $second: $positions',
                );
              }
            }
            debugPrint('MBN_PRODUCTION_SUBTITLE ${jsonEncode(positions)}');
          }
          final start = player.state.position;
          final drops = await native.getProperty('frame-drop-count');
          final decoderDrops = await native.getProperty(
            'decoder-frame-drop-count',
          );
          await Future<void>.delayed(
            Duration(seconds: sample.file.contains('fallback') ? 2 : 8),
          );
          await tester.pump();
          debugPrint(
            'MBN_PRODUCTION_PLAYBACK ${jsonEncode({'file': sample.file, 'sdk': DevicePerformance.androidSdk, 'originalAss': sample.original, 'decoder': decoder, 'output': output, 'outputDropsStart': drops, 'outputDropsEnd': await native.getProperty('frame-drop-count'), 'decoderDropsStart': decoderDrops, 'decoderDropsEnd': await native.getProperty('decoder-frame-drop-count'), 'advancedMs': (player.state.position - start).inMilliseconds})}',
          );
          if (!sample.file.contains('fallback')) {
            expect(
              (player.state.position - start).inMilliseconds,
              greaterThan(6500),
            );
            if (!sample.original &&
                const bool.fromEnvironment('MBN_QA_REQUIRE_MEDIACODEC')) {
              // Debug builds and Surface resize may discard a few output
              // frames. Reject sustained loss (>3% at the 30fps fixture rate).
              expect(
                int.parse(await native.getProperty('frame-drop-count')) -
                    int.parse(drops),
                lessThanOrEqualTo(8),
              );
              expect(
                await native.getProperty('decoder-frame-drop-count'),
                decoderDrops,
              );
            }
            await player.pause();
            final position = player.state.position;
            await Future<void>.delayed(const Duration(milliseconds: 500));
            expect(
              (player.state.position - position).inMilliseconds.abs(),
              lessThan(400),
            );
            await player.seek(const Duration(seconds: 18));
            await player.play();
            await until(
              tester,
              () => player.state.position >= const Duration(seconds: 20),
            );
          }
          await tester.binding.handlePopRoute();
          await until(
            tester,
            () => find.byType(PlayerScreen).evaluate().isEmpty,
          );
          await Future<void>.delayed(const Duration(milliseconds: 750));
          await tester.pump();
          expect(PlaybackActivity.active, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await prefs.remove('sub_original_ass');
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
