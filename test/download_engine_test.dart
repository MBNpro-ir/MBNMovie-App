import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-memory platform-independent store; records round-trip through the exact
/// persisted schema. Real HTTP and file IO exercise the production desktop engine.
class TestDownloadStorage implements PersistentStorage {
  final records = <String, Map<String, dynamic>>{};
  final paused = <String, Task>{};
  final resumes = <String, ResumeData>{};
  @override
  (String, int) get currentDatabaseVersion => ('test', 1);
  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> storeTaskRecord(TaskRecord record) async {
    records[record.taskId] = record.toJson();
  }

  @override
  Future<TaskRecord?> retrieveTaskRecord(String id) async =>
      records[id] == null ? null : TaskRecord.fromJson(records[id]!);
  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async =>
      records.values.map(TaskRecord.fromJson).toList();
  @override
  Future<void> removeTaskRecord(String? id) async {
    id == null ? records.clear() : records.remove(id);
  }

  @override
  Future<void> storePausedTask(Task task) async {
    paused[task.taskId] = task;
  }

  @override
  Future<Task?> retrievePausedTask(String id) async => paused[id];
  @override
  Future<List<Task>> retrieveAllPausedTasks() async => paused.values.toList();
  @override
  Future<void> removePausedTask(String? id) async {
    id == null ? paused.clear() : paused.remove(id);
  }

  @override
  Future<void> storeResumeData(ResumeData data) async {
    resumes[data.task.taskId] = data;
  }

  @override
  Future<ResumeData?> retrieveResumeData(String id) async => resumes[id];
  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      resumes.values.toList();
  @override
  Future<void> removeResumeData(String? id) async {
    id == null ? resumes.clear() : resumes.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  final storage = TestDownloadStorage();
  final downloader = FileDownloader(persistentStorage: storage);
  final updates = downloader.updates.asBroadcastStream();
  late Directory directory;
  late HttpServer server;
  final payload = List.generate(2 * 1024 * 1024, (index) => index % 251);
  var rangeRequests = 0;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('mbnmovie-download-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await downloader.ready;
    await downloader.configure(
      globalConfig: [
        (Config.tempFilePath, directory.path),
        (Config.holdingQueue, (2, 2, 2)),
      ],
    );
    await downloader.trackTasks();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.uri.path == '/missing') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final start = range == null
            ? 0
            : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
        if (range != null) {
          rangeRequests++;
          request.response.statusCode = 206;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${payload.length - 1}/${payload.length}',
          );
        }
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(HttpHeaders.etagHeader, '"mbnmovie-test"');
        request.response.contentLength = payload.length - start;
        for (var offset = start; offset < payload.length; offset += 32768) {
          request.response.add(
            payload.sublist(offset, (offset + 32768).clamp(0, payload.length)),
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await request.response.close();
      } catch (_) {
        /* Expected when the client pauses or cancels. */
      }
    });
  });
  tearDownAll(() async {
    await downloader.reset();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    downloader.destroy();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  DownloadTask task(String name, {String path = '/file'}) => DownloadTask(
    url: 'http://127.0.0.1:${server.port}$path',
    filename: '$name.bin',
    baseDirectory: BaseDirectory.root,
    directory: directory.path,
    taskId: name,
    allowPause: true,
    updates: Updates.statusAndProgress,
  );
  Future<TaskStatusUpdate> status(String id, TaskStatus value) => updates
      .where(
        (event) =>
            event is TaskStatusUpdate &&
            event.task.taskId == id &&
            event.status == value,
      )
      .cast<TaskStatusUpdate>()
      .first
      .timeout(const Duration(seconds: 15));

  test(
    'pause/resume uses Range and produces the exact original file',
    () async {
      final download = task('resume');
      final progressing = updates
          .where(
            (e) =>
                e is TaskProgressUpdate &&
                e.task.taskId == download.taskId &&
                e.progress > 0 &&
                e.progress < .8,
          )
          .first;
      expect(await downloader.enqueue(download), isTrue);
      await progressing.timeout(const Duration(seconds: 10));
      final paused = status(download.taskId, TaskStatus.paused);
      expect(await downloader.pause(download), isTrue);
      await paused;
      final complete = status(download.taskId, TaskStatus.complete);
      expect(await downloader.resume(download), isTrue);
      await complete;
      final data = await File(await download.filePath()).readAsBytes();
      expect(sha256.convert(data), sha256.convert(payload));
      expect(rangeRequests, greaterThan(0));
      final record = await downloader.database.recordForId(download.taskId);
      expect(record?.status, TaskStatus.complete);
    },
  );
  test('held queue wakes on resume and never writes before resume', () async {
    await downloader.configure(
      globalConfig: [(Config.holdingQueue, (0, 1, 1))],
    );
    final download = task('held');
    await downloader.enqueue(download);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(await File(await download.filePath()).exists(), isFalse);
    final complete = status(download.taskId, TaskStatus.complete);
    await downloader.configure(
      globalConfig: [(Config.holdingQueue, (1, 1, 1))],
    );
    await complete;
  });
  test('404 and cancellation never masquerade as completed files', () async {
    final missing = task('missing', path: '/missing');
    final notFound = status(missing.taskId, TaskStatus.notFound);
    await downloader.enqueue(missing);
    await notFound;
    expect(await File(await missing.filePath()).exists(), isFalse);
    final canceled = task('canceled');
    final running = status(canceled.taskId, TaskStatus.running);
    await downloader.enqueue(canceled);
    await running;
    final ended = status(canceled.taskId, TaskStatus.canceled);
    await downloader.cancelTaskWithId(canceled.taskId);
    await ended;
    expect(await File(await canceled.filePath()).exists(), isFalse);
  });
}
