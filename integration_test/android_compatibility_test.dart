import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/services/device_performance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native device profile, encryption, files and video work on API 23',
    (tester) async {
      await initializeDeviceLayout();
      await DevicePerformance.initialize();
      expect(DevicePerformance.androidSdk, greaterThanOrEqualTo(23));
      const expectedSdk = int.fromEnvironment('MBN_QA_EXPECT_SDK');
      if (expectedSdk > 0) expect(DevicePerformance.androidSdk, expectedSdk);
      if (DevicePerformance.androidSdk < 31 || isAndroidTv) {
        expect(DevicePerformance.lightweight, isTrue);
        expect(
          PaintingBinding.instance.imageCache.maximumSizeBytes,
          48 * 1024 * 1024,
        );
      }
      const storage = FlutterSecureStorage();
      final key =
          'mbn_compatibility_qa_${DateTime.now().microsecondsSinceEpoch}';
      try {
        await storage.write(key: key, value: 'native-encrypted-value');
        expect(await storage.read(key: key), 'native-encrypted-value');
        await storage.write(key: key, value: 'updated-value');
        expect(await storage.read(key: key), 'updated-value');
      } finally {
        await storage.delete(key: key);
      }
      expect(await storage.read(key: key), isNull);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/mbn-compatibility-qa.txt');
      try {
        await file.writeAsString('Android file access');
        expect(await file.readAsString(), 'Android file access');
      } finally {
        if (await file.exists()) await file.delete();
      }

      MediaKit.ensureInitialized();
      final player = Player();
      final errors = <String>[];
      final subscription = player.stream.error.listen(errors.add);
      final controller = VideoController(player);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 640,
                  height: 360,
                  child: Video(controller: controller),
                ),
              ),
            ),
          ),
        );
        await player.open(
          Media(
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
          ),
        );
        await tester.runAsync(
          () => player.stream.position
              .firstWhere((position) => position > const Duration(seconds: 2))
              .timeout(const Duration(seconds: 60)),
        );
        await player.pause();
        expect(player.state.duration, greaterThan(Duration.zero));
        expect(errors, isEmpty);
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await subscription.cancel();
        await player.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
