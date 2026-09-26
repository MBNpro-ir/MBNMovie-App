import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/screens/download_manager_screen.dart';
import 'package:mbnmovie/services/download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1440, 900),
  ]) {
    testWidgets('download controls and playback chooser fit $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'mbnmovie-download-ui-',
      );
      final file = File('${directory.path}/episode.mkv')..writeAsBytesSync([0]);
      addTearDown(() {
        file.deleteSync();
        directory.deleteSync();
      });
      final task = DownloadTask(
        url: 'https://example.org/video.mkv',
        filename: 'episode.mkv',
        directory: directory.path,
        baseDirectory: BaseDirectory.root,
        displayName: 'نام طولانی فیلم و سریال برای بررسی چیدمان دانلود در گوشی',
      );
      final manager = DownloadManager.instance;
      manager.records[task.taskId] = TaskRecord(
        task,
        TaskStatus.complete,
        1,
        1000,
      );
      addTearDown(manager.records.clear);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: DownloadManagerScreen(initializeDownloads: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('پخش'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('پخش'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('پخش'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('پلیر داخلی (پیشنهادی)'), findsOneWidget);
      await tester.tap(find.text('پلیرهای خارجی'));
      await tester.pumpAndSettle();
      expect(find.text('VLC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
