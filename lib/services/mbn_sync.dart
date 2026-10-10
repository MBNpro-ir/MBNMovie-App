import '../core/title_language.dart';
import 'account_profile.dart';
import 'app_links.dart';
import '../core/sync_merge.dart';
import '../core/watch_progress.dart';
import 'dart:convert';
import 'dart:async';
import '../core/platform_ui.dart' show settingsDeviceProfile;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/library_store.dart';
import '../core/playlist_store.dart';
import '../models/movie_content.dart';
import 'accessibility_service.dart';
import 'mbn_auth.dart';

/// Server sync for favorites / playlists / history / watch progress.
///
/// Server cursors detect remote edits; base snapshots preserve independent
/// local changes while device revisions prevent delayed responses from
/// overwriting newer edits.
class MbnSync {
  MbnSync._();
  static final instance = MbnSync._();
  final changes = ValueNotifier<int>(0);
  Set<String> changedCategories = const {};
  bool _settingsChoicePending = false;
  bool _prompting = false;
  int _loginChoice = 0;
  void beginSettingsChoice() {
    _settingsChoicePending = true;
    _loginChoice++;
  }

  static const _app = 'movie';
  static const _tsPrefix = 'mbn_sync_ts_';
  static const _categories = [
    'favorites',
    'playlists',
    'history',
    'progress',
    'preferences',
  ];

  MbnAuth? _auth;
  DateTime? _lastHistoryPush;
  Timer? _pendingProgressPush;
  Timer? _pendingPreferencesPush;
  bool _syncing = false;
  bool _resyncRequested = false;
  int _generation = 0;
  final Set<String> _pendingPushes = {};
  final Map<String, Object?> _baseSnapshots = {};
  Future<void>? _pushing;

  void _invalidateNetworkWork() {
    _generation++;
    _baseSnapshots.clear();
    _pendingProgressPush?.cancel();
    _pendingPreferencesPush?.cancel();
    _pendingProgressPush = null;
    _pendingPreferencesPush = null;
    _lastHistoryPush = null;
    _pendingPushes.clear();
    _pushing = null;
  }

  bool _resettingProgress = false;
  static const _pendingResetKey = 'mbn_progress_resets_v1';

  void configure({required MbnAuth auth}) {
    _invalidateNetworkWork();
    _auth = auth;
    AccountProfile.configure(auth);
    if (AccountProfile.owner != null) {
      unawaited(
        AccountProfile.reload()
            .then((_) => AccountProfile.flush())
            .catchError((Object _) {}),
      );
    }
  }

  void clear() {
    _invalidateNetworkWork();
    _settingsChoicePending = false;
    _loginChoice++;
    AccountProfile.configure(null);
    _pendingProgressPush?.cancel();
    _pendingPreferencesPush?.cancel();
    _pendingProgressPush = null;
    _pendingPreferencesPush = null;
    _auth = null;
    _baseSnapshots.clear();
  }

  void _changed(Set<String> categories) {
    if (categories.isEmpty) return;
    changedCategories = Set.unmodifiable(categories);
    changes.value++;
    if (categories.contains('progress')) WatchProgressStore.changes.value++;
  }

  Future<void> bindAccount(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getInt('mbn_sync_owner_v1');
    if (owner == userId) return;
    _baseSnapshots.clear();
    if (owner != null) {
      final lib = LibraryStore();
      await lib.saveFavorites([]);
      await lib.saveHistory([]);
      final lists = PlaylistStore();
      for (final list in await lists.playlists()) {
        await lists.delete(list.id);
      }
      for (final key in prefs.getKeys().toList()) {
        if (_isProgressKey(key) ||
            _isPreferenceKey(key) ||
            key.startsWith(_tsPrefix) ||
            key.startsWith('mbn_sync_dirty_') ||
            key.startsWith('mbn_sync_rev_') ||
            key.startsWith('mbn_sync_base_') ||
            key == _pendingResetKey) {
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
      key.startsWith('watch_status_') ||
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
      key == 'preferred_stream_quality' ||
      key == TitleLanguage.preferenceKey;

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
      key == 'sub_color' || key == 'sub_bg_color';

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
      // Local revisions are independent of the wall clock and server cursor.
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

  static String _baseKey(String category) => 'mbn_sync_base_$category';

  Future<Object?> _readBase(String category) async {
    final cached = _baseSnapshots[category];
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_baseKey(category));
      if (raw == null) return null;
      final value = jsonDecode(raw);
      _baseSnapshots[category] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBase(String category, Object? payload) async {
    if (payload == null) return;
    _baseSnapshots[category] = payload;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_baseKey(category), jsonEncode(payload));
    } catch (_) {}
  }

  /// Full sync: pull newer server rows, push newer local rows.
  Future<void> syncAll() async {
    final auth = _auth;
    if (auth?.token == null) return;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }
    final generation = _generation;
    final credential = auth!.token;
    _syncing = true;
    try {
      if (!await _flushEpisodeResets()) return;
      if (generation != _generation || auth.token != credential) return;
      final server = await auth.getJson('/api/sync', query: {'app': _app});
      if (generation != _generation || auth.token != credential) return;
      final lib = LibraryStore();
      final lists = PlaylistStore();
      final changed = <String>{};
      for (final category in _categories) {
        if (category == 'preferences' && _settingsChoicePending) continue;
        if (generation != _generation || auth.token != credential) return;
        final row = (server[category] as Map?)?.cast<String, dynamic>();
        final serverTs = (row?['updated_at'] as num?)?.toInt() ?? 0;
        final localTs = await _localTs(category);
        final prefs = await SharedPreferences.getInstance();
        final dirty = prefs.getBool('mbn_sync_dirty_$category') ?? false;
        if (generation != _generation || auth.token != credential) return;
        if (dirty) {
          await _pushCategories([category]);
        } else if (serverTs > localTs) {
          await _applyServer(category, row?['payload'], lib, lists);
          await _setLocalTs(category, serverTs);
          await _writeBase(category, row?['payload']);
          changed.add(category);
        } else if (serverTs == 0 && localTs == 0) {
          final local = await _localBundle(category, lib, lists);
          if (local is List && local.isNotEmpty ||
              local is Map &&
                  local.values.any((v) => v is Map ? v.isNotEmpty : true)) {
            await _pushCategories([category]);
          }
        }
      }
      _changed(changed);
    } catch (_) {
    } finally {
      _syncing = false;
      if (_resyncRequested && generation == _generation) {
        _resyncRequested = false;
        unawaited(syncAll());
      }
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

  Future<void> _pushCategories(List<String> targets) {
    if (_auth?.token == null) return Future.value();
    _pendingPushes.addAll(
      targets.where((c) => c != 'preferences' || !_settingsChoicePending),
    );
    if (_pendingPushes.isEmpty) return Future.value();
    if (_pushing != null) return _pushing!;
    final generation = _generation;
    Future<void> drain() async {
      while (generation == _generation && _pendingPushes.isNotEmpty) {
        final batch = _pendingPushes.toList();
        _pendingPushes.clear();
        await _sendCategories(batch);
      }
    }

    late final Future<void> work;
    work = drain().whenComplete(() {
      if (identical(_pushing, work)) _pushing = null;
    });
    _pushing = work;
    return work;
  }

  Future<void> _sendCategories(List<String> targets) async {
    final auth = _auth;
    if (auth?.token == null) return;
    final generation = _generation;
    final credential = auth!.token;
    if (targets.contains('progress') && !await _flushEpisodeResets()) return;
    final lib = LibraryStore();
    final lists = PlaylistStore();
    final data = <String, dynamic>{};
    final prefs = await SharedPreferences.getInstance();
    final revisions = <String, int>{};
    final bases = <String, Object?>{};
    for (final category in targets) {
      revisions[category] = prefs.getInt('mbn_sync_rev_$category') ?? 0;
      final payload = await _localBundle(category, lib, lists);
      if (payload == null) continue;
      data[category] = payload;
      final base = await _readBase(category);
      if (base != null) bases[category] = base;
    }
    if (data.isEmpty) return;
    try {
      if (generation != _generation || auth.token != credential) return;
      final updated = await auth.putJson('/api/sync', {
        'app': _app,
        'data': data,
        if (bases.isNotEmpty) 'bases': bases,
      });
      if (generation != _generation || auth.token != credential) return;
      final changed = <String>{};
      for (final category in data.keys) {
        if (generation != _generation || auth.token != credential) return;
        final row = (updated[category] as Map?)?.cast<String, dynamic>();
        final ts = (row?['updated_at'] as num?)?.toInt() ?? 0;
        if (row == null || !row.containsKey('payload')) continue;
        final remotePayload = row['payload'];
        final current = await _localBundle(category, lib, lists);
        final unchanged =
            (prefs.getInt('mbn_sync_rev_$category') ?? 0) ==
                revisions[category] &&
            syncEqual(current, data[category]);
        final rebased = unchanged
            ? remotePayload
            : mergeSyncDelta(remotePayload, current, data[category]);
        if (!syncEqual(current, rebased)) {
          await _applyServer(category, rebased, lib, lists);
          changed.add(category);
        }
        await _setLocalTs(category, ts);
        await _writeBase(category, remotePayload);
        final editedDuringApply =
            (prefs.getInt('mbn_sync_rev_$category') ?? 0) !=
            revisions[category];
        await prefs.setBool(
          'mbn_sync_dirty_$category',
          !unchanged || editedDuringApply,
        );
        if (!unchanged || editedDuringApply) _pendingPushes.add(category);
      }
      _changed(changed);
    } catch (_) {}
  }

  /// Queue a scoped reset durably so an offline clear cannot be resurrected
  /// by the next server pull. The server rejects older device snapshots.
  Future<bool> resetEpisodeProgress(
    String contentId,
    Set<String> episodeIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingResetKey) ?? [];
    pending.add(
      jsonEncode({
        'app': _app,
        'content_id': contentId,
        'episode_ids': episodeIds.toList(),
      }),
    );
    await prefs.setStringList(_pendingResetKey, pending);
    await _touchLocal('progress');
    final synced = await _flushEpisodeResets();
    if (synced) {
      await _pushCategories(['progress']);
    } else if (_auth?.token != null) {
      _scheduleProgressPush();
    }
    return synced;
  }

  Future<bool> setEpisodeStatus(
    String contentId,
    String episodeId,
    Set<String> episodeIds,
    String status,
    int positionMs,
    int durationMs,
    int written,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingResetKey) ?? [];
    pending.add(
      jsonEncode({
        'app': _app,
        'content_id': contentId,
        'episode_id': episodeId,
        'episode_ids': episodeIds.toList(),
        'status': status,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'written_at_ms': written,
      }),
    );
    await prefs.setStringList(_pendingResetKey, pending);
    await _touchLocal('progress');
    final synced = await _flushEpisodeResets();
    if (synced) {
      await _pushCategories(['progress']);
    } else {
      _scheduleProgressPush();
    }
    return synced;
  }

  Future<bool> _flushEpisodeResets() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getStringList(_pendingResetKey) ?? []).isEmpty) return true;
    if (_auth?.token == null || _resettingProgress) return false;
    final source = _auth;
    final generation = _generation;
    final credential = source?.token;
    _resettingProgress = true;
    try {
      while ((prefs.getStringList(_pendingResetKey) ?? []).isNotEmpty) {
        if (generation != _generation || source?.token != credential) {
          return false;
        }
        final entry = prefs.getStringList(_pendingResetKey)!.first;
        final body = Map<String, dynamic>.from(jsonDecode(entry) as Map);
        final response = await source!.postJson(
          body.containsKey('status')
              ? '/api/sync/progress/set-status'
              : '/api/sync/progress/reset-episode',
          body,
        );
        if (generation != _generation || source.token != credential) {
          return false;
        }
        if (body.containsKey('status')) {
          final suffix = '${body['content_id']}_${body['episode_id']}';
          final serverTime =
              ((response['progress'] as Map?)?['payload']
                  as Map?)?['watch_time_$suffix'];
          if (serverTime is int) {
            final current = prefs.getInt('watch_time_$suffix') ?? 0;
            if (current == body['written_at_ms']) {
              await prefs.setInt('watch_time_$suffix', serverTime);
            } else if (current > body['written_at_ms'] &&
                prefs.getString('watch_status_$suffix') == null) {
              // Playback resumed while this manual marker was queued offline.
              await prefs.setInt(
                'watch_time_$suffix',
                current > serverTime ? current : serverTime + 1,
              );
            }
          }
        }
        final remaining = prefs.getStringList(_pendingResetKey) ?? [];
        remaining.remove(entry);
        await prefs.setStringList(_pendingResetKey, remaining);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _resettingProgress = false;
    }
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
        now.difference(_lastHistoryPush!) < const Duration(seconds: 5)) {
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
        now.difference(_lastHistoryPush!) >= const Duration(seconds: 5)) {
      _lastHistoryPush = now;
      await _pushCategories(['progress']);
    } else {
      _scheduleProgressPush();
    }
  }

  void _scheduleProgressPush() {
    _pendingProgressPush ??= Timer(const Duration(seconds: 5), () {
      _pendingProgressPush = null;
      _lastHistoryPush = DateTime.now();
      unawaited(_pushPendingProgress());
    });
  }

  Future<void> _pushPendingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await _pushCategories([
      if (prefs.getBool('mbn_sync_dirty_history') ?? false) 'history',
      'progress',
    ]);
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
    final transport = _auth;
    if (!_settingsChoicePending || _prompting || transport?.token == null) {
      return;
    }
    _prompting = true;
    final generation = _generation, choice = _loginChoice;
    try {
      final sources = await transport!.getJson(
        '/api/sync/other-settings',
        query: {'platform': settingsDeviceProfile},
      );
      if (generation != _generation ||
          choice != _loginChoice ||
          !context.mounted) {
        return;
      }
      final hasServer =
          sources['has_server_settings'] == true &&
          sources['server_settings'] is Map;
      final hasOther =
          sources['has_other_app_settings'] == true &&
          sources['other_settings'] is Map &&
          await AppLinks.isSiblingAvailable(siblingAnime);
      if (!context.mounted || generation != _generation) return;
      String? selected;
      if (hasServer || hasOther) {
        selected = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('دریافت تنظیمات'),
            content: const Text(
              'تنظیمات ذخیره‌شده پیدا شد. کدام منبع را دریافت می‌کنی؟',
            ),
            actions: [
              if (hasServer)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'server'),
                  child: const Text('دریافت از سرور'),
                ),
              if (hasOther)
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, 'other'),
                  child: Text('دریافت از ${siblingAnime.name}'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('لغو'),
              ),
            ],
          ),
        );
      }
      if (generation != _generation || choice != _loginChoice) return;
      final payload = selected == 'server'
          ? sources['server_settings']
          : selected == 'other'
          ? sources['other_settings']
          : null;
      if (payload is Map) await _restorePreferences(payload);
      // A cancelled import keeps local preferences until the next remote edit.
      final cursor = (sources['server_updated_at'] as num?)?.toInt() ?? 0;
      await _setLocalTs('preferences', cursor);
      await _writeBase('preferences', sources['server_settings']);
      _settingsChoicePending = false;
      if (selected == 'server') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('mbn_sync_dirty_preferences', false);
      } else if (selected == 'other') {
        await touchAndPush('preferences');
      }
      _changed({'preferences'});
    } catch (_) {
      // Retry on the next authenticated foreground entry; do not fabricate sources.
    } finally {
      _prompting = false;
    }
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
        final platformKey = settingsDeviceProfile;
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
        final platformKey = settingsDeviceProfile;
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

    final platformKey = settingsDeviceProfile;
    Map? targetPayload;
    bool isCrossPlatformFallback = false;

    const platforms = ['windows', 'android', 'web', 'tv', 'other'];
    if (payload[platformKey] is Map &&
        (payload[platformKey] as Map).isNotEmpty) {
      targetPayload = payload[platformKey] as Map;
    } else if (!platforms.any(payload.containsKey)) {
      targetPayload = payload;
    } else {
      for (final fallback in platforms) {
        if (payload[fallback] is Map && (payload[fallback] as Map).isNotEmpty) {
          targetPayload = payload[fallback] as Map;
          isCrossPlatformFallback = true;
          break;
        }
      }
    }

    if (targetPayload == null || targetPayload.isEmpty) return false;

    final writes = <Future<bool>>[];
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
          writes.add(prefs.setDouble(key, d));
        }
      } else if (_isIntPreferenceKey(key)) {
        int? i;
        if (value is num) {
          i = value.toInt();
        } else if (value is String) {
          i = int.tryParse(value);
        }
        if (i != null) {
          writes.add(prefs.setInt(key, i));
        }
      } else if (value is bool) {
        writes.add(prefs.setBool(key, value));
      } else if (value is String) {
        writes.add(prefs.setString(key, value));
      }
    }

    await Future.wait(writes);
    await TitleLanguage.reloadPreference();
    try {
      await AccessibilityService.instance.reloadFromStore();
    } catch (_) {}

    return true;
  }

  Future<void> _restorePlaylists(PlaylistStore lists, Object? payload) async {
    if (payload is! List) return;
    final received = <MoviePlaylist>[];
    final seen = <String>{};
    for (final row in payload.whereType<Map>()) {
      final parsed = MoviePlaylist.fromJson(
        row.map((key, value) => MapEntry('$key', value)),
      );
      if (parsed != null && seen.add(parsed.id)) received.add(parsed);
    }
    await lists.replaceAll(received);
  }

  Future<void> _restoreProgress(Object? payload) async {
    if (payload is! Map) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final writes = <Future<bool>>[];
      final received = payload.keys
          .map((key) => '$key')
          .where(_isProgressKey)
          .toSet();
      for (final key in prefs.getKeys().where(_isProgressKey).toList()) {
        if (!received.contains(key)) writes.add(prefs.remove(key));
      }
      for (final entry in payload.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        final isWatchKey = _isProgressKey(key);
        if (!isWatchKey) continue;
        if (value is int) {
          writes.add(prefs.setInt(key, value));
        } else if (value is double) {
          writes.add(prefs.setDouble(key, value));
        } else if (value is bool) {
          writes.add(prefs.setBool(key, value));
        } else if (value is String) {
          writes.add(prefs.setString(key, value));
        } else {
          continue;
        }
      }
      await Future.wait(writes);
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
