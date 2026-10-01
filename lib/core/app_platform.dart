// dart:io types remain available for guarded native features.
export 'dart:io' hide Platform;
import 'dart:io' as io;
import 'package:flutter/foundation.dart';

abstract final class Platform {
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
  static String get operatingSystem => kIsWeb ? 'web' : io.Platform.operatingSystem;
  static String get resolvedExecutable => kIsWeb ? '' : io.Platform.resolvedExecutable;
  static Map<String, String> get environment => kIsWeb ? const {} : io.Platform.environment;
}
