import '../core/title_language.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/platform_ui.dart';
import '../core/playlist_store.dart';
import '../core/theme.dart';
import '../models/movie_content.dart';
import '../services/mbn_sync.dart';
import '../widgets/ambient_background.dart';
import '../widgets/content_art.dart';
import '../widgets/pressable.dart';

/// Callback used to open a title from a playlist grid.
typedef PlaylistOpenContent =
    Future<void> Function(MovieContent item, String tag);

/// Shows the add-to-playlist sheet for [item].
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  MovieContent item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MovieColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _AddToPlaylistSheet(item: item),
    ),
  );
}

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key, required this.onOpen});
  final PlaylistOpenContent onOpen;
  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  final _store = PlaylistStore();
  late Future<List<MoviePlaylist>> _future = _store.playlists();

  @override
  void initState() {
    super.initState();
    MbnSync.instance.changes.addListener(_onSync);
  }

  @override
  void dispose() {
    MbnSync.instance.changes.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (mounted && MbnSync.instance.changedCategories.contains('playlists')) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final next = _store.playlists();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _create() async {
    final name = await _askName(context, title: 'پلی‌لیست جدید');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _store.create(name);
      unawaited(MbnSync.instance.pushPlaylists());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ساخت پلی‌لیست انجام نشد.')),
        );
      }
      return;
    }
    await _reload();
  }

  Future<void> _rename(MoviePlaylist list) async {
    final name = await _askName(
      context,
      title: 'تغییر نام پلی‌لیست',
      initial: list.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await _store.rename(list.id, name);
    unawaited(MbnSync.instance.pushPlaylists());
    await _reload();
  }

  Future<void> _delete(MoviePlaylist list) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف پلی‌لیست؟'),
        content: Text(
          '«${list.name}» با ${list.items.length} عنوان حذف می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _store.delete(list.id);
    unawaited(MbnSync.instance.pushPlaylists());
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('پلی‌لیست‌ها')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add_rounded),
      label: const Text('پلی‌لیست جدید'),
    ),
    body: AmbientBackground(
      child: FutureBuilder<List<MoviePlaylist>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('دریافت پلی‌لیست‌ها انجام نشد.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('تلاش دوباره'),
                  ),
                ],
              ),
            );
          }
          final lists = snapshot.data ?? const <MoviePlaylist>[];
          if (lists.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.queue_music_rounded,
                    size: 64,
                    color: MovieColors.muted,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'هنوز پلی‌لیستی نساخته‌ای',
                    style: TextStyle(color: MovieColors.muted),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'هر فیلم یا سریال را به پلی‌لیست دلخواهت اضافه کن.',
                    style: TextStyle(color: MovieColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('ساخت پلی‌لیست'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: lists.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final list = lists[index];
                return Card(
                  color: MovieColors.surfaceHigh,
                  child: ListTile(
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: MovieColors.orange.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: MovieColors.orange,
                      ),
                    ),
                    title: Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${list.items.length} عنوان'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'تغییر نام',
                          onPressed: () => _rename(list),
                          icon: const Icon(Icons.edit_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          onPressed: () => _delete(list),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.push<void>(
                      context,
                      slideUpRoute(
                        PlaylistDetailPage(
                          playlistId: list.id,
                          onOpen: widget.onOpen,
                        ),
                      ),
                    ).then((_) => _reload()),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.onOpen,
  });
  final String playlistId;
  final PlaylistOpenContent onOpen;
  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final _store = PlaylistStore();
  MoviePlaylist? _list;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lists = await _store.playlists();
      if (!mounted) return;
      final found = lists.where((list) => list.id == widget.playlistId);
      setState(() {
        _list = found.isEmpty ? null : found.first;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'دریافت پلی‌لیست انجام نشد.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _remove(MovieContent item) async {
    await _store.removeTitle(widget.playlistId, item.id);
    unawaited(MbnSync.instance.pushPlaylists());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: Text(list?.name ?? 'پلی‌لیست')),
      body: AmbientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('تلاش دوباره'),
                    ),
                  ],
                ),
              )
            : list == null
            ? const Center(child: Text('این پلی‌لیست حذف شده است.'))
            : list.items.isEmpty
            ? const Center(
                child: Text(
                  'هنوز عنوانی به این پلی‌لیست اضافه نشده است.',
                  style: TextStyle(color: MovieColors.muted),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: .57,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: list.items.length,
                itemBuilder: (context, index) {
                  final item = list.items[index];
                  final tag = 'playlist-${list.id}-${item.id}';
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Pressable(
                          onTap: () => widget.onOpen(item, tag),
                          child: Hero(
                            tag: tag,
                            transitionOnUserGestures: true,
                            createRectTween: smoothHeroRectTween,
                            flightShuttleBuilder: portraitHeroFlightShuttle,
                            child: ContentArt(content: item),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: IconButton.filledTonal(
                          tooltip: 'حذف از پلی‌لیست',
                          onPressed: () => _remove(item),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({required this.item});
  final MovieContent item;
  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  final _store = PlaylistStore();
  final _controller = TextEditingController();
  List<MoviePlaylist> _lists = const [];
  Set<String> _containing = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lists = await _store.playlists();
    final containing = await _store.listIdsContaining(widget.item.id);
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _containing = containing;
      _loading = false;
    });
  }

  Future<void> _toggle(MoviePlaylist list) async {
    if (_containing.contains(list.id)) {
      await _store.removeTitle(list.id, widget.item.id);
    } else {
      await _store.addTitle(list.id, widget.item);
    }
    unawaited(MbnSync.instance.pushPlaylists());
    await _load();
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    try {
      final created = await _store.create(name);
      await _store.addTitle(created.id, widget.item);
    } catch (_) {
      return;
    }
    _controller.clear();
    unawaited(MbnSync.instance.pushPlaylists());
    await _load();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'افزودن به پلی‌لیست',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            TitleLanguage.title(widget.item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: MovieColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'نام پلی‌لیست جدید…',
                  ),
                  onSubmitted: (_) => _create(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('ساخت'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lists.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'هنوز پلی‌لیستی نداری؛ از بالا بساز.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MovieColors.muted),
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _lists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final list = _lists[index];
                        final selected = _containing.contains(list.id);
                        return Card(
                          color: selected
                              ? MovieColors.orange.withValues(alpha: .14)
                              : MovieColors.surfaceHigh,
                          child: ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.queue_music_rounded,
                              color: selected
                                  ? MovieColors.orange
                                  : MovieColors.muted,
                            ),
                            title: Text(list.name),
                            subtitle: Text('${list.items.length} عنوان'),
                            onTap: () => _toggle(list),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'نام پلی‌لیست…'),
        onSubmitted: (_) =>
            Navigator.pop(dialogContext, controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('تأیید'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.trim().isEmpty) return null;
  return result.trim();
}
