import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../services/mbn_sync.dart';

enum WatchStatus { unwatched, partial, watched }

/// Saved playback position of a single episode.
class SavedWatchProgress {
  const SavedWatchProgress({
    required this.positionMs,
    required this.durationMs,
    this.watched = false,
    this.manualStatus,
    this.updatedAtMs = 0,
  });

  final int positionMs;
  final int durationMs;
  final bool watched;
  final WatchStatus? manualStatus;

  /// Last write time (epoch ms). Picks the most-recently watched episode of
  /// a title for its «ادامه تماشا» button. 0 = written before tracking.
  final int updatedAtMs;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  /// Offer "resume" only for genuinely partial watches.
  bool get isResumable =>
      positionMs > 15000 &&
      (durationMs <= 0 || positionMs < durationMs - 30000);

  bool get almostWatched =>
      !watched &&
      durationMs > 0 &&
      positionMs > 0 &&
      positionMs <= durationMs &&
      durationMs - positionMs <= const Duration(minutes: 5).inMilliseconds;
}

/// Persists per-episode playback positions in local preferences so the
/// user can resume later. The watched marker is stored independently from the
/// position so replaying or moving to the next episode does not erase history.
class WatchProgressStore {
  static final changes = ValueNotifier<int>(0);
  static String _posKey(String contentId, String episodeId) =>
      'watch_pos_${contentId}_$episodeId';
  static String _durKey(String contentId, String episodeId) =>
      'watch_dur_${contentId}_$episodeId';
  static String _watchedKey(String contentId, String episodeId) =>
      'watch_done_${contentId}_$episodeId';
  static String _statusKey(String contentId, String episodeId) =>
      'watch_status_${contentId}_$episodeId';
  static String _timeKey(String contentId, String episodeId) =>
      'watch_time_${contentId}_$episodeId';

  Future<void> save({
    required String contentId,
    required String episodeId,
    required Duration position,
    required Duration duration,
    bool markWatched = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (position > Duration.zero) {
      await prefs.remove(_statusKey(contentId, episodeId));
    }
    await prefs.setInt(_posKey(contentId, episodeId), position.inMilliseconds);
    await prefs.setInt(_durKey(contentId, episodeId), duration.inMilliseconds);
    await prefs.setInt(
      _timeKey(contentId, episodeId),
      (prefs.getInt(_timeKey(contentId, episodeId)) ?? 0) >=
              DateTime.now().millisecondsSinceEpoch
          ? (prefs.getInt(_timeKey(contentId, episodeId)) ?? 0) + 1
          : DateTime.now().millisecondsSinceEpoch,
    );
    final reachedEnd =
        duration > Duration.zero &&
        position >= duration - const Duration(seconds: 10);
    if (markWatched || reachedEnd) {
      await prefs.remove(_statusKey(contentId, episodeId));
      await prefs.setBool(_watchedKey(contentId, episodeId), true);
    }
    unawaited(MbnSync.instance.pushProgressThrottled());
  }

  Future<SavedWatchProgress?> load({
    required String contentId,
    required String episodeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getInt(_posKey(contentId, episodeId));
    final watched = prefs.getBool(_watchedKey(contentId, episodeId)) ?? false;
    final status = WatchStatus.values
        .where(
          (s) => s.name == prefs.getString(_statusKey(contentId, episodeId)),
        )
        .firstOrNull;
    if ((pos == null || pos <= 0) && !watched && status == null) return null;
    final dur = prefs.getInt(_durKey(contentId, episodeId)) ?? 0;
    return SavedWatchProgress(
      positionMs: pos ?? 0,
      durationMs: dur,
      watched: watched,
      manualStatus: status,
      updatedAtMs: prefs.getInt(_timeKey(contentId, episodeId)) ?? 0,
    );
  }

  /// Clears canonical and legacy quality identities together. Other episodes
  /// and the last-watch slot of a different episode are preserved.
  Future<bool> resetEpisode({
    required String contentId,
    required Set<String> episodeIds,
    required Set<String> fileUrls,
    bool hentai = false,
    bool sync = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in episodeIds) {
      for (final key in [
        _posKey(contentId, id),
        _durKey(contentId, id),
        _watchedKey(contentId, id),
        _statusKey(contentId, id),
        _timeKey(contentId, id),
      ]) {
        await prefs.remove(key);
      }
    }
    final slot = hentai ? 'watch_last_hentai_v1' : 'watch_last_v1';
    final raw = prefs.getString(slot);
    if (raw != null) {
      try {
        final last = LastWatch.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (last?.contentId == contentId &&
            (episodeIds.contains(last!.episodeId) ||
                fileUrls.contains(last.fileUrl))) {
          await prefs.remove(slot);
        }
      } catch (_) {}
    }
    changes.value++;
    if (hentai) return true;
    if (!sync) return true;
    return MbnSync.instance.resetEpisodeProgress(contentId, episodeIds);
  }

  /// A manual marker does not invent a duration or watched minutes.
  Future<bool> setStatus({
    required String contentId,
    required String episodeId,
    required Set<String> episodeIds,
    required Set<String> fileUrls,
    required WatchStatus status,
  }) async {
    final old = await load(contentId: contentId, episodeId: episodeId);
    await resetEpisode(
      contentId: contentId,
      episodeIds: episodeIds,
      fileUrls: fileUrls,
      sync: false,
    );
    final prefs = await SharedPreferences.getInstance();
    final pos = status == WatchStatus.partial && old?.isResumable == true
        ? old!.positionMs
        : 0;
    final duration = old?.durationMs ?? 0;
    final written = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_posKey(contentId, episodeId), pos);
    await prefs.setInt(_durKey(contentId, episodeId), duration);
    await prefs.setBool(
      _watchedKey(contentId, episodeId),
      status == WatchStatus.watched,
    );
    await prefs.setString(_statusKey(contentId, episodeId), status.name);
    await prefs.setInt(_timeKey(contentId, episodeId), written);
    changes.value++;
    return MbnSync.instance.setEpisodeStatus(
      contentId,
      episodeId,
      episodeIds,
      status.name,
      pos,
      duration,
      written,
    );
  }

  Future<void> clear({
    required String contentId,
    required String episodeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posKey(contentId, episodeId));
    await prefs.remove(_durKey(contentId, episodeId));
    await prefs.remove(_watchedKey(contentId, episodeId));
    await prefs.remove(_statusKey(contentId, episodeId));
    await prefs.remove(_timeKey(contentId, episodeId));
    unawaited(MbnSync.instance.pushProgressThrottled());
  }
}

/// The single most-recent playback exit across all titles: what the user was
/// watching last and the exact position when they left the player. Backs the
/// global «ادامه تماشا» button shown under the play button.
class LastWatch {
  const LastWatch({
    required this.contentId,
    required this.title,
    required this.episodeId,
    required this.episodeName,
    required this.fileUrl,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
  });

  final String contentId;
  final String title;
  final String episodeId;
  final String episodeName;
  final String fileUrl;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  /// Same resumability contract as [SavedWatchProgress]: only genuinely
  /// partial watches are offered for continuation.
  bool get isResumable =>
      positionMs > 15000 &&
      (durationMs <= 0 || positionMs < durationMs - 30000);

  Map<String, dynamic> toJson() => {
    'contentId': contentId,
    'title': title,
    'episodeId': episodeId,
    'episodeName': episodeName,
    'fileUrl': fileUrl,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAtMs': updatedAtMs,
  };

  static LastWatch? fromJson(Map<String, dynamic> json) {
    try {
      final contentId = json['contentId']?.toString() ?? '';
      final fileUrl = json['fileUrl']?.toString() ?? '';
      if (contentId.isEmpty || fileUrl.isEmpty) return null;
      return LastWatch(
        contentId: contentId,
        title: json['title']?.toString() ?? 'بدون عنوان',
        episodeId: json['episodeId']?.toString() ?? '',
        episodeName: json['episodeName']?.toString() ?? '',
        fileUrl: fileUrl,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persists the single most-recent playback exit (see [LastWatch]).
class LastWatchStore {
  const LastWatchStore();

  static const _key = 'watch_last_v1';

  String get _slot => _key;

  Future<void> save(LastWatch last) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      ...last.toJson(),
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_slot, jsonEncode(payload));
    WatchProgressStore.changes.value++;
    unawaited(MbnSync.instance.pushProgressThrottled());
  }

  Future<LastWatch?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_slot);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      final last = LastWatch.fromJson(data);
      if (last == null || !last.isResumable) return null;
      return last;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_slot);
      unawaited(MbnSync.instance.pushProgressThrottled());
    } catch (_) {}
  }
}
