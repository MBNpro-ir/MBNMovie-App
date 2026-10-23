import 'package:mbnmovie/core/video_decode_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/native_playback_policy.dart';

void main() {
  test(
    'software mode bypasses MediaCodec surfaces but retains GPU rendering',
    () {
      for (final android in [true, false]) {
        for (final sdk in [0, 23, 26, 28, 29, 32, 35]) {
          final config = NativePlaybackPolicy.videoConfiguration(
            android: android,
            sdk: sdk,
            emulator: false,
            decoderMode: VideoDecodeMode.software,
          );
          expect(config.hwdec, 'no');
          expect(config.vo, isNull);
          expect(config.enableHardwareAcceleration, isTrue);
          expect(
            NativePlaybackPolicy.playerProperties(
              windows: !android,
              android: android,
              sdk: sdk,
              decoderMode: VideoDecodeMode.software,
            ),
            isNot(contains('vd-lavc-o')),
          );
        }
      }
    },
  );

  test('old physical Android prefers the direct decoder with fallback', () {
    for (final sdk in [23, 24, 25, 26, 27, 28, 29, 30, 31, 32]) {
      final config = NativePlaybackPolicy.videoConfiguration(
        android: true,
        sdk: sdk,
        emulator: false,
      );
      expect(
        config.hwdec,
        sdk <= 28 ? 'mediacodec' : 'mediacodec,mediacodec-copy',
      );
      expect(config.enableHardwareAcceleration, isTrue);
      expect(config.vo, sdk <= 28 ? 'mediacodec_embed' : null);
    }
  });

  test(
    'new Android, unknown profiles, emulators and other platforms keep defaults',
    () {
      for (final sdk in [0, 22, 33, 34, 35, 37]) {
        expect(
          NativePlaybackPolicy.videoConfiguration(
            android: true,
            sdk: sdk,
            emulator: false,
          ).hwdec,
          isNull,
        );
      }
      for (final sdk in [23, 26, 27, 28, 29, 30, 31, 32, 35]) {
        expect(
          NativePlaybackPolicy.videoConfiguration(
            android: true,
            sdk: sdk,
            emulator: true,
          ).hwdec,
          isNull,
        );
        expect(
          NativePlaybackPolicy.videoConfiguration(
            android: false,
            sdk: sdk,
            emulator: false,
          ).hwdec,
          isNull,
        );
      }
    },
  );

  test('native player policies avoid stalls on Windows and old Android', () {
    expect(
      NativePlaybackPolicy.playerProperties(windows: true),
      containsPair('cache-on-disk', 'no'),
    );
    expect(
      NativePlaybackPolicy.playerProperties(windows: true),
      containsPair('framedrop', 'vo'),
    );
    expect(
      int.tryParse(
        NativePlaybackPolicy.playerProperties(
          windows: true,
        )['vd-lavc-threads']!,
      ),
      0,
    );
    final android = NativePlaybackPolicy.playerProperties(
      windows: false,
      android: true,
      sdk: 23,
    );
    expect(android, containsPair('framedrop', 'vo'));
    expect(android, containsPair('scale', 'bilinear'));
    expect(android, containsPair('dscale', 'bilinear'));
    expect(int.tryParse(android['vd-lavc-threads']!), 0);
    expect(
      NativePlaybackPolicy.playerProperties(
        windows: false,
        android: true,
        sdk: 33,
      ),
      isEmpty,
    );
    expect(
      NativePlaybackPolicy.playerProperties(
        windows: false,
        android: true,
        sdk: 33,
        television: true,
      ),
      containsPair('framedrop', 'vo'),
    );
  });
}
