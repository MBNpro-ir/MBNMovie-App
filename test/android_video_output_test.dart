import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/bounded_video_output.dart';
import 'package:mbnmovie/core/native_playback_policy.dart';

void main() {
  test(
    'Android render surface preserves aspect ratio within display bounds',
    () {
      final small = boundedVideoOutput(
        1280,
        720,
        maxWidth: 800,
        maxHeight: 480,
      );
      expect([small.width, small.height], [800, 450]);
      final high = boundedVideoOutput(
        2560,
        1440,
        maxWidth: 1280,
        maxHeight: 720,
      );
      expect([high.width, high.height], [1280, 720]);
      expect(high.width * high.height, 2560 * 1440 ~/ 4);
      final portrait = boundedVideoOutput(
        1080,
        1920,
        maxWidth: 1280,
        maxHeight: 720,
      );
      expect([portrait.width, portrait.height], [405, 720]);
      final low = boundedVideoOutput(320, 180, maxWidth: 1280, maxHeight: 720);
      expect([low.width, low.height], [320, 180]);
      final native = boundedVideoOutput(3840, 2160);
      expect([native.width, native.height], [3840, 2160]);
      expect(boundedVideoOutput(0, 0).width, 0);
    },
  );
  test(
    'only constrained Android receives render bounds; decoder stays accelerated',
    () {
      final config = NativePlaybackPolicy.videoConfiguration(
        android: true,
        sdk: 23,
        emulator: false,
        lightweight: true,
        displayWidth: 1280,
        displayHeight: 720,
      );
      expect([config.width, config.height], [1280, 720]);
      expect(config.hwdec, 'mediacodec');
      expect(config.enableHardwareAcceleration, true);
      for (final android in [true, false]) {
        final defaults = NativePlaybackPolicy.videoConfiguration(
          android: android,
          sdk: 35,
          emulator: false,
          displayWidth: 1280,
          displayHeight: 720,
        );
        expect(defaults.width, isNull);
        expect(defaults.height, isNull);
      }
    },
  );
}
