import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/library_store.dart';
import '../core/playlist_store.dart';
import '../models/movie_content.dart';
import 'accessibility_service.dart';
import 'mbn_auth.dart';

/// Server sync for favorites / playlists / history / watch progress.
///
/// Last-write-wins per category using timestamps: the side with the newer
/// timestamp wins, so an admin-side clear propagates on the next sync and
/// two devices converge without resurrecting deleted rows.
class MbnSync {
  MbnSync._();
  static final instance = MbnSync._();

  static const _app = 'movie';
  static const _tsPrefix = 'mbn_sync_ts_';
  static const _categories = [
    'favorites', 'playlists', 'history', 'progress', 'preferences',
  ];

  MbnAuth? _auth;
  DateTime? _lastHistoryPush;
  Timer? _pendingProgressPush;
  Timer? _pendingPreferencesPush;
  bool _syncing = false;

  void configure({required MbnAuth auth}) => _auth = auth;
  void clear() {
    _pendingProgressPush?.cancel();
    _pendingPreferencesPush?.cancel();
    _pendingProgressPush = null;
    _pendingPreferencesPush = null;
    _auth = null;
  }

  Future<void> bindAccount(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getInt('mbn_sync_owner_v1');
    if (owner == userId) return;
    if (owner != null) {
      final lib = LibraryStore();
      await lib.saveFavorites([]);
      await lib.saveHistory([]);
      final lists = PlaylistStore();
      for (final list in await lists.playlists()) {
        await lists.delete(list.id);
      }
      for (final key in prefs.getKeys().toList()) {
        if (_isProgressKey(key) || _isPreferenceKey(key) ||
            key.startsWith(_tsPrefix) ||
            key.startsWith('mbn_sync_dirty_') ||
            key.startsWith('mbn_sync_rev_')) {
          await prefs.remove(key);
        }
      }
    }
    await prefs.setInt('mbn_sync_owner_v1', userId);
  }

  static bool _isProgressKey(String key) =>
      key.startsWith('watch_pos_') ||
      key.startsWith('watch_dur_') ||
      key.startsWith('watch_done_') ||
      key.startsWith('watch_time_') ||
      key == 'watch_last_v1';

  static bool _isPreferenceKey(String key) =>
      key.startsWith('sub_') ||
      key.startsWith('access_') ||
      key == 'player_volume' ||
      key == 'player_rate' ||
      key == 'player_fit_cover' ||
      key == 'default_video_player' ||
      key == 'default_streamer' ||
      key == 'preferred_stream_quality';

  static bool _isDoublePreferenceKey(String key) =>
      key == 'player_volume' ||
      key == 'player_rate' ||
      key == 'sub_size' ||
      key == 'sub_height' ||
      key == 'sub_bg' ||
      key == 'sub_radius' ||
      key == 'sub_bottom' ||
      key == 'sub_delay' ||
      key == 'sub_timing_scale' ||
      key == 'access_ui_scale' ||
      key == 'access_text_scale';

  static bool _isIntPreferenceKey(String key) =>
      key == 'sub_color' ||
      key == 'sub_bg_color';

  static String _tsKey(String category) => '$_tsPrefix$category';

  Future<int> _localTs(String category) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_tsKey(category)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _touchLocal(String category) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _tsKey(category),
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await prefs.setBool('mbn_sync_dirty_$category', true);
      await prefs.setInt(
        'mbn_sync_rev_$category',
        (prefs.getInt('mbn_sync_rev_$category') ?? 0) + 1,
      );
    } catch (_) {}
  }

  Future<void> _setLocalTs(String category, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_tsKey(category), value);
    } catch (_) {}
  }

  /// Full sync: pull newer server rows, push newer local rows.
  Future<void> syncAll() async {
    final auth = _auth;
    if (auth?.token == null || _syncing) return;
    _syncing = true;
    try {
      final server = await auth!.getJson('/api/sync', query: {'app': _app});
      final lib = LibraryStore();
      final lists = PlaylistStore();
      for (final category in _categories) {
        final row = (server[category] as Map?)?.cast<String, dynamic>();
        final serverTs = (row?['updated_at'] as num?)?.toInt() ?? 0;
        final localTs = await _localTs(category);
        final prefs = await SharedPreferences.getInstance();
        final dirty = prefs.getBool('mbn_sync_dirty_$category') ?? false;
        if (dirty) {
          await _pushCategories([category]);
        } else if (serverTs > localTs) {
          await _applyServer(category, row?['payload'], lib, lists);
          await _setLocalTs(category, serverTs);
        } else if (serverTs == 0 && localTs == 0) {
          await _pushCategories([category]);
        }
      }
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  Future<void> _applyServer(
    String category,
    Object? payload,
    LibraryStore lib,
    PlaylistStore lists,
  ) async {
    try {
      switch (category) {
        case 'favorites':
          await lib.saveFavorites(_decodeContents(payload));
        case 'history':
          await lib.saveHistory(_decodeContents(payload));
        case 'playlists':
          await _restorePlaylists(lists, payload);
        case 'progress':
          await _restoreProgress(payload);
        case 'preferences':
          await _restorePreferences(payload);
      }
    } catch (_) {}
  }

  Future<void> _pushCategories(List<String> targets) async {
    final auth = _auth;
    if (auth?.token == null) return;
    final lib = LibraryStore();
    final lists = PlaylistStore();
    final data = <String, dynamic>{};
    final prefs = await SharedPreferences.getInstance();
    final revisions = <String, int>{};
    for (final category in targets) {
      revisions[category] = prefs.getInt('mbn_sync_rev_$category') ?? 0;
      data[category] = await _localBundle(category, lib, lists);
    }
    try {
      final updated = await auth!.putJson('/api/sync', {
        'app': _app,
        'data': data,
      });
      for (final category in targets) {
        final row = (updated[category] as Map?)?.cast<String, dynamic>();
        final ts = (row?['updated_at'] as num?)?.toInt() ?? 0;
        await _setLocalTs(category, ts);
        if ((prefs.getInt('mbn_sync_rev_$category') ?? 0) ==
            revisions[category]) {
          await prefs.setBool('mbn_sync_dirty_$category', false);
        }
      }
    } catch (_) {}
  }

  Future<void> pushFavorites() async {
    await _touchLocal('favorites');
    await _pushCategories(['favorites']);
  }

  Future<void> pushPlaylists() async {
    await _touchLocal('playlists');
    await _pushCategories(['playlists']);
  }

  Future<void> pushPreferences() async {
    if (_auth?.token == null) return;
    await _touchLocal('preferences');
    _pendingPreferencesPush?.cancel();
    _pendingPreferencesPush = Timer(const Duration(seconds: 2), () {
      _pendingPreferencesPush = null;
      unawaited(_pushCategories(['preferences']));
    });
  }

  /// History/progress change often during playback; throttle pushes.
  Future<void> pushHistoryThrottled() async {
    final now = DateTime.now();
    if (_lastHistoryPush != null &&
        now.difference(_lastHistoryPush!) < const Duration(seconds: 60)) {
      await _touchLocal('history');
      await _touchLocal('progress');
      _scheduleProgressPush();
      return;
    }
    _lastHistoryPush = now;
    await _touchLocal('history');
    await _touchLocal('progress');
    await _pushCategories(['history']);
    await _pushCategories(['progress']);
  }

  Future<void> pushProgressThrottled() async {
    if (_auth?.token == null) return;
    await _touchLocal('progress');
    final now = DateTime.now();
    if (_lastHistoryPush == null ||
        now.difference(_lastHistoryPush!) >= const Duration(seconds: 60)) {
      _lastHistoryPush = now;
      await _pushCategories(['progress']);
    } else {
      _scheduleProgressPush();
    }
  }

  void _scheduleProgressPush() {
    _pendingProgressPush ??= Timer(const Duration(seconds: 60), () {
      _pendingProgressPush = null;
      _lastHistoryPush = DateTime.now();
      unawaited(_pushCategories(['progress']));
    });
  }

  Future<void> pushPreferencesThrottled() async {
    if (_auth?.token == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('sync_settings_enabled') ?? true)) return;
    await _touchLocal('preferences');
    _pendingPreferencesPush?.cancel();
    _pendingPreferencesPush = Timer(const Duration(milliseconds: 800), () {
      _pendingPreferencesPush = null;
      unawaited(_pushCategories(['preferences']));
    });
  }

  Future<void> flushPending() async {
    _pendingProgressPush?.cancel();
    _pendingProgressPush = null;
    _pendingPreferencesPush?.cancel();
    _pendingPreferencesPush = null;
    final prefs = await SharedPreferences.getInstance();
    for (final category in _categories) {
      if (prefs.getBool('mbn_sync_dirty_$category') ?? false) {
        await _pushCategories([category]);
      }
    }
  }

  Future<void> checkOtherAppSettingsPrompt(BuildContext context) async {
    final auth = _auth;
    if (auth?.token == null) return;
    final profile = auth?.profile;
    if (profile == null || profile.id <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final promptKey = 'mbn_other_app_settings_prompted_${profile.id}';
    if (prefs.getBool(promptKey) ?? false) return;

    try {
      final platformKey = Platform.isWindows ? 'windows' : (Platform.isAndroid ? 'android' : 'other');
      final res = await auth!.getJson('/api/sync/other-settings', query: {'platform': platformKey});
      if (res['has_settings'] == true && res['settings'] is Map) {
        final otherName = res['other_app_name']?.toString() ?? 'برنامه دیگر';
        if (!context.mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('همگام‌سازی تنظیمات'),
              content: Text(
                'بخش تنظیمات برنامه در سرور یافت شد ، آیا مایل هستی که تنظیمات خودت رو از برنامه $otherName دریافت کنم ؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('خیر'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('بله'),
                ),
              ],
            ),
          ),
        );
        if (accepted == true) {
          final ok = await _restorePreferences(res['settings']);
          if (ok) {
            await _touchLocal('preferences');
            unawaited(pushPreferencesThrottled());
            try {
              await AccessibilityService.instance.reloadFromStore();
            } catch (_) {}
          }
        }
      }
      await prefs.setBool(promptKey, true);
    } catch (_) {}
  }

  /// Pulls preferences from server (current app, and if empty/unconfigured, other app)
  /// and applies them immediately to local store.
  Future<bool> pullAndApplyPreferences({bool force = false}) async {
    final auth = _auth;
    if (auth?.token == null) return false;
    try {
      bool restored = false;
      // 1. Try pulling preferences from this app's sync endpoint
      final server = await auth!.getJson('/api/sync', query: {'app': _app});
      final row = (server['preferences'] as Map?)?.cast<String, dynamic>();
      final payload = row?['payload'];
      if (payload is Map && payload.isNotEmpty) {
        restored = await _restorePreferences(payload);
        if (restored) {
          final ts = (row?['updated_at'] as num?)?.toInt() ?? 0;
          if (ts > 0) await _setLocalTs('preferences', ts);
        }
      }

      // 2. If current app had no settings or nothing restored, fallback to checking other app's settings
      if (!restored) {
        final platformKey = Platform.isWindows ? 'windows' : (Platform.isAndroid ? 'android' : 'other');
        final otherRes = await auth.getJson(
          '/api/sync/other-settings',
          query: {'platform': platformKey},
        );
        if (otherRes['has_settings'] == true && otherRes['settings'] is Map) {
          restored = await _restorePreferences(otherRes['settings']);
          if (restored) {
            await _touchLocal('preferences');
            unawaited(pushPreferencesThrottled());
          }
        }
      }

      if (restored) {
        try {
          await AccessibilityService.instance.reloadFromStore();
        } catch (_) {}
      }
      return restored;
    } catch (_) {
      return false;
    }
  }

  Future<void> pushAll() => _pushCategories(_categories);

  Future<void> touchAndPush(String category) async {
    await _touchLocal(category);
    await _pushCategories([category]);
  }

  // ---------------------------------------------------------- local I/O ---
  Future<Object?> _localBundle(
    String category,
    LibraryStore lib,
    PlaylistStore lists,
  ) async {
    switch (category) {
      case 'favorites':
        return (await lib.favorites()).map(_encodeContent).toList();
      case 'history':
        return (await lib.history()).map(_encodeContent).toList();
      case 'playlists':
        return (await lists.playlists()).map((list) => list.toJson()).toList();
      case 'progress':
        return _readProgressKeys();
      case 'preferences':
        final prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool('sync_settings_enabled') ?? true)) return null;
        final raw = await _readPreferenceKeys();
        final platformKey = Platform.isWindows ? 'windows' : (Platform.isAndroid ? 'android' : 'other');
        return {platformKey: raw};
    }
    return null;
  }

  Future<Map<String, dynamic>> _readProgressKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (_isProgressKey(key)) {
          final value = prefs.get(key);
          if (value is num || value is bool || value is String) {
            out[key] = value;
          }
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _readPreferenceKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys().where(_isPreferenceKey)) {
      final value = prefs.get(key);
      if (value is num || value is bool || value is String) out[key] = value;
    }
    return out;
  }

  Future<bool> _restorePreferences(Object? payload) async {
    if (payload is! Map) return false;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('sync_settings_enabled') ?? true)) return false;

    final platformKey = Platform.isWindows ? 'windows' : (Platform.isAndroid ? 'android' : 'other');
    Map? targetPayload;
    bool isCrossPlatformFallback = false;

    if (payload.containsKey(platformKey) && payload[platformKey] is Map && (payload[platformKey] as Map).isNotEmpty) {
      targetPayload = payload[platformKey] as Map;
    } else if (payload.containsKey('windows') && payload['windows'] is Map && (payload['windows'] as Map).isNotEmpty) {
      targetPayload = payload['windows'] as Map;
      isCrossPlatformFallback = (platformKey != 'windows');
    } else if (payload.containsKey('android') && payload['android'] is Map && (payload['android'] as Map).isNotEmpty) {
      targetPayload = payload['android'] as Map;
      isCrossPlatformFallback = (platformKey != 'android');
    } else if (payload.containsKey('other') && payload['other'] is Map && (payload['other'] as Map).isNotEmpty) {
      targetPayload = payload['other'] as Map;
      isCrossPlatformFallback = (platformKey != 'other');
    } else if (!payload.containsKey('windows') && !payload.containsKey('android') && !payload.containsKey('other')) {
      targetPayload = payload;
    }

    if (targetPayload == null || targetPayload.isEmpty) return false;

    for (final entry in targetPayload.entries) {
      final key = '${entry.key}';
      if (!_isPreferenceKey(key)) continue;
      // Do not overwrite UI scale when falling back from a different platform
      if (isCrossPlatformFallback && key == 'access_ui_scale') continue;
      final value = entry.value;
      if (value == null) continue;

      if (_isDoublePreferenceKey(key)) {
        double? d;
        if (value is num) {
          d = value.toDouble();
        } else if (value is String) {
          d = double.tryParse(value);
        }
        if (d != null) {
          await prefs.remove(key);
          await prefs.setDouble(key, d);
        }
      } else if (_isIntPreferenceKey(key)) {
        int? i;
        if (value is num) {
          i = value.toInt();
        } else if (value is String) {
          i = int.tryParse(value);
        }
        if (i != null) {
          await prefs.remove(key);
          await prefs.setInt(key, i);
        }
      } else if (value is bool) {
        await prefs.remove(key);
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.remove(key);
        await prefs.setString(key, value);
      }
    }

    try {
      await AccessibilityService.instance.reloadFromStore();
    } catch (_) {}

    return true;
  }

  Future<void> _restorePlaylists(PlaylistStore lists, Object? payload) async {
    final rows = payload is List ? payload : const [];
    final current = await lists.playlists();
    final seen = {for (final list in current) list.id};
    for (final row in rows.whereType<Map>()) {
      final parsed = MoviePlaylist.fromJson(
        row.map((key, value) => MapEntry('$key', value)),
      );
      if (parsed == null || !seen.add(parsed.id)) continue;
      await lists.importPlaylist(parsed);
    }
    for (final list in current) {
      if (!rows.any((row) => row is Map && '${row['id']}' == list.id)) {
        await lists.delete(list.id);
      }
    }
  }

  Future<void> _restoreProgress(Object? payload) async {
    if (payload is! Map) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final received = payload.keys
          .map((key) => '$key')
          .where(_isProgressKey)
          .toSet();
      for (final key in prefs.getKeys().where(_isProgressKey).toList()) {
        if (!received.contains(key)) await prefs.remove(key);
      }
      for (final entry in payload.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        final isWatchKey = _isProgressKey(key);
        if (!isWatchKey) continue;
        if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is String) {
          await prefs.setString(key, value);
        } else {
          continue;
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- codecs -
  static Map<String, Object?> _encodeContent(MovieContent item) => {
    'id': item.id,
    'title': item.title,
    'subtitle': item.subtitle,
    'description': item.description,
    'year': item.year,
    'rating': item.rating,
    'kind': item.kind.name,
    'colors': item.colors.map((color) => color.toARGB32()).toList(),
    'genres': item.genres,
    'imageUrl': item.imageUrl,
    'backdropUrl': item.backdropUrl,
    'detailUrl': item.detailUrl,
    'tags': item.tags,
  };

  static List<MovieContent> _decodeContents(Object? payload) {
    final rows = payload is List ? payload : const [];
    return [
      for (final row in rows.whereType<Map>())
        _decodeContent(row.map((key, value) => MapEntry('$key', value))),
    ].where((item) => item.id.isNotEmpty).toList();
  }

  static MovieContent _decodeContent(Map<String, dynamic> row) {
    final kindName = row['kind']?.toString();
    final kind = ContentKind.values.where((value) => value.name == kindName);
    var kindValue = kind.isEmpty ? ContentKind.movie : kind.first;
    if (kindName == 'anime') kindValue = ContentKind.movie;
    final colors = (row['colors'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((value) => Color(value.toInt()))
        .toList();
    return MovieContent(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? 'بدون عنوان',
      subtitle: row['subtitle']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      year: (row['year'] as num?)?.toInt() ?? 0,
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      kind: kindValue,
      colors: colors.length >= 2
          ? colors
          : const [Color(0xFF4665B3), Color(0xFF10182B)],
      genres: (row['genres'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      imageUrl: row['imageUrl']?.toString(),
      backdropUrl: row['backdropUrl']?.toString(),
      detailUrl: row['detailUrl']?.toString(),
      tags: (row['tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}
