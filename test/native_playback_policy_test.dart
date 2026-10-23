import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/native_playback_policy.dart';

void main() {
  test('old physical Android prefers the direct decoder with fallback', () {
    for (final sdk in [23, 24, 25, 26, 27, 28, 29, 30, 31, 32]) {
      final config = NativePlaybackPolicy.videoConfiguration(
        android: true,
        sdk: sdk,
        emulator: false,
      );
      expect(config.hwdec, 'mediacodec,mediacodec-copy');
      expect(config.enableHardwareAcceleration, isTrue);
      // Keep GPU compositing: direct-to-display VO cannot render ASS subtitles.
      expect(config.vo, isNull);
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
