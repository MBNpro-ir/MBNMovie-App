import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExternalTrackKind { audio, subtitle }

class ExternalMediaTrack {
  const ExternalMediaTrack({
    required this.id,
    required this.path,
    required this.name,
    required this.kind,
  });
  final String id;
  final String path;
  final String name;
  final ExternalTrackKind kind;

  factory ExternalMediaTrack.file(String path, ExternalTrackKind kind) {
    final normalized = path.replaceAll('\\', '/');
    return ExternalMediaTrack(
      id: sha256
          .convert(utf8.encode('${kind.name}\u0000${normalized.toLowerCase()}'))
          .toString(),
      path: path,
      name: normalized.split('/').last,
      kind: kind,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'kind': kind.name,
  };

  static ExternalMediaTrack? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    if (path is! String ||
        path.isEmpty ||
        path.length > 32768 ||
        path.contains('\u0000')) {
      return null;
    }
    final kind = switch (value['kind']) {
      'audio' => ExternalTrackKind.audio,
      'subtitle' => ExternalTrackKind.subtitle,
      _ => null,
    };
    return kind == null ? null : ExternalMediaTrack.file(path, kind);
  }
}

class ExternalTrackSnapshot {
  const ExternalTrackSnapshot({
    this.tracks = const [],
    this.audioId,
    this.subtitleId,
  });
  final List<ExternalMediaTrack> tracks;
  final String? audioId;
  final String? subtitleId;

  String? selected(ExternalTrackKind kind) =>
      kind == ExternalTrackKind.audio ? audioId : subtitleId;

  ExternalTrackSnapshot select(ExternalTrackKind kind, String? id) =>
      ExternalTrackSnapshot(
        tracks: tracks,
        audioId: kind == ExternalTrackKind.audio ? id : audioId,
        subtitleId: kind == ExternalTrackKind.subtitle ? id : subtitleId,
      );

  ExternalTrackSnapshot add(ExternalMediaTrack track, {bool activate = true}) {
    final all = [...tracks.where((t) => t.id != track.id), track];
    final retained = all
        .skip(all.length > 64 ? all.length - 64 : 0)
        .toList(growable: false);
    final ids = retained.map((t) => t.id).toSet();
    final result = ExternalTrackSnapshot(
      tracks: retained,
      audioId: ids.contains(audioId) ? audioId : null,
      subtitleId: ids.contains(subtitleId) ? subtitleId : null,
    );
    return activate ? result.select(track.kind, track.id) : result;
  }

  ExternalTrackSnapshot remove(String id) => ExternalTrackSnapshot(
    tracks: tracks.where((t) => t.id != id).toList(growable: false),
    audioId: audioId == id ? null : audioId,
    subtitleId: subtitleId == id ? null : subtitleId,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'audio': audioId,
    'subtitle': subtitleId,
  };

  static ExternalTrackSnapshot decode(String? text) {
    try {
      final data = jsonDecode(text ?? '{}');
      if (data is! Map || data['version'] != 1 || data['tracks'] is! List) {
        return const ExternalTrackSnapshot();
      }
      final byId = <String, ExternalMediaTrack>{};
      for (final value in (data['tracks'] as List).take(64)) {
        final track = ExternalMediaTrack.fromJson(value);
        if (track != null) byId[track.id] = track;
      }
      String? selected(String field, ExternalTrackKind kind) {
        final id = data[field];
        return id is String && byId[id]?.kind == kind ? id : null;
      }

      return ExternalTrackSnapshot(
        tracks: byId.values.toList(growable: false),
        audioId: selected('audio', ExternalTrackKind.audio),
        subtitleId: selected('subtitle', ExternalTrackKind.subtitle),
      );
    } catch (_) {
      return const ExternalTrackSnapshot();
    }
  }
}

/// Device-local references, deliberately outside account-synced player keys.
class ExternalMediaTrackStore {
  ExternalMediaTrackStore({
    required String owner,
    required String contentId,
    required String episodeId,
  }) : key =
           'external_tracks_v1_${sha256.convert(utf8.encode(jsonEncode([owner, contentId, episodeId])))}';
  final String key;

  Future<ExternalTrackSnapshot> load() async => ExternalTrackSnapshot.decode(
    (await SharedPreferences.getInstance()).getString(key),
  );

  Future<void> save(ExternalTrackSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(snapshot.toJson());
    if (prefs.getString(key) != encoded &&
        !await prefs.setString(key, encoded)) {
      throw StateError('external track preferences were not saved');
    }
  }
}

ExternalTrackKind? externalTrackKind(String path) {
  final ext = path
      .replaceAll('\\', '/')
      .split('/')
      .last
      .split('.')
      .last
      .toLowerCase();
  if (const {
    'srt',
    'vtt',
    'ass',
    'ssa',
    'sub',
    'idx',
    'sup',
    'smi',
    'sami',
    'lrc',
    'ttml',
    'dfxp',
    'sbv',
    'mpl2',
    'jss',
    'rt',
    'pjs',
    'aqt',
    'stl',
    'scc',
    'txt',
  }.contains(ext)) {
    return ExternalTrackKind.subtitle;
  }
  if (const {
    'mp3',
    'm4a',
    'aac',
    'ac3',
    'eac3',
    'dts',
    'flac',
    'wav',
    'wave',
    'ogg',
    'oga',
    'opus',
    'mka',
    'wma',
    'aiff',
    'aif',
    'ape',
    'alac',
    'amr',
    'mp2',
    'm4b',
    'aifc',
    'wv',
    'tak',
    'tta',
    'caf',
    'au',
    'mpa',
    'm4r',
  }.contains(ext)) {
    return ExternalTrackKind.audio;
  }
  return null; // Unknown containers are offered as audio/subtitle, not rejected by suffix.
}
