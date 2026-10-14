import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/core/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LastWatch _lastAt(int positionMs, int durationMs) => LastWatch(
  contentId: 'c1',
  title: 'فیلم تست',
  episodeId: 'g1',
  episodeName: 'قسمت ۱',
  fileUrl: 'https://cdn.invalid/v.mp4',
  positionMs: positionMs,
  durationMs: durationMs,
  updatedAtMs: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MbnSync.instance.clear();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => MbnSync.instance.clear());

  test('watch progress round-trips and is resumable mid-episode', () async {
    final store = WatchProgressStore();
    expect(await store.load(contentId: 'c1', episodeId: 'e1'), isNull);

    await store.save(
      contentId: 'c1',
      episodeId: 'e1',
      position: const Duration(minutes: 12, seconds: 30),
      duration: const Duration(minutes: 24),
    );
    final saved = await store.load(contentId: 'c1', episodeId: 'e1');
    expect(saved, isNotNull);
    expect(saved!.position, const Duration(minutes: 12, seconds: 30));
    expect(saved.isResumable, isTrue);

    await store.clear(contentId: 'c1', episodeId: 'e1');
    expect(await store.load(contentId: 'c1', episodeId: 'e1'), isNull);
  });

  test(
    'finished episodes keep their final position and watched marker',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c1',
        episodeId: 'e9',
        position: const Duration(minutes: 23, seconds: 55),
        duration: const Duration(minutes: 24),
      );
      final saved = await store.load(contentId: 'c1', episodeId: 'e9');
      expect(saved, isNotNull);
      expect(saved!.position, const Duration(minutes: 23, seconds: 55));
      expect(saved.watched, isTrue);
      expect(saved.isResumable, isFalse);
    },
  );

  test(
    'next episode action marks watched without losing resume time',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c1',
        episodeId: 'e3',
        position: const Duration(minutes: 22),
        duration: const Duration(minutes: 24),
        markWatched: true,
      );
      final saved = await store.load(contentId: 'c1', episodeId: 'e3');
      expect(saved, isNotNull);
      expect(saved!.position, const Duration(minutes: 22));
      expect(saved.watched, isTrue);
      expect(saved.isResumable, isTrue);
    },
  );

  test('first seconds are not offered as resumable', () async {
    final store = WatchProgressStore();
    await store.save(
      contentId: 'c1',
      episodeId: 'e2',
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 24),
    );
    final saved = await store.load(contentId: 'c1', episodeId: 'e2');
    expect(saved, isNotNull);
    expect(saved!.isResumable, isFalse);
  });

  test('stopping in the last five minutes is almost watched', () async {
    final store = WatchProgressStore();
    await store.save(
      contentId: 'c1',
      episodeId: 'e4',
      position: const Duration(minutes: 19),
      duration: const Duration(minutes: 24),
    );
    final saved = await store.load(contentId: 'c1', episodeId: 'e4');
    expect(saved, isNotNull);
    expect(saved!.almostWatched, isTrue);
    expect(saved.watched, isFalse);
  });

  test('last watch round-trips the exact exit point', () async {
    final store = LastWatchStore();
    expect(await store.load(), isNull);

    await store.save(_lastAt(750000, 1440000));
    final last = await store.load();
    expect(last, isNotNull);
    expect(last!.title, 'فیلم تست');
    expect(last.position, const Duration(milliseconds: 750000));
    expect(last.isResumable, isTrue);

    await store.clear();
    expect(await store.load(), isNull);
  });

  test('finished or barely-started exits are never offered', () async {
    final store = LastWatchStore();
    // Finished: 5 seconds before a 24-minute episode ends.
    await store.save(_lastAt(1435000, 1440000));
    expect(await store.load(), isNull);
    // Barely started: 5 seconds in.
    await store.save(_lastAt(5000, 1440000));
    expect(await store.load(), isNull);
  });

  test('last watch slot round-trips a single exit point', () async {
    const store = LastWatchStore();
    await store.save(_lastAt(750000, 1440000));

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.contentId, 'c1');

    await store.clear();
    expect(await store.load(), isNull);
  });
  test(
    'truncated checkpoint cannot erase known runtime or mark watched',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c',
        episodeId: 'e',
        position: const Duration(minutes: 20),
        duration: const Duration(minutes: 50),
      );
      await store.save(
        contentId: 'c',
        episodeId: 'e',
        position: const Duration(seconds: 55),
        duration: const Duration(seconds: 61),
        markWatched: true,
      );
      final saved = (await store.load(contentId: 'c', episodeId: 'e'))!;
      expect(saved.duration, const Duration(minutes: 50));
      expect(saved.position, const Duration(minutes: 20));
      expect(saved.watched, isFalse);
    },
  );

  test(
    'genuine short clips still complete and unknown durations retain runtime',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c',
        episodeId: 'clip',
        position: const Duration(seconds: 55),
        duration: const Duration(seconds: 61),
      );
      expect(
        (await store.load(contentId: 'c', episodeId: 'clip'))!.watched,
        isTrue,
      );
      await store.save(
        contentId: 'c',
        episodeId: 'long',
        position: const Duration(minutes: 20),
        duration: const Duration(minutes: 50),
      );
      await store.save(
        contentId: 'c',
        episodeId: 'long',
        position: const Duration(minutes: 21),
        duration: Duration.zero,
      );
      final saved = (await store.load(contentId: 'c', episodeId: 'long'))!;
      expect(saved.duration, const Duration(minutes: 50));
      expect(saved.position, const Duration(minutes: 21));
      expect(saved.watched, isFalse);
    },
  );
  test(
    'pause checkpoint uploads newest episode and clears completed continuation',
    () async {
      const store = LastWatchStore();
      LastWatch checkpoint(String episode, int position) => LastWatch(
        contentId: 'c',
        title: 'Audit',
        episodeId: episode,
        episodeName: episode,
        fileUrl: 'https://example.com/$episode.mp4',
        positionMs: position,
        durationMs: 3000000,
        updatedAtMs: 1,
      );
      await store.save(checkpoint('e1', 120000));
      Map? upload;
      final auth = MbnAuth(
        client: MockClient((request) async {
          final data = jsonDecode(request.body)['data'] as Map;
          upload = data;
          return http.Response(
            jsonEncode({
              for (final row in data.entries)
                row.key: {'payload': row.value, 'updated_at': 1000},
            }),
            200,
          );
        }),
      )..token = 'test';
      MbnSync.instance.configure(auth: auth);
      await WatchProgressStore().save(
        contentId: 'c',
        episodeId: 'e3',
        position: const Duration(minutes: 20),
        duration: const Duration(minutes: 50),
        lastWatch: checkpoint('e3', 1200000),
      );
      await MbnSync.instance.pushProgressNow();
      final last =
          jsonDecode(upload!['progress']['watch_last_v1'] as String) as Map;
      expect(last['episodeId'], 'e3');
      expect(last['positionMs'], 1200000);
      expect(upload!['progress']['watch_pos_c_e3'], 1200000);
      await WatchProgressStore().save(
        contentId: 'c',
        episodeId: 'e3',
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 50),
        lastWatch: checkpoint('e3', 3000000),
      );
      expect(await store.load(), isNull);
    },
  );
}
