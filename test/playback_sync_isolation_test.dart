import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';

http.Response reply(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    MbnSync.instance.clear();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => MbnSync.instance.clear());

  test(
    'bulk requests coalesce until the last playback lease releases',
    () async {
      var requests = 0;
      final auth = MbnAuth(
        client: MockClient((_) async {
          requests++;
          return reply({});
        }),
      )..token = 'qa';
      MbnSync.instance.configure(auth: auth);
      final release = MbnSync.instance.holdPlayback();
      final releaseSecond = MbnSync.instance.holdPlayback();
      for (var i = 0; i < 25; i++) {
        await MbnSync.instance.syncAll();
        await MbnSync.instance.pushAll();
      }
      expect(requests, 0);
      release();
      release();
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(requests, 0);
      releaseSecond();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(requests, 2); // One coalesced upload, then one fresh pull.
    },
  );

  test(
    'a slow pull finishing during playback cannot change local progress',
    () async {
      final started = Completer<void>(), response = Completer<void>();
      var gets = 0;
      final auth = MbnAuth(
        client: MockClient((_) async {
          if (++gets == 1) {
            started.complete();
            await response.future;
          }
          return reply({
            'progress': {
              'updated_at': 123,
              'payload': {'watch_pos_qa_one': 90000},
            },
          });
        }),
      )..token = 'qa';
      MbnSync.instance.configure(auth: auth);
      final pull = MbnSync.instance.syncAll();
      await started.future;
      final release = MbnSync.instance.holdPlayback();
      try {
        response.complete();
        await pull;
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('watch_pos_qa_one'), isNull);
        release();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(prefs.getInt('watch_pos_qa_one'), 90000);
        expect(gets, 2);
      } finally {
        release();
      }
    },
  );

  test(
    'pause checkpoint uploads only progress and reconciles after exit',
    () async {
      final batches = <Map>[];
      final auth = MbnAuth(
        client: MockClient((request) async {
          if (request.method == 'GET') return reply({});
          final data = jsonDecode(request.body)['data'] as Map;
          batches.add(data);
          return reply({
            for (final e in data.entries)
              e.key: {
                'updated_at': batches.length,
                'payload': e.key == 'progress'
                    ? {...e.value as Map, 'watch_pos_remote_one': 45000}
                    : e.value,
              },
          });
        }),
      )..token = 'qa';
      MbnSync.instance.configure(auth: auth);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('watch_pos_qa_one', 30000);
      final release = MbnSync.instance.holdPlayback();
      try {
        await MbnSync.instance.pushHistoryThrottled();
        expect(batches, isEmpty);
        await MbnSync.instance.pushProgressNow();
        expect(batches.single.keys, ['progress']);
        expect(prefs.getInt('watch_pos_remote_one'), isNull);
        expect(prefs.getBool('mbn_sync_dirty_progress'), true);
        release();
        await Future<void>.delayed(const Duration(milliseconds: 800));
        expect(prefs.getInt('watch_pos_qa_one'), 30000);
        expect(prefs.getInt('watch_pos_remote_one'), 45000);
        expect(prefs.getBool('mbn_sync_dirty_progress'), false);
        expect(prefs.getBool('mbn_sync_dirty_history'), false);
      } finally {
        release();
      }
    },
  );

  test(
    'a slow upload cannot apply a bulk response after playback starts',
    () async {
      final started = Completer<void>(), response = Completer<void>();
      var puts = 0;
      final auth = MbnAuth(
        client: MockClient((request) async {
          if (request.method == 'GET') return reply({});
          final data = jsonDecode(request.body)['data'] as Map;
          if (++puts == 1) {
            started.complete();
            await response.future;
          }
          return reply({
            'progress': {
              'updated_at': puts,
              'payload': {
                ...data['progress'] as Map,
                'watch_pos_remote_one': 45000,
              },
            },
          });
        }),
      )..token = 'qa';
      MbnSync.instance.configure(auth: auth);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('watch_pos_qa_one', 30000);
      final upload = MbnSync.instance.pushProgressNow();
      await started.future;
      final release = MbnSync.instance.holdPlayback();
      try {
        response.complete();
        await upload;
        expect(prefs.getInt('watch_pos_remote_one'), isNull);
        expect(prefs.getBool('mbn_sync_dirty_progress'), true);
        release();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(prefs.getInt('watch_pos_remote_one'), 45000);
        expect(prefs.getBool('mbn_sync_dirty_progress'), false);
      } finally {
        release();
      }
    },
  );
}
