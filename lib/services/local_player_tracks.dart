import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/app_platform.dart';
import '../core/external_media_tracks.dart';
import '../core/native_player_properties.dart';

/// One instance per player. All import/relink operations are serialized and
/// checked after awaits so an old episode cannot attach files to a new one.
class LocalPlayerTracks {
  LocalPlayerTracks({
    required this.player,
    required this.context,
    required this.alive,
    required this.onSubtitleChanged,
  });
  final Player player;
  final BuildContext Function() context;
  final bool Function() alive;
  final Future<void> Function(SubtitleTrack) onSubtitleChanged;
  ExternalMediaTrackStore? _store;
  ExternalTrackSnapshot _snapshot = const ExternalTrackSnapshot();
  final Map<String, String> _nativeIds = {};
  Future<void> _queue = Future.value();
  int _generation = 0;
  bool _closed = false;
  final Set<DialogRoute<dynamic>> _dialogs = {};

  Future<T?> _dialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    final ctx = context();
    final route = DialogRoute<T>(
      context: ctx,
      builder: builder,
      barrierDismissible: barrierDismissible,
    );
    _dialogs.add(route);
    return Navigator.of(
      ctx,
      rootNavigator: true,
    ).push<T>(route).whenComplete(() => _dialogs.remove(route));
  }

  void _dismissDialogs() {
    final routes = _dialogs.toList();
    _dialogs.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  bool valid(int generation) =>
      !_closed && alive() && generation == _generation;
  void invalidate() {
    _generation++;
    _store = null;
    _nativeIds.clear();
    _dismissDialogs();
  }

  void close() {
    _closed = true;
    _generation++;
    _dismissDialogs();
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.catchError((Object _) {}).then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> restore({
    required String owner,
    required String contentId,
    required String episodeId,
    required bool Function() current,
  }) {
    final generation = ++_generation;
    return _serial(() async {
      if (!valid(generation) || !current()) return;
      _nativeIds.clear();
      _store = ExternalMediaTrackStore(
        owner: owner,
        contentId: contentId,
        episodeId: episodeId,
      );
      _snapshot = await _store!.load();
      if (!valid(generation) || !current()) return;
      for (final old in _snapshot.tracks.toList(growable: false)) {
        if (!valid(generation) || !current()) return;
        var track = old;
        if (!await _exists(track.path)) {
          if (!valid(generation) || !current()) return;
          final playing = player.state.playing;
          if (playing) await player.pause();
          final replacement = await _relink(track, generation);
          if (!valid(generation) || !current()) return;
          final selected = _snapshot.selected(track.kind) == track.id;
          _snapshot = _snapshot.remove(track.id);
          if (replacement != null) {
            track = ExternalMediaTrack.file(replacement, track.kind);
            _snapshot = _snapshot.add(track, activate: selected);
          }
          await _store!.save(_snapshot);
          if (playing && valid(generation) && current()) await player.play();
          if (replacement == null) continue;
        }
        if (!valid(generation) || !current()) return;
        try {
          await _attach(
            track,
            select: _snapshot.selected(track.kind) == track.id,
            generation: generation,
          );
        } catch (_) {
          if (!valid(generation) || !current()) return;
          _snapshot = _snapshot.remove(track.id);
          await _store!.save(_snapshot);
          _notice('فایل «${track.name}» قابل پخش نبود؛ انتخاب پیش‌فرض حفظ شد.');
        }
      }
    });
  }

  Future<bool> _exists(String path) async {
    try {
      return await File(path).exists().timeout(const Duration(seconds: 3));
    } catch (_) {
      return false;
    }
  }

  Future<String?> _relink(ExternalMediaTrack track, int generation) async {
    while (valid(generation)) {
      final result = await _dialog<bool>(
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            track.kind == ExternalTrackKind.audio
                ? 'فایل صوتی پیدا نشد'
                : 'فایل زیرنویس پیدا نشد',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'این فایل در سیستم پیدا نمی‌شود. محل جدید آن را انتخاب کن یا اطلاعات قبلی را پاک کن و با انتخاب پیش‌فرض ادامه بده.',
                ),
                const SizedBox(height: 12),
                SelectableText(track.name, textDirection: TextDirection.ltr),
                const SizedBox(height: 6),
                SelectableText(
                  track.path,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ادامه با پیش‌فرض'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('پیداکردن فایل'),
            ),
          ],
        ),
      );
      if (result != true || !valid(generation)) return null;
      final file = await openFile();
      if (!valid(generation)) return null;
      if (file != null && await _exists(file.path)) return file.path;
      // Canceling the picker returns to the explanation; it does not silently
      // discard the saved selection.
    }
    return null;
  }

  Future<void> importFiles(List<String> paths, {ExternalTrackKind? kind}) {
    final generation = _generation;
    return _serial(() async {
      if (!valid(generation) || _store == null) return;
      for (var path in paths.take(32)) {
        if (!valid(generation)) return;
        final uri = Uri.tryParse(path);
        if (uri?.scheme == 'file') path = uri!.toFilePath(windows: true);
        if (!await _exists(path)) {
          if (valid(generation)) {
            _notice('فایل رهاشده در دسترس نیست یا پوشه است.');
          }
          continue;
        }
        var selectedKind = kind ?? externalTrackKind(path);
        if (selectedKind == null) {
          if (!valid(generation)) return;
          selectedKind = await _dialog<ExternalTrackKind>(
            builder: (ctx) => SimpleDialog(
              title: const Text('این فایل را چگونه باز کنیم؟'),
              children: [
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.pop(ctx, ExternalTrackKind.subtitle),
                  child: const Text('به‌عنوان زیرنویس'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ExternalTrackKind.audio),
                  child: const Text('به‌عنوان صدای خارجی'),
                ),
              ],
            ),
          );
        }
        if (selectedKind == null || !valid(generation)) continue;
        final track = ExternalMediaTrack.file(path, selectedKind);
        try {
          await _attach(track, select: true, generation: generation);
          if (!valid(generation)) return;
          _snapshot = _snapshot.add(track);
          await _store!.save(_snapshot);
          if (valid(generation)) {
            _notice(
              '${selectedKind == ExternalTrackKind.audio ? 'صدا' : 'زیرنویس'} «${track.name}» فعال و برای این ویدیو ذخیره شد.',
            );
          }
        } catch (_) {
          if (valid(generation)) {
            _notice(
              'این فایل قابل استفاده نیست؛ قالب فایل یا دسترسی آن را بررسی کن.',
            );
          }
        }
      }
    });
  }

  Future<void> _attach(
    ExternalMediaTrack track, {
    required bool select,
    required int generation,
  }) async {
    if (!valid(generation)) return;
    await addNativeExternalTrack(
      player.platform!,
      path: track.path,
      title: track.name,
      subtitle: track.kind == ExternalTrackKind.subtitle,
      select: select,
    );
    if (!valid(generation)) return;
    final raw = await getNativePlayerProperty(player.platform!, 'track-list');
    if (!valid(generation)) return;
    final entries = jsonDecode(raw ?? '[]');
    final list = entries is List ? entries : const [];
    String normalize(Object? value) {
      var result = '$value';
      if (result.startsWith('file:')) {
        result = Uri.parse(result).toFilePath(windows: true);
      }
      return result.replaceAll('\\', '/').toLowerCase();
    }

    final found = list
        .whereType<Map>()
        .where(
          (r) =>
              r['type'] ==
                  (track.kind == ExternalTrackKind.audio ? 'audio' : 'sub') &&
              normalize(r['external-filename']) == normalize(track.path),
        )
        .toList();
    if (found.isEmpty) {
      throw const FormatException('unsupported external track');
    }
    final row = found.last;
    _nativeIds[track.id] = '${row['id']}';
    if (select) {
      // mpv's add command selects the stream, but media_kit's selected Track
      // state is updated through its public setters. Keep the picker in sync.
      if (track.kind == ExternalTrackKind.subtitle) {
        final selected = SubtitleTrack(
          '${row['id']}',
          track.name,
          null,
          codec: row['codec']?.toString(),
        );
        await player.setSubtitleTrack(selected);
        if (valid(generation)) await onSubtitleChanged(selected);
      } else {
        await player.setAudioTrack(
          AudioTrack('${row['id']}', track.name, null),
        );
      }
    }
  }

  Future<void> rememberSelection(ExternalTrackKind kind, String nativeId) {
    final generation = _generation;
    return _serial(() async {
      if (!valid(generation) || _store == null) return;
      String? selected;
      for (final track in _snapshot.tracks) {
        if (track.kind == kind &&
            (_nativeIds[track.id] == nativeId || track.path == nativeId)) {
          selected = track.id;
        }
      }
      _snapshot = _snapshot.select(kind, selected);
      await _store!.save(_snapshot);
    });
  }

  void _notice(String message) {
    if (!alive() || _closed) return;
    ScaffoldMessenger.of(
      context(),
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
