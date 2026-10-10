import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'rapid sync changes coalesce and the last write contains the latest preferences',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final bodies = <String>[];
      final server = MbnAuth(
        client: MockClient((request) async {
          bodies.add(request.body);
          if (bodies.length == 1) {
            started.complete();
            await release.future;
          }
          final data = jsonDecode(request.body)['data'] as Map;
          return http.Response(
            jsonEncode({
              for (final entry in data.entries)
                entry.key: {'payload': entry.value, 'updated_at': 2000},
            }),
            200,
          );
        }),
      )..token = 'tok';
      MbnSync.instance.configure(auth: server);
      try {
        final first = MbnSync.instance.pushAll();
        await started.future;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('player_rate', 1.75);
        final pending = List.generate(20, (_) => MbnSync.instance.pushAll());
        release.complete();
        await Future.wait([first, ...pending]);
        expect(bodies.length, 2);
        expect(bodies.last, contains('"player_rate":1.75'));
      } finally {
        if (!release.isCompleted) release.complete();
        MbnSync.instance.clear();
      }
    },
  );

  test(
    'remote merge is applied locally without losing an edit made during upload',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('player_rate', 1.0);
      var requests = 0;
      final server = MbnAuth(
        client: MockClient((request) async {
          final data = jsonDecode(request.body)['data'] as Map;
          requests++;
          if (requests == 1) {
            started.complete();
            await release.future;
          }
          final preferences = Map<String, dynamic>.from(
            data['preferences'] as Map,
          );
          final platform = preferences.keys.first;
          preferences[platform] = {
            ...(preferences[platform] as Map),
            'sub_size': 30.0,
          };
          return http.Response(
            jsonEncode({
              for (final entry in data.entries)
                entry.key: {
                  'payload': entry.key == 'preferences'
                      ? preferences
                      : entry.value,
                  'updated_at': requests + 1000,
                },
            }),
            200,
          );
        }),
      )..token = 'tok';
      MbnSync.instance.configure(auth: server);
      try {
        final first = MbnSync.instance.pushAll();
        await started.future;
        await prefs.setDouble('player_rate', 1.75);
        final second = MbnSync.instance.pushAll();
        release.complete();
        await Future.wait([first, second]);
        expect(prefs.getDouble('player_rate'), 1.75);
        expect(prefs.getDouble('sub_size'), 30.0);
        expect(prefs.getBool('mbn_sync_dirty_preferences'), false);
        expect(requests, 2);
      } finally {
        if (!release.isCompleted) release.complete();
        MbnSync.instance.clear();
      }
    },
  );

  test('a delayed pull cannot replace an edit queued while offline', () async {
    final started = Completer<void>(), release = Completer<void>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_rate', 1.0);
    final server = MbnAuth(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          started.complete();
          await release.future;
          return http.Response(
            jsonEncode({
              'preferences': {
                'payload': {
                  'windows': {'player_rate': 0.5},
                },
                'updated_at': 1000,
              },
            }),
            200,
          );
        }
        throw http.ClientException('offline');
      }),
    )..token = 'tok';
    MbnSync.instance.configure(auth: server);
    try {
      final pull = MbnSync.instance.syncAll();
      await started.future;
      await prefs.setDouble('player_rate', 1.75);
      await MbnSync.instance.pushPreferences();
      release.complete();
      await pull;
      expect(prefs.getDouble('player_rate'), 1.75);
      expect(prefs.getBool('mbn_sync_dirty_preferences'), true);
    } finally {
      if (!release.isCompleted) release.complete();
      MbnSync.instance.clear();
    }
  });
}
