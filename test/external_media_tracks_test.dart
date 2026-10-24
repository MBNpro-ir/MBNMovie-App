import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/external_media_tracks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Windows slash and case duplicates have one identity; kinds stay separate',
    () {
      final a = ExternalMediaTrack.file(
            r'C:\Films\FA.SRT',
            ExternalTrackKind.subtitle,
          ),
          b = ExternalMediaTrack.file(
            'c:/films/fa.srt',
            ExternalTrackKind.subtitle,
          );
      expect(a.id, b.id);
      expect(
        a.id,
        isNot(ExternalMediaTrack.file(a.path, ExternalTrackKind.audio).id),
      );
      expect(const ExternalTrackSnapshot().add(a).add(b).tracks.length, 1);
    },
  );
  test(
    'Selected imported audio and subtitle survive serialization independently',
    () {
      final a = ExternalMediaTrack.file('C:/fa.flac', ExternalTrackKind.audio),
          s = ExternalMediaTrack.file('C:/fa.ass', ExternalTrackKind.subtitle);
      final saved = const ExternalTrackSnapshot().add(a).add(s),
          restored = ExternalTrackSnapshot.decode(jsonEncode(saved.toJson()));
      expect(restored.audioId, a.id);
      expect(restored.subtitleId, s.id);
      final removed = restored.remove(a.id);
      expect(removed.audioId, isNull);
      expect(removed.subtitleId, s.id);
      final relinked = removed.add(
        ExternalMediaTrack.file('D:/fa.flac', ExternalTrackKind.audio),
      );
      expect(relinked.audioId, isNot(a.id));
    },
  );
  test(
    'Corrupt records and selections pointing to another kind are rejected',
    () {
      for (final value in [null, '{', '[]', '{"version":9,"tracks":[]}']) {
        expect(ExternalTrackSnapshot.decode(value).tracks, isEmpty);
      }
      final audio = ExternalMediaTrack.file(
        'C:/audio.wav',
        ExternalTrackKind.audio,
      );
      final data = {
        'version': 1,
        'tracks': [
          audio.toJson(),
          {'path': 'bad\u0000', 'kind': 'subtitle'},
        ],
        'subtitle': audio.id,
      };
      final result = ExternalTrackSnapshot.decode(jsonEncode(data));
      expect(result.tracks.length, 1);
      expect(result.subtitleId, isNull);
    },
  );
  test(
    'Store is durable and isolated by account, title and logical episode',
    () async {
      ExternalMediaTrackStore store(
        String owner,
        String title,
        String episode,
      ) => ExternalMediaTrackStore(
        owner: owner,
        contentId: title,
        episodeId: episode,
      );
      final original = store('1', '42', 'season1-episode2');
      final snapshot = const ExternalTrackSnapshot().add(
        ExternalMediaTrack.file('C:/fa.srt', ExternalTrackKind.subtitle),
      );
      await original.save(snapshot);
      expect(
        (await store('1', '42', 'season1-episode2').load()).subtitleId,
        snapshot.subtitleId,
      );
      for (final other in [
        store('2', '42', 'season1-episode2'),
        store('1', '43', 'season1-episode2'),
        store('1', '42', 'season1-episode3'),
      ]) {
        expect((await other.load()).tracks, isEmpty);
      }
      expect(original.key, startsWith('external_tracks_v1_'));
      expect(original.key, isNot(startsWith('sub_')));
    },
  );
  test(
    'Import history remains bounded and unknown containers can be classified',
    () {
      var snapshot = const ExternalTrackSnapshot();
      for (var i = 0; i < 100; i++) {
        snapshot = snapshot.add(
          ExternalMediaTrack.file('C:/$i.srt', ExternalTrackKind.subtitle),
        );
      }
      expect(snapshot.tracks.length, 64);
      expect(snapshot.subtitleId, snapshot.tracks.last.id);
      var mixed = const ExternalTrackSnapshot().add(
        ExternalMediaTrack.file('C:/audio.wav', ExternalTrackKind.audio),
      );
      for (var i = 0; i < 64; i++) {
        mixed = mixed.add(
          ExternalMediaTrack.file('C:/$i.srt', ExternalTrackKind.subtitle),
        );
      }
      expect(
        mixed.audioId,
        isNull,
        reason: 'evicted references must not remain selected',
      );
      expect(externalTrackKind('C:/FA.ASS'), ExternalTrackKind.subtitle);
      expect(externalTrackKind('C:/fa.FLAC'), ExternalTrackKind.audio);
      expect(externalTrackKind('C:/unknown.container'), isNull);
    },
  );
}
