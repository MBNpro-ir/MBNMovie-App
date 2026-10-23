import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

// Run on an actual Android device. Baseline failures are recorded separately;
// the direct output must really use MediaCodec when the hardware gate is set.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'compare GPU and direct MediaCodec output',
    (tester) async {
      MediaKit.ensureInitialized();
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/surface-720.mkv');
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse(
            const String.fromEnvironment(
              'MBN_QA_MEDIA',
              defaultValue: 'http://127.0.0.1:8766/mbn-legacy-h264.mkv',
            ),
          ),
        )).close();
        expect(response.statusCode, 200);
        await response.pipe(file.openWrite());
      } finally {
        client.close(force: true);
      }
      for (final output in [
        if (const bool.fromEnvironment('MBN_QA_COMPARE_GPU')) 'gpu',
        'mediacodec_embed',
      ]) {
        final player = Player(
          configuration: const PlayerConfiguration(logLevel: MPVLogLevel.debug),
        );
        final controller = VideoController(
          player,
          configuration: VideoControllerConfiguration(
            vo: output,
            hwdec: output == 'gpu'
                ? 'mediacodec,mediacodec-copy'
                : 'mediacodec',
            width: 1280,
            height: 720,
          ),
        );
        final logs = <String>[];
        final subscription = player.stream.log.listen((log) {
          if (log.level == 'error') logs.add(log.text);
          if (log.prefix.startsWith('vd') ||
              log.prefix.startsWith('ffmpeg') ||
              log.prefix.startsWith('vo')) {
            debugPrint('MBN_CODEC_TRACE $log');
          }
        });
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Video(
                controller: controller,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: false,
                ),
              ),
            ),
          );
          await tester.pump();
          final native = player.platform as NativePlayer;
          await native.setProperty('cache-on-disk', 'no');
          await native.setProperty('vd-lavc-o', 'ndk_codec=yes');
          await player.open(Media(file.uri.toString()));
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (player.state.position < const Duration(seconds: 3) &&
              DateTime.now().isBefore(deadline)) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (output == 'mediacodec_embed') {
            expect(player.state.position.inSeconds, greaterThanOrEqualTo(2));
          }
          final startDrops = await native.getProperty('frame-drop-count');
          final start = player.state.position;
          await Future<void>.delayed(const Duration(seconds: 8));
          await tester.pump();
          final decoder = await native.getProperty('hwdec-current');
          final result = {
            'outputRequested': output,
            'actualOutput': await native.getProperty('current-vo'),
            'decoder': decoder,
            'codec': await native.getProperty('video-codec'),
            'width': await native.getProperty('width'),
            'height': await native.getProperty('height'),
            'outputDropsStart': startDrops,
            'outputDropsEnd': await native.getProperty('frame-drop-count'),
            'decoderDrops': await native.getProperty(
              'decoder-frame-drop-count',
            ),
            'advancedMs': (player.state.position - start).inMilliseconds,
            'errors': logs,
          };
          debugPrint('MBN_SURFACE_QA ${jsonEncode(result)}');
          if (output == 'mediacodec_embed') {
            expect(
              (player.state.position - start).inMilliseconds,
              greaterThan(6500),
            );
          }
          if (output == 'mediacodec_embed' &&
              const bool.fromEnvironment('MBN_QA_REQUIRE_MEDIACODEC')) {
            expect(decoder, 'mediacodec');
            expect(result['actualOutput'], 'mediacodec_embed');
            expect(result['outputDropsEnd'], startDrops);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await subscription.cancel();
          await player.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
