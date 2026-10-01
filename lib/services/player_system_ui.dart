import 'package:flutter/services.dart';
import '../core/platform_ui.dart';
import 'device_performance.dart';

/// Keep orientation and system bars in the same lifecycle. An async entry
/// completing after back-navigation must not hide the restored bars again.
abstract final class PlayerSystemUi {
  static int _generation = 0;
  static bool _active = false;

  static Future<void> enter() async {
    final generation = ++_generation;
    _active = true;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (generation != _generation) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (generation != _generation && !_active) await _showAppUi();
  }

  static Future<void> exit() async {
    ++_generation;
    _active = false;
    await SystemChrome.setPreferredOrientations(
      isAndroidTv
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    if (!_active) await _showAppUi();
  }

  static Future<void> _showAppUi() => isAndroidTv
      ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
      : DevicePerformance.androidSdk >= 35
      ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
      : SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
        );
}
