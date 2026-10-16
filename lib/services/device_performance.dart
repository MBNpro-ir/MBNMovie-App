import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_platform.dart';
import 'browser_features.dart';

/// Resource policy is local to the device, never copied by account sync.
abstract final class DevicePerformance {
  static int androidSdk = 0;
  static bool lowRam = false;
  static bool television = false;
  static bool appleMobileWeb = false;

  static bool useLightweightUiFor({
    required int sdk,
    required bool lowRam,
    required bool television,
    bool appleMobileWeb = false,
  }) => appleMobileWeb || (sdk > 0 && sdk < 31) || lowRam || television;

  static bool get lightweight => useLightweightUiFor(
    sdk: androidSdk,
    lowRam: lowRam,
    television: television,
    appleMobileWeb: appleMobileWeb,
  );
  static int artworkWidth(bool portrait) => appleMobileWeb
      ? (portrait ? 240 : 640)
      : lightweight
      ? (portrait ? 320 : 960)
      : (portrait ? 512 : 1280);
  static Duration get routeDuration => Duration(
    milliseconds: appleMobileWeb
        ? 120
        : lightweight
        ? 180
        : 380,
  );

  /// Detect the browser profile synchronously so the first web frame already
  /// uses the lightweight Apple-mobile policy. Shared preferences are loaded
  /// later and can refine the user-selected scale without blocking startup.
  static void configureWeb() {
    if (!kIsWeb) return;
    appleMobileWeb = BrowserFeatures.isAppleMobile;
    if (appleMobileWeb) {
      PaintingBinding.instance.imageCache
        ..maximumSize = 80
        ..maximumSizeBytes = 24 * 1024 * 1024;
    }
  }

  static Future<void> initialize() async {
    configureWeb();
    if (appleMobileWeb) {
      PaintingBinding.instance.imageCache
        ..maximumSize = 80
        ..maximumSizeBytes = 24 * 1024 * 1024;
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      final info = await const MethodChannel(
        'com.mbn.movie/device',
      ).invokeMapMethod<String, dynamic>('performanceInfo');
      androidSdk = (info?['sdk'] as num?)?.toInt() ?? 0;
      lowRam = info?['lowRam'] == true;
      television = info?['television'] == true;
    } on MissingPluginException {
      // An older installed binary does not yet expose the profile.
    } on PlatformException {
      // Startup remains usable if a vendor cannot report device information.
    }
    if (lightweight) {
      PaintingBinding.instance.imageCache
        ..maximumSize = 140
        ..maximumSizeBytes = 48 * 1024 * 1024;
    }
  }
}
