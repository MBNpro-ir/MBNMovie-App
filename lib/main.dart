import 'package:flutter/foundation.dart';
import 'core/app_platform.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/platform_ui.dart';
import 'screens/update_screen.dart';
import 'services/accessibility_service.dart';
import 'services/app_links.dart';
import 'services/download_manager.dart';
import 'services/device_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  DeviceBridge.initialize();
  await initializeDeviceLayout();
  await AccessibilityService.instance.initialize();
  if (isAndroidTv) {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1000, 650),
      center: true,
      backgroundColor: Color(0xFF080A0F),
      title: 'MBNMovie',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } else if (isAndroidTv) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
  if (!kIsWeb) UpdatePresentation.start();
  runApp(const MbnmovieApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (kIsWeb) return;
    AppLinks.registerThisApp(appId: 'MBNMovie', exeName: 'mbnmovie.exe');
    DownloadManager.instance.initialize().catchError((Object error) {
      DownloadManager.instance.error = 'راه‌اندازی دانلودها انجام نشد.';
    });
  });
}
