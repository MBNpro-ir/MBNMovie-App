import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/models/movie_content.dart';
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
  testWidgets(
    'real player exit restores Android system bars and portrait',
    (tester) async {
      await initializeDeviceLayout();
      await DevicePerformance.initialize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('player_gestures_introduced', true);
      const channel = MethodChannel('com.mbn.movie/device');
      Future<Map<String, dynamic>> window() async =>
          await channel.invokeMapMethod<String, dynamic>('systemUiState') ?? {};
      final source = const String.fromEnvironment(
        'MBN_QA_MEDIA',
        defaultValue: 'http://10.0.2.2:8765/mbn-compatibility.mp4',
      );
      final item = MovieContent(
        id: 'native-fullscreen-qa',
        title: 'Native fullscreen QA',
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.movie,
        colors: const [],
        genres: const [],
      );
      final episode = MovieEpisode(id: 'one', name: '1', fileUrl: source);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlayerScreen(content: item, episode: episode),
                  ),
                ),
                child: const Text('open real player'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open real player'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final state = await window();
        if (state['orientation'] == 2 &&
            ((state['flags'] as int? ?? 0) & 4) != 0) {
          break;
        }
      }
      final playing = await window();
      expect(playing['orientation'], 2);
      expect(((playing['flags'] as int) & 4) != 0, true);
      final before = await _resourceSnapshot();
      final elapsed = Stopwatch()..start();
      for (var i = 0; i < 75; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final during = await _resourceSnapshot();
      await tester.binding.handlePopRoute();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (find.text('open real player').evaluate().isNotEmpty &&
            find.byType(PlayerScreen).evaluate().isEmpty) {
          break;
        }
      }
      expect(find.byType(PlayerScreen), findsNothing);
      final returned = await window();
      if (isAndroidTv) {
        expect(returned['orientation'], 2);
      } else {
        expect(returned['orientation'], 1);
        expect((returned['flags'] as int) & (2 | 4 | 2048 | 4096), 0);
        expect(returned['windowFullscreen'], false);
      }
      final after = await _resourceSnapshot();
      // Debug emulator measurements are diagnostics, not battery or release CPU claims.
      final diagnostics = jsonEncode({
        'sdk': DevicePerformance.androidSdk,
        'tv': isAndroidTv,
        'mode': 'debug-emulator',
        'seconds': elapsed.elapsedMilliseconds / 1000,
        'before': before,
        'playing': during,
        'afterReturn': after,
        'windowAfterReturn': returned,
      });
      debugPrint('MBN_RESOURCE $diagnostics');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<Map<String, Object>> _resourceSnapshot() async {
  final result = <String, Object>{'rssMiB': ProcessInfo.currentRss / 1048576};
  try {
    final stat = await File('/proc/self/stat').readAsString();
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    result['cpuTicks'] = int.parse(fields[11]) + int.parse(fields[12]);
  } catch (_) {}
  return result;
}
