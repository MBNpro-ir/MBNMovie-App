import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/services/android_network_trust.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  HttpOverrides.global = null;

  testWidgets(
    'native device profile, encryption, files and video work on API 23',
    (tester) async {
      await initializeDeviceLayout();
      await DevicePerformance.initialize();
      await AndroidNetworkTrust.initialize();
      expect(DevicePerformance.androidSdk, greaterThanOrEqualTo(23));
      const expectedSdk = int.fromEnvironment('MBN_QA_EXPECT_SDK');
      if (expectedSdk > 0) expect(DevicePerformance.androidSdk, expectedSdk);
      if (const bool.fromEnvironment('MBN_QA_EXPECT_TV')) {
        expect(isAndroidTv, isTrue);
      }
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
      if (const bool.fromEnvironment('MBN_QA_HEALTH')) {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('https://login.a.mbnpro.ir/api/health'),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          expect(response.statusCode, 200);
          await response.drain<void>();
          final downloader = FileDownloader();
          final task = DownloadTask(
            url: 'https://login.a.mbnpro.ir/api/health',
            filename: 'mbn-compatibility-https.json',
            baseDirectory: BaseDirectory.applicationDocuments,
          );
          final record = await downloader
              .download(task)
              .timeout(const Duration(seconds: 30));
          expect(record.status, TaskStatus.complete);
          final downloaded = File(await task.filePath());
          expect(await downloaded.readAsString(), contains('"ok"'));
          await downloaded.delete();
        } finally {
          client.close(force: true);
        }
      }
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
            const String.fromEnvironment(
              'MBN_QA_MEDIA',
              defaultValue: 'http://10.0.2.2:8765/mbn-compatibility.mp4',
            ),
          ),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (player.state.position <= const Duration(seconds: 2) &&
            errors.isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await player.pause();
        expect(errors, isEmpty);
        expect(player.state.duration, greaterThan(Duration.zero));
        expect(player.state.position, greaterThan(const Duration(seconds: 2)));
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
