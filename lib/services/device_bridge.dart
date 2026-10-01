import '../core/app_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class DeviceBridge {
  static const channel = MethodChannel('com.mbn.movie/device');
  static final installStatus = ValueNotifier<String?>(null);
  static bool _initialized = false;

  static void initialize() {
    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'updateInstallStatus') {
        installStatus.value = call.arguments as String?;
      }
    });
  }

  static Future<bool> wirelessDisplay() async {
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('wirelessDisplay') ?? false;
    }
    if (Platform.isWindows) {
      return await channel.invokeMethod<bool>('wirelessDisplay') ?? false;
    }
    return false;
  }

  static Future<String> updatePlatform() async => Platform.isWindows
      ? 'Windows-x64'
      : 'Android-${await channel.invokeMethod<String>('abi')}';
  static Future<bool> storageGranted() async =>
      !Platform.isAndroid ||
      await channel.invokeMethod<bool>('storageGranted') == true;
  static Future<void> requestStorage() =>
      channel.invokeMethod<void>('requestStorage');
  static Future<String> downloadsDirectory() async =>
      (await channel.invokeMethod<String>('downloadsDirectory'))!;
  static Future<String> installApk(String path) async =>
      await channel.invokeMethod<String>('installApk', {'path': path}) ??
      'failed';
  static Future<bool> requestInstallPermission() async =>
      await channel.invokeMethod<bool>('requestInstallPermission') == true;

  /// Cross-app handoff: is the sibling package installed / open it.
  static Future<bool> isAppInstalled(String package) async {
    if (!Platform.isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('isAppInstalled', {
            'package': package,
          }) ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> takeHandoff() async =>
      Platform.isAndroid ? channel.invokeMethod<String>('takeHandoff') : null;

  static Future<void> saveAuthBridge({
    required String token,
    required String email,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod('saveAuthBridge', {
        'token': token,
        'email': email,
      });
    } catch (_) {}
  }

  static Future<void> clearAuthBridge() async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod('clearAuthBridge');
    } catch (_) {}
  }

  static Future<Map<String, String>?> readSiblingAuth(String package) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await channel.invokeMapMethod<String, dynamic>(
        'readSiblingAuth',
        {'package': package},
      );
      if (res != null) {
        final token = res['token']?.toString();
        final email = res['email']?.toString() ?? '';
        if (token != null && token.isNotEmpty) {
          return {'token': token, 'email': email};
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> openApp(String package, {String? handoff}) async {
    if (!Platform.isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('openApp', {
            'package': package,
            'handoff': handoff,
          }) ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<double> mediaVolume() async =>
      await channel.invokeMethod<double>('mediaVolume') ?? 1;
  static Future<double> setMediaVolume(
    double value, {
    bool showUi = true,
  }) async =>
      await channel.invokeMethod<double>('setMediaVolume', {
        'value': value.clamp(0, 1),
        'showUi': showUi,
      }) ??
      value.clamp(0, 1);
  static Future<double> screenBrightness() async =>
      await channel.invokeMethod<double>('screenBrightness') ?? .5;
  static Future<void> setScreenBrightness(double? value) =>
      channel.invokeMethod<void>('setScreenBrightness', {
        'value': value?.clamp(0, 1) ?? -1.0,
      });
  static Future<void> openFolder(String path) async {
    if (Platform.isWindows) {
      await Directory(path).create(recursive: true);
      await Process.start('explorer.exe', [
        path,
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isAndroid) {
      if (await channel.invokeMethod<bool>('openDownloads') != true) {
        throw const FileSystemException('برنامهٔ مدیریت فایل پیدا نشد');
      }
    } else {
      if (!await launchUrl(
        Uri.directory(path),
        mode: LaunchMode.externalApplication,
      )) {
        throw const FileSystemException('پوشه باز نشد');
      }
    }
  }
}
