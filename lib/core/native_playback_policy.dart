import 'package:media_kit_video/media_kit_video.dart';

/// Decoder selection is device-local; never save or sync it as a preference.
abstract final class NativePlaybackPolicy {
  static VideoControllerConfiguration videoConfiguration({
    required bool android,
    required int sdk,
    required bool emulator,
  }) => VideoControllerConfiguration(
    enableHardwareAcceleration: true,
    // mpv's auto-safe selects mediacodec-copy on Android. On older phones,
    // copying every decoded frame through CPU RAM can dominate playback even
    // when Flutter's UI is smooth. Prefer the GPU surface path, then retain
    // copy-back and mpv's automatic software fallback for unsupported files.
    // Keep the plugin's defaults (including its emulator guard) elsewhere.
    hwdec: android && sdk >= 23 && sdk <= 32 && !emulator
        ? 'mediacodec,mediacodec-copy'
        : null,
  );
}
