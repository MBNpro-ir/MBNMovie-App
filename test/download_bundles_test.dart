import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/download_bundles.dart';
import 'package:mbnmovie/screens/download_manager_screen.dart';
import 'package:mbnmovie/services/download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskRecord record(
  String taskId,
  String displayName, {
  Map<String, String> meta = const {},
  TaskStatus status = TaskStatus.enqueued,
  double progress = 0,
}) {
  final task = DownloadTask(
    url: 'https://example.org/$taskId.mkv',
    filename: '$taskId.mkv',
    directory: '/tmp',
    baseDirectory: BaseDirectory.root,
    displayName: displayName,
    // پیش‌فرض یک باندل مشترک تا تست‌های منطق دکمه یک باندل چندعضوی بگیرند؛
    // با دادن bundleId صریح می‌شود جدا یا هم‌باندل کرد.
    metaData: jsonEncode({'bundleId': 'test-bundle', ...meta}),
  );
  return TaskRecord(task, status, progress, 1000);
}

void main() {
  test('tasks with the same bundleId form one bundle', () {
    final bundles = groupDownloadRecords([
      record('a1', 'فیلم · 1080p', meta: {
        'title': 'فیلم',
        'season': 'کیفیت‌های پخش · 1080p',
        'bundleId': 'b1',
      }, status: TaskStatus.complete, progress: 1),
      record('a2', 'فیلم · 720p', meta: {
        'title': 'فیلم',
        'season': 'کیفیت‌های پخش · 720p',
        'bundleId': 'b1',
      }, progress: .5),
      record('solo', 'سریال · قسمت 1', meta: {'title': 'سریال'}),
    ]);

    expect(bundles, hasLength(2));
    final bundle = bundles.firstWhere((item) => !item.isSingle);
    expect(bundle.records, hasLength(2));
    expect(bundle.completeCount, 1);
    expect(bundle.progress, closeTo(.75, .001));
    expect(bundle.subtitle, contains('2 فایل'));
    expect(
      bundles.where((item) => item.isSingle).single.records.single.task
          .displayName,
      'سریال · قسمت 1',
    );
  });

  test('bundle pause/resume buttons show only when meaningful', () {
    DownloadBundle bundleOf(List<TaskRecord> members) =>
        groupDownloadRecords(members).single;

    // فقط در حال اجرا: توقف معنادار، ادامه نه.
    final runningOnly = bundleOf([
      record('r1', 'a', status: TaskStatus.running, progress: .5),
      record('r2', 'b', status: TaskStatus.enqueued),
    ]);
    expect(bundleCanPause(runningOnly), isTrue);
    expect(bundleCanResume(runningOnly), isFalse);

    // فقط در صف (شروع‌نشده): توقف گروهی باید دیده شود تا صف نگه داشته شود.
    final queuedOnly = bundleOf([
      record('q1', 'a'),
      record('q2', 'b'),
    ]);
    expect(bundleCanPause(queuedOnly), isTrue);
    expect(bundleCanResume(queuedOnly), isFalse);

    // فقط متوقف: ادامه معنادار، توقف نه.
    final pausedOnly = bundleOf([
      record('p1', 'a', status: TaskStatus.paused, progress: .3),
    ]);
    expect(bundleCanPause(pausedOnly), isFalse);
    expect(bundleCanResume(pausedOnly), isTrue);

    // holdِ توقف گروهی دسکتاپ هم «ادامه همه» را روشن می‌کند.
    final held = bundleOf([
      record('h1', 'a', status: TaskStatus.canceled),
    ]);
    expect(bundleCanResume(held), isFalse);
    expect(
      bundleCanResume(held, {held.records.single.task.taskId}),
      isTrue,
    );

    // تکمیل‌شده: هیچ‌کدام.
    final done = bundleOf([
      record('d1', 'a', status: TaskStatus.complete, progress: 1),
    ]);
    expect(bundleCanPause(done), isFalse);
    expect(bundleCanResume(done), isFalse);
  });

  testWidgets('bundle of two files shows as one expandable group', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final manager = DownloadManager.instance;
    manager.records['x1'] = record('x1', 'فیلم · 1080p', meta: {
      'title': 'فیلم',
      'season': 'کیفیت‌های پخش',
      'bundleId': 'bundle-x',
    });
    manager.records['x2'] = record('x2', 'فیلم · 720p', meta: {
      'title': 'فیلم',
      'season': 'کیفیت‌های پخش',
      'bundleId': 'bundle-x',
    });
    addTearDown(manager.records.clear);
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DownloadManagerScreen(initializeDownloads: _noop),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1 باندل · 2 فایل'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(ExpansionTile),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('فیلم · 720p'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('فیلم · 1080p'), findsWidgets);
    expect(find.text('فیلم · 720p'), findsWidgets);
    // باندلِ در صف: «توقف همه» دارد (یکی پنل، یکی باندل) ولی «ادامه همه»
    // ندارد چون عضوی متوقف نیست.
    expect(find.text('توقف همه'), findsNWidgets(2));
    expect(find.text('ادامه همه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _noop() async {}
