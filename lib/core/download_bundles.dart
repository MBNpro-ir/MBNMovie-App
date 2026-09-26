import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

/// گروه‌بندی هوشمند فهرست دانلودها: چند کیفیت یک فیلم یا چند قسمت
/// یک کیفیت که باهم در صف رفته‌اند، یک «باندل» بازشونده دیده می‌شوند
/// تا تکی‌تکی شلوغ نکنند. تک‌فایل‌ها باندل تک‌عضوی‌اند.

/// کلید پایدار باندل یک رکورد: همان دسته‌ای که موقع افزودن باهم صف شد.
/// رکوردهای قدیمی (بدون bundleId) هر کدام باندل جداگانه‌اند تا قاطی نشوند.
String downloadBundleId(TaskRecord record) {
  try {
    final meta = jsonDecode(record.task.metaData) as Map;
    final bundle = (meta['bundleId'] as String?)?.trim() ?? '';
    if (bundle.isNotEmpty) return 'bundle-$bundle';
  } catch (_) {
    // بدون متادیتا: تک‌باندل.
  }
  return 'task-${record.task.taskId}';
}

String _metaString(Task task, String key) {
  try {
    return ((jsonDecode(task.metaData) as Map)[key] as String?)?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

class DownloadBundle {
  const DownloadBundle({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.records,
  });

  final String id;
  final String title;
  final String subtitle;
  final String coverPath;
  final List<TaskRecord> records;

  bool get isSingle => records.length == 1;

  int get completeCount => records
      .where((record) => record.status == TaskStatus.complete)
      .length;

  double get progress {
    if (records.isEmpty) return 0;
    var sum = 0.0;
    for (final record in records) {
      sum += record.progress.clamp(0, 1);
    }
    return (sum / records.length).clamp(0, 1);
  }

  int get totalBytes {
    var sum = 0;
    for (final record in records) {
      if (record.expectedFileSize > 0) sum += record.expectedFileSize;
    }
    return sum;
  }

  bool get hasRunning => records.any(
    (record) =>
        record.status == TaskStatus.running ||
        record.status == TaskStatus.enqueued ||
        record.status == TaskStatus.waitingToRetry,
  );

  bool get hasPaused => records.any(
    (record) => record.status == TaskStatus.paused,
  );

  bool get hasRetryable => records.any(
    (record) =>
        record.status == TaskStatus.failed ||
        record.status == TaskStatus.notFound ||
        record.status == TaskStatus.canceled,
  );

  bool get hasActive => records.any(
    (record) =>
        record.status != TaskStatus.complete &&
        record.status != TaskStatus.failed &&
        record.status != TaskStatus.notFound &&
        record.status != TaskStatus.canceled,
  );
}

/// دکمهٔ «ادامه همه» باندل معنادار است وقتی عضوی paused یا holdشده
/// (توقف گروهی دسکتاپ) داشته باشد — نه وقتی همه در حال اجراند.
bool bundleCanResume(DownloadBundle bundle, [Set<String> heldIds = const {}]) =>
    bundle.hasPaused ||
    bundle.records.any((record) => heldIds.contains(record.task.taskId));

/// دکمهٔ «توقف همه» باندل معنادار است وقتی عضوی فعال
/// (در حال اجرا / در صف / در انتظار تلاش مجدد) داشته باشد.
bool bundleCanPause(DownloadBundle bundle) => bundle.hasRunning;

/// رکوردها را به باندل تبدیل می‌کند؛ مرتب‌سازی جدیدترین اول حفظ می‌شود.
List<DownloadBundle> groupDownloadRecords(Iterable<TaskRecord> input) {
  final order = <String>[];
  final groups = <String, List<TaskRecord>>{};
  for (final record in input) {
    final id = downloadBundleId(record);
    if (!groups.containsKey(id)) {
      groups[id] = [];
      order.add(id);
    }
    groups[id]!.add(record);
  }
  return [
    for (final id in order)
      _bundleOf(id, groups[id]!),
  ];
}

DownloadBundle _bundleOf(String id, List<TaskRecord> records) {
  if (records.length == 1) {
    final task = records.single.task;
    return DownloadBundle(
      id: id,
      title: task.displayName,
      subtitle: _metaString(task, 'season'),
      coverPath: _metaString(task, 'coverPath'),
      records: records,
    );
  }
  final first = records.first.task;
  final title = _metaString(first, 'title');
  final season = _metaString(first, 'season');
  return DownloadBundle(
    id: id,
    title: title.isEmpty ? first.displayName : title,
    subtitle: season.isEmpty
        ? '${records.length} فایل'
        : '$season · ${records.length} فایل',
    coverPath: _metaString(first, 'coverPath'),
    records: records,
  );
}
