import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../core/app_platform.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import '../core/download_bundles.dart';
import '../core/watch_progress.dart';
import '../core/search_direction.dart';
import '../services/download_manager.dart';
import '../services/device_bridge.dart';
import '../services/external_apps.dart';
import '../models/movie_content.dart';
import '../widgets/download_playback_sheet.dart';
import 'detail_screen.dart';

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key, this.initializeDownloads});
  final Future<void> Function()? initializeDownloads;
  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  final manager = DownloadManager.instance;
  String _search = '';
  String _filter = 'همه';
  final _expandedBundles = <String>{};
  @override
  void initState() {
    super.initState();
    unawaited(
      _action(() async {
        await (widget.initializeDownloads?.call() ?? manager.initialize());
        return true;
      }),
    );
  }

  Future<void> _play(Task task) async {
    final path = await task.filePath();
    if (!mounted) return;
    if (!await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فایل پیدا نشد؛ ممکن است جابه‌جا یا حذف شده باشد.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDownloadPlaybackSheet(context);
    if (choice == null || !mounted) return;
    if (choice == 'internal') {
      Map<String, dynamic> metadata = {};
      try {
        metadata = Map<String, dynamic>.from(jsonDecode(task.metaData) as Map);
      } catch (_) {}
      // Resume offline playback from the canonical streaming progress record
      // (stored as groupId at enqueue time); fall back to the raw episode id
      // for downloads created before that metadata existed.
      final contentId =
          metadata['contentId'] as String? ?? 'download-${task.taskId}';
      final episodeId = metadata['episodeId'] as String? ?? task.taskId;
      final groupId =
          (metadata['groupId'] as String?)?.trim().isNotEmpty == true
          ? (metadata['groupId'] as String)
          : episodeId;
      Duration startAt = Duration.zero;
      try {
        final saved = await WatchProgressStore().load(
          contentId: contentId,
          episodeId: groupId,
        );
        if (saved != null && saved.isResumable) startAt = saved.position;
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            content: MovieContent(
              id: contentId,
              title: metadata['title'] as String? ?? task.displayName,
              subtitle: '',
              description: '',
              year: 0,
              rating: 0,
              kind: ContentKind.movie,
              colors: const [],
              genres: const [],
            ),
            episode: MovieEpisode(
              id: episodeId,
              name: metadata['episode'] as String? ?? task.displayName,
              fileUrl: Uri.file(path).toString(),
            ),
            initialPosition: startAt,
            progressEpisodeId: groupId,
          ),
        ),
      );
    } else {
      final player = ExternalVideoPlayer.values.byName(choice);
      final result = await ExternalApps.playLocalVideo(
        player: player,
        path: path,
        title: task.displayName,
      );
      if (!mounted || result == ExternalLaunchResult.launched) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == ExternalLaunchResult.missing
                ? '${ExternalApps.playerName(player)} نصب نیست؛ پلیر داخلی را انتخاب کن یا آن را نصب کن.'
                : 'فایل در پلیر خارجی باز نشد؛ پلیر داخلی را امتحان کن.',
          ),
        ),
      );
    }
  }

  Future<void> _action(Future<bool> Function() operation) async {
    try {
      final success = await operation();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'این عملیات انجام نشد؛ ممکن است سرور ادامهٔ دانلود را پشتیبانی نکند. دوباره تلاش کن.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'عملیات دانلود انجام نشد؛ دسترسی، اینترنت و فضای خالی را بررسی کن.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => kIsWeb
    ? Scaffold(appBar: AppBar(title: const Text('دانلودهای مرورگر')), body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('فایل‌های دانلودشده را در Downloads مرورگر یا برنامه Files آیفون ببین. دانلود هر قسمت از صفحه جزئیات در دسترس است.', textAlign: TextAlign.center))))
    : Scaffold(
    appBar: AppBar(
      title: const Text('مدیریت دانلود ها'),
      actions: [
        IconButton(
          tooltip: 'باز کردن پوشهٔ دانلود',
          icon: const Icon(Icons.folder_open),
          onPressed: () => _action(() async {
            await DeviceBridge.openFolder(await manager.rootDirectory());
            return true;
          }),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final records =
            manager.records.values
                .where(
                  (r) =>
                      r.task.displayName.toLowerCase().contains(
                        _search.toLowerCase(),
                      ) &&
                      (_filter == 'همه' ||
                          _filter ==
                              downloadStatusLabel(manager.effectiveStatus(r))),
                )
                .toList()
              ..sort(
                (a, b) => b.task.creationTime.compareTo(a.task.creationTime),
              );
        final allRecords = manager.records.values.toList(growable: false);
        final bundles = groupDownloadRecords(records);
        final fileCount = bundles.fold<int>(
          0,
          (sum, bundle) => sum + bundle.records.length,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1000;
            final horizontal = desktop ? 28.0 : 12.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        16,
                        horizontal,
                        10,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _overview(allRecords, desktop),
                            const SizedBox(height: 12),
                            _controlPanel(desktop),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'فهرست دانلودها',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                                Text(
                                  '${bundles.length} باندل · $fileCount فایل',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (records.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyDownloads(),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          0,
                          horizontal,
                          24,
                        ),
                        sliver: SliverList.builder(
                          itemCount: bundles.length,
                          itemBuilder: (context, index) {
                            final bundle = bundles[index];
                            if (bundle.isSingle) {
                              return _downloadCard(
                                bundle.records.single,
                                desktop: desktop,
                              );
                            }
                            return _bundleCard(bundle, desktop: desktop);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Widget _overview(List<TaskRecord> records, bool desktop) {
    int count(Iterable<TaskStatus> statuses) =>
        records.where((record) => statuses.contains(record.status)).length;
    final cards = [
      _SummaryData('همه دانلودها', records.length, Icons.download_rounded),
      _SummaryData(
        'در حال دریافت',
        count(const [TaskStatus.running]),
        Icons.downloading_rounded,
      ),
      _SummaryData(
        'در انتظار',
        count(const [TaskStatus.enqueued, TaskStatus.paused]),
        Icons.schedule_rounded,
      ),
      _SummaryData(
        'تکمیل‌شده',
        count(const [TaskStatus.complete]),
        Icons.task_alt_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = desktop
            ? 205.0
            : constraints.maxWidth < 420
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in cards)
              SizedBox(
                width: width,
                child: _SummaryCard(data: item),
              ),
          ],
        );
      },
    );
  }

  Widget _controlPanel(bool desktop) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: EdgeInsets.all(desktop ? 18 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (desktop)
            Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 12),
                SizedBox(width: 190, child: _filterField()),
              ],
            )
          else ...[
            _searchField(),
            const SizedBox(height: 10),
            _filterField(),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _action(() async {
                  await manager.resumeAll();
                  return true;
                }),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('ادامه همه'),
              ),
              OutlinedButton.icon(
                onPressed: () => _action(() async {
                  await manager.pauseAll();
                  return true;
                }),
                icon: const Icon(Icons.pause_rounded),
                label: const Text('توقف همه'),
              ),
              OutlinedButton.icon(
                onPressed: () => _action(() async {
                  await manager.clearFinished();
                  return true;
                }),
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('پاک‌کردن تکمیل‌شده‌ها'),
              ),
              FilterChip(
                avatar: const Icon(Icons.wifi_rounded, size: 18),
                label: Text(
                  Platform.isWindows || Platform.isLinux || Platform.isMacOS
                      ? 'فقط Wi-Fi (موبایل)'
                      : 'فقط Wi-Fi',
                ),
                tooltip:
                    Platform.isWindows || Platform.isLinux || Platform.isMacOS
                    ? 'روی دسکتاپ، دانلودر Dart محدودیت شبکه اعمال نمی‌کند؛ این گزینه فقط روی موبایل اثر دارد.'
                    : null,
                selected: manager.wifiOnly,
                onSelected: (value) => _action(() async {
                  await manager.settings(wifi: value);
                  return true;
                }),
              ),
              SizedBox(
                width: 190,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: manager.concurrency,
                        hint: const Text('هم‌زمان'),
                        items: [
                          for (var i = 1; i <= 4; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text('$i دانلود هم‌زمان'),
                            ),
                        ],
                        onChanged: (value) => _action(() async {
                          await manager.settings(simultaneous: value);
                          return true;
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'مسیر ذخیره: Downloads/MBNMovie/Movies یا Series  •  پاک‌کردن سابقه، فایل را حذف نمی‌کند.',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      ),
    ),
  );

  Widget _searchField() => TextField(
    textDirection: searchTextDirection(_search),
    decoration: const InputDecoration(
      labelText: 'جست‌وجو در دانلودها',
      prefixIcon: Icon(Icons.search_rounded),
    ),
    onChanged: (value) => setState(() => _search = value),
  );

  Widget _filterField() => DropdownButtonFormField<String>(
    initialValue: _filter,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'وضعیت',
      prefixIcon: Icon(Icons.filter_list_rounded),
    ),
    items: [
      for (final value in const [
        'همه',
        'در صف',
        'در حال دانلود',
        'متوقف',
        'تکمیل‌شده',
        'ناموفق',
        'لغوشده',
      ])
        DropdownMenuItem(value: value, child: Text(value)),
    ],
    onChanged: (value) => setState(() => _filter = value ?? 'همه'),
  );

  Widget _downloadCard(TaskRecord record, {required bool desktop}) {
    final task = record.task;
    final live = manager.progress[task.taskId];
    final cover = _coverPath(task);
    final details = _downloadDetails(record, live);
    final actions = _downloadActions(record);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(desktop ? 16 : 12),
        child: desktop
            ? Row(
                children: [
                  _cover(cover, 58, 82),
                  const SizedBox(width: 14),
                  Expanded(child: details),
                  const SizedBox(width: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 270),
                    child: actions,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cover(cover, 46, 64),
                      const SizedBox(width: 10),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 10),
                  actions,
                ],
              ),
      ),
    );
  }

  /// کارت باندل: چند فایل هم‌خانواده (چند کیفیت فیلم / چند قسمت
  /// یک کیفیت) یکجا با پیشرفت تجمیعی؛ بازشونده و قابل مدیریت گروهی.
  Widget _bundleCard(DownloadBundle bundle, {required bool desktop}) {
    final percent = (bundle.progress.clamp(0, 1) * 100).round();
    return Card(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('bundle-${bundle.id}'),
        initiallyExpanded: _expandedBundles.contains(bundle.id),
        onExpansionChanged: (expanded) => setState(() {
          if (expanded) {
            _expandedBundles.add(bundle.id);
          } else {
            _expandedBundles.remove(bundle.id);
          }
        }),
        leading: _cover(bundle.coverPath, 46, 64),
        title: Text(
          bundle.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bundle.subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                bundle.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: bundle.progress.clamp(0, 1),
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 3,
              children: [
                Text(
                  '${bundle.completeCount} از ${bundle.records.length} تکمیل‌شده · $percent٪',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (bundle.totalBytes > 0)
                  Text(
                    '${(bundle.totalBytes / 1048576).toStringAsFixed(1)} MB',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 16 : 12,
              0,
              desktop ? 16 : 12,
              4,
            ),
            child: _bundleActions(bundle),
          ),
          const Divider(height: 1),
          for (final record in bundle.records) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                desktop ? 16 : 12,
                10,
                desktop ? 16 : 12,
                10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _downloadDetails(
                    record,
                    manager.progress[record.task.taskId],
                  ),
                  const SizedBox(height: 8),
                  _downloadActions(record),
                ],
              ),
            ),
            const Divider(height: 1, indent: 12, endIndent: 12),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _bundleActions(DownloadBundle bundle) => Wrap(
    spacing: 6,
    runSpacing: 6,
    alignment: WrapAlignment.end,
    children: [
      if (bundleCanResume(bundle, manager.heldForPause))
        FilledButton.tonalIcon(
          onPressed: () =>
              _action(() => manager.resumeBundleTasks(bundle.records)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ادامه همه'),
        ),
      if (bundleCanPause(bundle))
        OutlinedButton.icon(
          onPressed: () =>
              _action(() => manager.pauseBundleTasks(bundle.records)),
          icon: const Icon(Icons.pause_rounded),
          label: const Text('توقف همه'),
        ),
      if (bundle.hasRetryable)
        FilledButton.tonalIcon(
          onPressed: () => _action(() async {
            var ok = true;
            for (final record in bundle.records) {
              if (record.status == TaskStatus.failed ||
                  record.status == TaskStatus.notFound ||
                  record.status == TaskStatus.canceled) {
                try {
                  ok = await manager.retry(record.task) && ok;
                } catch (_) {
                  ok = false;
                }
              }
            }
            return ok;
          }),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('تلاش مجدد همه'),
        ),
      if (bundle.hasActive)
        IconButton.outlined(
          tooltip: 'لغو همهٔ باندل',
          onPressed: () => _action(() async {
            var ok = true;
            for (final record in bundle.records) {
              if (record.status != TaskStatus.complete &&
                  record.status != TaskStatus.failed &&
                  record.status != TaskStatus.notFound &&
                  record.status != TaskStatus.canceled) {
                try {
                  ok = await manager.cancel(record.task) && ok;
                } catch (_) {
                  ok = false;
                }
              }
            }
            return ok;
          }),
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );

  Widget _downloadDetails(TaskRecord record, TaskProgressUpdate? live) {
    final percent = (record.progress.clamp(0, 1) * 100).round();
    // holdِ توقف گروهی (دسکتاپ) وضعیت پایه‌اش «لغوشده» است ولی از دید
    // کاربر متوقف است و با «ادامه» برمی‌گردد.
    final held = manager.heldForPause.contains(record.task.taskId);
    final statusLabel = held ? 'متوقف' : downloadStatusLabel(record.status);
    final statusColor = held
        ? _statusColor(TaskStatus.paused)
        : _statusColor(record.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          record.task.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        LinearProgressIndicator(
          value: record.progress.clamp(0, 1),
          minHeight: 7,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 3,
          children: [
            Text(
              '$statusLabel  •  $percent٪',
              style: TextStyle(color: statusColor),
            ),
            if (record.expectedFileSize > 0)
              Text(
                '${(record.expectedFileSize / 1048576).toStringAsFixed(1)} MB',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white60),
              ),
            if (record.status == TaskStatus.running && live != null) ...[
              if (live.networkSpeedAsString.isNotEmpty)
                Text(
                  live.networkSpeedAsString,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.white60),
                ),
              if (live.timeRemainingAsString.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      live.timeRemainingAsString,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'مانده',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
            ],
          ],
        ),
        if (record.exception != null) ...[
          const SizedBox(height: 5),
          const Text(
            'دانلود متوقف شد؛ اتصال، اعتبار لینک و فضای ذخیره‌سازی را بررسی کن.',
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _downloadActions(TaskRecord record) {
    final task = record.task;
    final held = manager.heldForPause.contains(task.taskId);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        if (held)
          FilledButton.tonalIcon(
            onPressed: () => _action(() => manager.resume(task)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('ادامه'),
          ),
        if (record.status == TaskStatus.running && !held)
          FilledButton.tonalIcon(
            onPressed: () => _action(() => manager.pause(task)),
            icon: const Icon(Icons.pause_rounded),
            label: const Text('توقف'),
          ),
        if (record.status == TaskStatus.paused)
          FilledButton.tonalIcon(
            onPressed: () => _action(() => manager.resume(task)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('ادامه'),
          ),
        if (!held &&
            const [
              TaskStatus.failed,
              TaskStatus.notFound,
              TaskStatus.canceled,
            ].contains(record.status))
          FilledButton.tonalIcon(
            onPressed: () => _action(() => manager.retry(task)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تلاش مجدد'),
          ),
        if (!const [
          TaskStatus.complete,
          TaskStatus.failed,
          TaskStatus.notFound,
          TaskStatus.canceled,
        ].contains(record.status))
          IconButton.outlined(
            tooltip: 'لغو دانلود',
            onPressed: () => _action(() => manager.cancel(task)),
            icon: const Icon(Icons.close_rounded),
          ),
        if (record.status == TaskStatus.complete)
          FilledButton.icon(
            onPressed: () => _action(() async {
              await _play(task);
              return true;
            }),
            icon: const Icon(Icons.play_circle_rounded),
            label: const Text('پخش'),
          ),
      ],
    );
  }

  String _coverPath(Task task) {
    try {
      return (jsonDecode(task.metaData) as Map)['coverPath'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Widget _cover(String path, double width, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: path.isEmpty
          ? const Icon(Icons.movie_outlined, color: Colors.white38)
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.movie_outlined, color: Colors.white38),
            ),
    ),
  );

  Color _statusColor(TaskStatus status) => switch (status) {
    TaskStatus.complete => Colors.greenAccent,
    TaskStatus.failed || TaskStatus.notFound => Colors.redAccent,
    TaskStatus.running => Colors.orangeAccent,
    _ => Colors.white70,
  };
}

class _SummaryData {
  const _SummaryData(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});
  final _SummaryData data;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.deepOrange.withValues(alpha: .16),
          foregroundColor: Colors.orangeAccent,
          child: Icon(data.icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.value}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.download_done_rounded,
            size: 58,
            color: Colors.white38,
          ),
          const SizedBox(height: 12),
          Text(
            'هنوز دانلودی نداری',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'از صفحهٔ قسمت‌ها، دانلود داخلی را انتخاب کن.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    ),
  );
}
