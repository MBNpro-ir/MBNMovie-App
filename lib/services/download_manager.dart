import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/download_paths.dart';
import '../core/episode_catalog.dart';
import '../models/movie_content.dart';
import 'device_bridge.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final instance = DownloadManager._();
  static const group = 'mbnmovie-media';
  final downloader = FileDownloader();
  final Map<String, TaskRecord> records = {};
  final Map<String, TaskProgressUpdate> progress = {};
  Future<void>? _initialization;
  StreamSubscription<TaskUpdate>? _subscription;
  Future<void> _queueLock = Future.value();
  bool wifiOnly = false;
  int concurrency = 2;
  bool allPaused = false;
  String? error;
  static const _heldKey = 'downloads_held';

  /// Displayed status: desktop/mobile bundle holds cancel waiting tasks but
  /// keep their ids in [heldForPause]; the UI must show them as paused, not
  /// canceled, and filters/cleanup/resume must use this too.
  TaskStatus effectiveStatus(TaskRecord record) =>
      heldForPause.contains(record.task.taskId) &&
              record.status == TaskStatus.canceled
          ? TaskStatus.paused
          : record.status;

  Future<void> _loadHeld() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      heldForPause
        ..clear()
        ..addAll(prefs.getStringList(_heldKey) ?? const <String>[]);
    } catch (_) {}
  }

  Future<void> _saveHeld() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_heldKey, heldForPause.toList());
    } catch (_) {}
  }

  Future<DownloadTask> _freshDownloadTask(DownloadTask task) async => task;

  Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object exception) {
        _initialization = null;
        throw exception;
      });
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    wifiOnly = prefs.getBool('downloads_wifi') ?? false;
    concurrency = (prefs.getInt('downloads_concurrency') ?? 2).clamp(1, 4);
    allPaused = prefs.getBool('downloads_all_paused') ?? false;
    _subscription ??= downloader.updates.listen(_update);
    downloader.configureNotificationForGroup(
      group,
      running: const TaskNotification(
        'در حال دانلود · {displayName}',
        '{progress} · {networkSpeed} · {timeRemaining}',
      ),
      complete: const TaskNotification('دانلود تمام شد', '{displayName}'),
      paused: const TaskNotification('دانلود متوقف است', '{displayName}'),
      error: const TaskNotification(
        'دانلود انجام نشد',
        '{displayName} · دوباره تلاش کن',
      ),
      progressBar: true,
      tapOpensFile: true,
    );
    await _configureQueue();
    await downloader.configure(
      globalConfig: [(Config.checkAvailableSpace, 100)],
      androidConfig: [(Config.runInForeground, Config.always)],
    );
    for (final record in await downloader.database.allRecords(group: group)) {
      records[record.taskId] = record;
    }
    await _loadHeld();
    // Drop hold markers for tasks that no longer exist (e.g. DB cleaned
    // externally) so they can never block future deduplication forever.
    heldForPause.retainWhere(records.containsKey);
    await _saveHeld();
    await downloader.start(autoCleanDatabase: false);
    // Apply the stored Wi-Fi policy to already-enqueued tasks as well;
    // on desktop this is a documented no-op (see settings()).
    try {
      await downloader.requireWiFi(
        wifiOnly ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks,
      );
    } catch (_) {}
    if (prefs.getBool('downloads_resume_after_update') == true) {
      await prefs.remove('downloads_resume_after_update');
      await resumeAll();
    }
    notifyListeners();
  }

  void _update(TaskUpdate update) {
    if (update.task.group != group) return;
    final old = records[update.task.taskId];
    if (update is TaskStatusUpdate) {
      records[update.task.taskId] = TaskRecord(
        update.task,
        update.status,
        update.status == TaskStatus.complete ? 1 : old?.progress ?? 0,
        old?.expectedFileSize ?? -1,
        update.exception,
      );
    } else if (update is TaskProgressUpdate) {
      progress[update.task.taskId] = update;
      if (old != null) {
        records[update.task.taskId] = old.copyWith(
          progress: update.progress >= 0 ? update.progress : old.progress,
          expectedFileSize: update.expectedFileSize,
        );
      }
    }
    notifyListeners();
  }

  Future<void> settings({bool? wifi, int? simultaneous}) async {
    await initialize();
    wifiOnly = wifi ?? wifiOnly;
    concurrency = (simultaneous ?? concurrency).clamp(1, 4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('downloads_wifi', wifiOnly);
    await prefs.setInt('downloads_concurrency', concurrency);
    await _configureQueue();
    // Changing the switch must affect existing downloads too, not just
    // future tasks. Native platforms reschedule enqueued/inactive tasks;
    // on desktop (Dart HttpClient) this is a no-op and the option is
    // qualified in the UI.
    try {
      await downloader.requireWiFi(
        wifiOnly ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks,
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<String> rootDirectory() async {
    final root = Platform.isAndroid
        ? await DeviceBridge.downloadsDirectory()
        : (await getDownloadsDirectory())?.path;
    if (root == null) {
      throw const FileSystemException('پوشهٔ Downloads پیدا نشد');
    }
    return p.join(root, 'MBNMovie');
  }

  /// Serializing enqueue avoids double clicks/bulk requests creating duplicate files.
  Future<int> add(
    MovieContent content,
    MovieSeason season,
    List<MovieEpisode> episodes,
  ) {
    final completer = Completer<int>();
    _queueLock = _queueLock.then((_) async {
      try {
        completer.complete(await _add(content, season, episodes));
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  Future<int> _add(
    MovieContent content,
    MovieSeason season,
    List<MovieEpisode> episodes,
  ) async {
    await initialize();
    if (!await DeviceBridge.storageGranted()) {
      throw const FileSystemException(
        'برای ذخیره در Downloads/MBNMovie دسترسی مدیریت فایل را فعال کن.',
      );
    }
    if (Platform.isAndroid) {
      await downloader.permissions.request(PermissionType.notifications);
    }
    final root = await rootDirectory();
    final directory = p.joinAll([
      root,
      ...downloadFolderParts(content, season),
    ]);
    await Directory(directory).create(recursive: true);
    final cover = await _cacheCover(content);
    // شناسهٔ باندل: همهٔ فایل‌های یک افزودنِ یکجا (چند کیفیت فیلم یا
    // چند قسمت یک کیفیت) در مدیریت دانلود یک گروه بازشونده می‌شوند.
    final bundleId = DateTime.now().microsecondsSinceEpoch.toString();
    // Canonical media identity is independent of the synthetic bundle season
    // (movie-all, movie-720p, season-720p, …): the same file reached from an
    // individual button or a bulk button must deduplicate.
    String canonicalSeasonFor(MovieEpisode item) {
      for (final original in content.seasons) {
        if (original.episodes.any(
          (e) => e.id == item.id && e.fileUrl == item.fileUrl,
        )) {
          return original.id;
        }
      }
      var id = season.id;
      // Strip known synthetic suffixes (movie-all, movie-720p, S-all, S-720p).
      id = id.replaceFirst(RegExp(r'-all$'), '');
      id = id.replaceFirst(RegExp(r'-(1080p|720p|480p|4K)$'), '');
      if (id.endsWith('-all')) id = id.substring(0, id.length - 4);
      return id.isEmpty ? season.id : id;
    }

    String originOf(TaskRecord record) {
      if (record.task is! DownloadTask) return '';
      return (record.task as DownloadTask).url;
    }

    final activeUrls = <String>{
      for (final record in records.values)
        if (![
          TaskStatus.failed,
          TaskStatus.notFound,
        ].contains(record.status) ||
            heldForPause.contains(record.task.taskId))
          ...[
            if (record.task is DownloadTask)
              (record.task as DownloadTask).url,
            if (originOf(record).isNotEmpty) originOf(record),
          ],
    };
    var count = 0;
    for (final episode in episodes) {
      final url = Uri.tryParse(episode.fileUrl);
      if (url == null ||
          !['https', 'http'].contains(url.scheme) ||
          url.host.isEmpty) {
        continue;
      }
      // Same bytes from another entry point (individual vs bulk/quality)
      // must not enqueue twice, even though synthetic season ids differ.
      if (activeUrls.contains(episode.fileUrl)) continue;
      final canonicalSeason = canonicalSeasonFor(episode);
      final identity = downloadIdentity(
        content.id,
        canonicalSeason,
        episode.id,
      );
      final duplicate = records.values.any(
        (record) =>
            (record.task.taskId.startsWith('$identity-') ||
                originOf(record) == episode.fileUrl) &&
            (![
                  TaskStatus.failed,
                  TaskStatus.notFound,
                  TaskStatus.canceled,
                ].contains(record.status) ||
                heldForPause.contains(record.task.taskId)),
      );
      if (duplicate) continue;
      // Never overwrite an existing user file, including after history was cleared.
      // A truncated leftover from a failed finalization must not block an
      // ordinary retry: when the size is known and mismatches, allow
      // re-download (the atomic finalizer overwrites only on success).
      var filename = episodeDownloadFilename(episode, identity);
      final destination = File(p.join(directory, filename));
      if (await destination.exists()) {
        var blocksRetry = true;
        try {
          final record = records.values
              .where((r) => r.task is DownloadTask)
              .firstWhere((r) => originOf(r) == episode.fileUrl);
          if (record.expectedFileSize >= 0) {
            blocksRetry =
                await destination.length() == record.expectedFileSize;
          }
        } catch (_) {}
        if (blocksRetry) continue;
      }
      final task = DownloadTask(
        taskId: '$identity-${DateTime.now().microsecondsSinceEpoch}',
        url: url.toString(),
        filename: filename,
        directory: directory,
        baseDirectory: BaseDirectory.root,
        group: group,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 5,
        requiresWiFi: wifiOnly,
        priority: 0,
        displayName: '${content.title} · ${episode.name}',
        metaData: jsonEncode({
          'coverPath': cover,
          'title': content.title,
          'season': season.name,
          'episode': episode.name,
          'contentId': content.id,
          'seasonId': season.id,
          'canonicalSeasonId': canonicalSeason,
          'episodeId': episode.id,
          'groupId': _logicalGroupId(content, episode),
          'bundleId': bundleId,
        }),
      );
      records[task.taskId] = TaskRecord(task, TaskStatus.enqueued, 0, -1);
      if (await downloader.enqueue(task)) {
        activeUrls.add(episode.fileUrl);
        count++;
      } else {
        records[task.taskId] = TaskRecord(task, TaskStatus.failed, 0, -1);
      }
    }
    notifyListeners();
    return count;
  }

  Future<String> _cacheCover(MovieContent content) async {
    if (content.imageUrl == null) return '';
    final support = await getApplicationSupportDirectory();
    final directory = await Directory(
      p.join(support.path, 'download-covers'),
    ).create(recursive: true);
    final file = File(
      p.join(directory.path, '${downloadIdentity(content.id, '', '')}.img'),
    );
    if (await file.exists()) return file.path;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final response = await (await client.getUrl(
        Uri.parse(content.imageUrl!),
      )).close().timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return '';
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 7))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) return '';
      }
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  /// تسک‌های نگه‌داشته‌شده (hold): تسکِ هنوز-شروع‌نشده در همه پلتفرم‌ها
  /// تمیز کنسل می‌شود (صفری بایت دانلود نشده) و id به‌صورت پایدار نگه
  /// داشته می‌شود تا «ادامه» همان‌ها را دوباره در صف بگذارد.
  /// دلیل یکسان‌سازی: در پیاده‌سازی اندرویدی، pauseAll صرفاً id را در
  /// pausedTaskIds می‌گذارد و صف نگه‌دارنده آن را لحاظ نمی‌کند؛ تسک در صف
  /// می‌تواند بعداً اجرا شود. hold صریحِ سطح اپ، رفتار همه پلتفرم‌ها را
  /// یکسان و قابل بازیابی پس از restart می‌کند.
  final Set<String> heldForPause = {};

  Future<bool> pause(Task task) async {
    if (task is! DownloadTask) return false;
    final record = records[task.taskId];
    if (record != null &&
        (record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry)) {
      // تسکِ در صف: pause تکی/سطح کیو قابل اتکا نیست؛ hold تمیز.
      try {
        if (await downloader.cancelTaskWithId(task.taskId)) {
          heldForPause.add(task.taskId);
          await _saveHeld();
          notifyListeners();
          return true;
        }
        return false;
      } catch (_) {
        return false;
      }
    }
    return downloader.pause(task);
  }

  Future<bool> resume(Task task) async {
    if (heldForPause.remove(task.taskId)) {
      // ادامه hold گروهی/تکی از مسیر صف هلدینگ تا سقف هم‌زمانی رعایت شود.
      try {
        final fresh = task is DownloadTask
            ? await _freshDownloadTask(task)
            : task;
        final ok = await downloader.enqueue(fresh);
        await _saveHeld();
        notifyListeners();
        return ok;
      } catch (_) {
        await _saveHeld();
        return false;
      }
    }
    return task is DownloadTask
        ? downloader.resume(task)
        : Future.value(false);
  }

  /// توقف واقعی همهٔ اعضای فعال یک باندل (در حال اجرا + در صف).
  /// فقط همین باندل می‌ایستد؛ سقف هم‌زمانی بقیه دست نخورده می‌ماند.
  Future<bool> pauseBundleTasks(List<TaskRecord> bundleRecords) async {
    await initialize();
    final running = [
      for (final record in bundleRecords)
        if (record.status == TaskStatus.running) record.task,
    ];
    final waiting = [
      for (final record in bundleRecords)
        if (record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry)
          record.task,
    ];
    if (running.isEmpty && waiting.isEmpty) return true;
    var ok = true;
    // ۱) در حال اجراها: pause واقعی (resume-data حفظ می‌شود).
    for (final task in running) {
      try {
        ok =
            await downloader.pause(task as DownloadTask) &&
            ok;
      } catch (_) {
        ok = false;
      }
    }
    // ۲) در صف‌ها: hold تمیز و پایدار در همه پلتفرم‌ها (به توضیح heldForPause).
    if (waiting.isNotEmpty) {
      for (final task in waiting) {
        try {
          if (await downloader.cancelTaskWithId(task.taskId)) {
            heldForPause.add(task.taskId);
          } else {
            ok = false;
          }
        } catch (_) {
          ok = false;
        }
      }
      await _saveHeld();
    }
    notifyListeners();
    return ok;
  }

  /// ادامهٔ همهٔ اعضای متوقف یک باندل.
  /// hold سراسری («توقف همه» پنل) برداشته می‌شود تا ادامه واقعاً اجرا شود،
  /// ولی فقط همین باندل resume می‌شود و ورود دوباره از مسیر صف هلدینگ
  /// است تا سقف دانلود هم‌زمان کاربر رعایت شود.
  Future<bool> resumeBundleTasks(List<TaskRecord> bundleRecords) async {
    await initialize();
    if (allPaused) {
      allPaused = false;
      await (await SharedPreferences.getInstance()).setBool(
        'downloads_all_paused',
        false,
      );
      await _configureQueue();
    }
    final paused = [
      for (final record in bundleRecords)
        if (record.status == TaskStatus.paused) record.task,
    ];
    final held = [
      for (final record in bundleRecords)
        if (heldForPause.contains(record.task.taskId)) record.task,
    ];
    if (paused.isEmpty && held.isEmpty) return true;
    var ok = true;
    if (paused.isNotEmpty) {
      try {
        // API رسمی ادامهٔ گروهی: با فاصلهٔ زمانی، پاک‌سازی hold کیو،
        // و ورود از مسیر صف هلدینگ (رعایت سقف هم‌زمانی).
        final resumed = await downloader.resumeAll(
          tasks: paused.whereType<DownloadTask>().toList(growable: false),
        );
        ok = resumed.length == paused.length && ok;
      } catch (_) {
        ok = false;
      }
    }
    for (final task in held) {
      try {
        heldForPause.remove(task.taskId);
        final fresh = task is DownloadTask
            ? await _freshDownloadTask(task)
            : task;
        ok = await downloader.enqueue(fresh) && ok;
      } catch (_) {
        ok = false;
      }
    }
    await _saveHeld();
    notifyListeners();
    return ok;
  }

  Future<bool> cancel(Task task) async {
    heldForPause.remove(task.taskId);
    await _saveHeld();
    return downloader.cancelTaskWithId(task.taskId);
  }

  Future<bool> retry(Task task) async {
    heldForPause.remove(task.taskId);
    await _saveHeld();
    final path = await task.filePath();
    if (await File(path).exists()) {
      // A size-validated destination blocks retry; a truncated leftover
      // from a failed finalization must remain retryable.
      try {
        final record = records[task.taskId];
        if (record == null ||
            record.expectedFileSize < 0 ||
            await File(path).length() == record.expectedFileSize) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    if (task is DownloadTask) {
      final fresh = await _freshDownloadTask(task);
      return downloader.enqueue(
        fresh.copyWith(retriesRemaining: task.retries),
      );
    }
    return downloader.enqueue(task.copyWith(retriesRemaining: task.retries));
  }

  Future<void> pauseAll() async {
    allPaused = true;
    await (await SharedPreferences.getInstance()).setBool(
      'downloads_all_paused',
      true,
    );
    await _configureQueue();
    for (final record in records.values.toList()) {
      if (record.status == TaskStatus.running) {
        await pause(record.task);
      }
    }
    notifyListeners();
  }

  Future<void> resumeAll() async {
    allPaused = false;
    await (await SharedPreferences.getInstance()).setBool(
      'downloads_all_paused',
      false,
    );
    await _configureQueue();
    for (final record in records.values.toList()) {
      // Global resume must include bundle-held (canceled-but-held) tasks,
      // not just native-paused ones; otherwise held work is stranded.
      if (record.status == TaskStatus.paused ||
          heldForPause.contains(record.task.taskId)) {
        await resume(record.task);
      }
    }
    notifyListeners();
  }

  Future<void> _configureQueue() => downloader
      .configure(
        globalConfig: [
          (
            Config.holdingQueue,
            (allPaused ? 0 : concurrency, concurrency, concurrency),
          ),
        ],
      )
      .then((_) {});

  Future<void> prepareForUpdate() async {
    await initialize();
    if (!allPaused) {
      await (await SharedPreferences.getInstance()).setBool(
        'downloads_resume_after_update',
        true,
      );
      await pauseAll();
    }
    // A pause command is asynchronous on desktop; wait for the persisted status
    // before closing the process, otherwise partial-download metadata is lost.
    for (var attempt = 0; attempt < 80; attempt++) {
      if (!records.values.any((r) => r.status == TaskStatus.running)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const FileSystemException(
      'دانلود هنوز متوقف نشده؛ پس از پایان آن دوباره نصب کن.',
    );
  }

  Future<void> clearFinished() async {
    for (final record in records.values.toList()) {
      // Held tasks look canceled underneath but are user-paused work;
      // clearing them would silently discard paused downloads.
      if (heldForPause.contains(record.task.taskId)) continue;
      if ([TaskStatus.complete, TaskStatus.canceled].contains(record.status)) {
        await downloader.database.deleteRecordWithId(record.taskId);
        records.remove(record.taskId);
        heldForPause.remove(record.taskId);
      }
    }
    await _saveHeld();
    notifyListeners();
  }
}

/// Logical episode-group id for [episode] inside the full [content] catalog.
/// Stored in download metadata so offline playback reads/writes the same
/// canonical progress record as streaming (instead of a raw per-variant id
/// that would fork into the legacy/canonical conflict).
String _logicalGroupId(MovieContent content, MovieEpisode episode) {
  try {
    final catalog = EpisodeCatalog.from(content);
    return catalog.groupFor(episode)?.id ?? episode.id;
  } catch (_) {
    return episode.id;
  }
}

String downloadStatusLabel(TaskStatus status) => switch (status) {
  TaskStatus.enqueued => 'در صف',
  TaskStatus.running => 'در حال دانلود',
  TaskStatus.complete => 'تکمیل‌شده',
  TaskStatus.notFound => 'فایل در سرور پیدا نشد',
  TaskStatus.failed => 'ناموفق',
  TaskStatus.canceled => 'لغوشده',
  TaskStatus.waitingToRetry => 'در انتظار تلاش مجدد',
  TaskStatus.paused => 'متوقف',
};
