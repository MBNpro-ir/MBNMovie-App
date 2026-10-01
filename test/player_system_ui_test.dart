import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/services/player_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    isAndroidTv = false;
    DevicePerformance.androidSdk = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  test('Android 6 explicitly restores both bars and portrait', () async {
    DevicePerformance.androidSdk = 23;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    await PlayerSystemUi.enter();
    await PlayerSystemUi.exit();
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.last.arguments, [
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
    expect(
      calls
          .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
          .last
          .arguments,
      ['DeviceOrientation.portraitUp'],
    );
  });
  test('late immersive entry cannot override exit', () async {
    DevicePerformance.androidSdk = 23;
    final pending = Completer<void>();
    final entered = Completer<void>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          if (call.arguments == 'SystemUiMode.immersiveSticky') {
            entered.complete();
            await pending.future;
          }
          return null;
        });
    final opening = PlayerSystemUi.enter();
    await entered.future;
    await PlayerSystemUi.exit();
    pending.complete();
    await opening;
    expect(calls.last.arguments, [
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
  });
  test('TV restores its persistent landscape immersive shell', () async {
    isAndroidTv = true;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    await PlayerSystemUi.exit();
    expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
  });
}
