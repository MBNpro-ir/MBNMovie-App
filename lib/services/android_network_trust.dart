import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'device_performance.dart';

/// Extend older Android trust with official ISRG roots, retaining verification.
abstract final class AndroidNetworkTrust {
  static bool _initialized = false;
  static Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        !Platform.isAndroid ||
        DevicePerformance.androidSdk >= 31) {
      return;
    }
    for (final name in ['isrg-root-x1.pem', 'isrg-root-x2.pem']) {
      final data = await rootBundle.load('assets/certificates/$name');
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    _initialized = true;
  }
}
