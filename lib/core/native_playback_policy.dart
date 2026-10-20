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

  /// Runtime mpv settings that keep the Windows Flutter texture responsive.
  /// Disk caching is useful for a standalone mpv window, but writing a second
  /// copy of a network stream competes with Flutter's texture upload thread.
  /// Video framedrop is a last-resort safety valve: audio stays continuous
  /// instead of the whole player stopping when a machine briefly falls behind.
  static Map<String, String> playerProperties({required bool windows}) => {
    if (windows) ...{
      'cache-on-disk': 'no',
      'framedrop': 'vo',
      'interpolation': 'no',
      'vd-lavc-threads': 'auto',
    },
  };
}
