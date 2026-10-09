import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/watch_progress.dart';
import 'package:mbnmovie/core/player_preferences.dart';
import 'package:mbnmovie/core/external_player_link.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/widgets/audio_sync_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    MbnSync.instance.clear();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => MbnSync.instance.clear());
  test(
    'manual status survives offline and clears quality variants and continue watch',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c',
        episodeId: 'g',
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 2),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('watch_pos_c_raw', 10000);
      expect(
        await store.setStatus(
          contentId: 'c',
          episodeId: 'g',
          episodeIds: {'g', 'raw'},
          fileUrls: {},
          status: WatchStatus.partial,
        ),
        false,
      );
      expect(
        (await store.load(contentId: 'c', episodeId: 'g'))!.manualStatus,
        WatchStatus.partial,
      );
      expect(
        (await store.load(contentId: 'c', episodeId: 'g'))!.positionMs,
        60000,
      );
      expect(await store.load(contentId: 'c', episodeId: 'raw'), isNull);
      expect(prefs.getStringList('mbn_progress_resets_v1'), hasLength(1));
      await store.setStatus(
        contentId: 'c',
        episodeId: 'g',
        episodeIds: {'g'},
        fileUrls: {},
        status: WatchStatus.watched,
      );
      expect((await store.load(contentId: 'c', episodeId: 'g'))!.watched, true);
      await store.setStatus(
        contentId: 'c',
        episodeId: 'g',
        episodeIds: {'g'},
        fileUrls: {},
        status: WatchStatus.unwatched,
      );
      expect(
        (await store.load(contentId: 'c', episodeId: 'g'))!.isResumable,
        false,
      );
      await store.save(
        contentId: 'c',
        episodeId: 'g',
        position: const Duration(seconds: 35),
        duration: const Duration(minutes: 2),
      );
      expect(
        (await store.load(contentId: 'c', episodeId: 'g'))!.manualStatus,
        isNull,
      );
    },
  );
  test(
    'online status uses scoped endpoint and server timestamp before upload',
    () async {
      final paths = <String>[];
      int? serverTime;
      final client = MbnAuth(
        client: MockClient((r) async {
          paths.add(r.url.path);
          final body = jsonDecode(r.body);
          if (r.url.path.endsWith('set-status')) {
            expect(body['status'], 'watched');
            expect(body['episode_ids'], containsAll(['g', 'raw']));
            serverTime = body['written_at_ms'] + 10;
            return http.Response(
              jsonEncode({
                'progress': {
                  'payload': {'watch_time_c_g': serverTime},
                },
              }),
              200,
            );
          }
          final data = body['data']['progress'];
          expect(data['watch_status_c_g'], 'watched');
          expect(data['watch_time_c_g'], serverTime);
          return http.Response(
            jsonEncode({
              'progress': {'payload': data, 'updated_at': 1},
            }),
            200,
          );
        }),
      )..token = 'test';
      MbnSync.instance.configure(auth: client);
      expect(
        await WatchProgressStore().setStatus(
          contentId: 'c',
          episodeId: 'g',
          episodeIds: {'g', 'raw'},
          fileUrls: {},
          status: WatchStatus.watched,
        ),
        true,
      );
      expect(paths, ['/api/sync/progress/set-status', '/api/sync']);
    },
  );
  test('audio calibration stays on device and clamps invalid range', () async {
    expect(await PlaybackPreferenceStore.audioDelay(), 0);
    await PlaybackPreferenceStore.setAudioDelay(-.25);
    expect(await PlaybackPreferenceStore.audioDelay(), -.25);
    await PlaybackPreferenceStore.setAudioDelay(20);
    expect(await PlaybackPreferenceStore.audioDelay(), 3);
  });
  test(
    'external launch preserves signed URL and rejects unsafe Windows handoffs',
    () {
      Uri? link(String platform, String url, {String player = 'vlc'}) =>
          externalPlayerLink(
            player: player,
            platform: platform,
            url: url,
            title: 'عنوان',
            appScheme: 'test-player',
          );
      const url = 'https://anime.mbnpro.ir/api/web/media?ticket=abc%2Bxyz';
      expect(link('windows', url)!.queryParameters['url'], url);
      expect(link('ios', url)!.scheme, 'vlc-x-callback');
      expect(link('ios', url, player: 'mxPlayer'), isNull);
      for (final bad in [
        'file:///etc/passwd',
        'https://evil.invalid/api/web/media?ticket=x',
        'https://user@anime.mbnpro.ir/api/web/media?ticket=x',
      ]) {
        expect(link('windows', bad), isNull);
      }
      expect(
        link('android', url, player: 'mxPlayerPro')!.toString(),
        contains('com.mxtech.videoplayer.pro'),
      );
    },
  );
  for (final size in [const Size(320, 210), const Size(844, 180)]) {
    testWidgets('audio slider fits $size and applies only when drag ends', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final values = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AudioSyncControl(
                  initial: 0,
                  onApply: (v) async {
                    values.add(v);
                  },
                ),
              ],
            ),
          ),
        ),
      );
      final slider = find.byType(Slider);
      final position = tester.getCenter(slider);
      final gesture = await tester.startGesture(position);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(values, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(values, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
