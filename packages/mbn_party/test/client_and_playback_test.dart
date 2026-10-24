import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbn_party/mbn_party.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Bootstrap refresh preserves pending message event cursor', (
    tester,
  ) async {
    var cursor = 10;
    final afters = <String?>[];
    final client = PartyClient(
      baseUrl: 'http://test.local',
      app: 'movie',
      token: () => 'token',
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('updates')) {
          afters.add(r.url.queryParameters['after']);
          return http.Response('{"cursor":10,"events":[]}', 200);
        }
        return http.Response(
          jsonEncode({
            'me': {'id': 1},
            'rooms': [],
            'friends': [],
            'requests': [],
            'sessions': [],
            'cursor': cursor,
          }),
          200,
        );
      }),
    );
    await client.refresh();
    cursor = 20;
    await client.refresh();
    final release = client.watch();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(afters, [
      '10',
    ], reason: 'refresh cannot skip messages arriving before the next poll');
    release();
    client.dispose();
  });
  test('Room pagination survives refresh with filtered first page', () async {
    final client = PartyClient(
      baseUrl: 'http://test.local',
      app: 'movie',
      token: () => 'token',
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/rooms')) {
          return http.Response(
            '{"rooms":[{"id":"older","kind":"group"}],"next_offset":200,"has_more":false}',
            200,
          );
        }
        return http.Response(
          '{"me":{"id":1},"rooms":[{"id":"first","kind":"group"}],"friends":[],"requests":[],"sessions":[],"has_more_rooms":true}',
          200,
        );
      }),
    );
    await client.refresh();
    await client.moreRooms();
    await client.refresh();
    expect(client.rooms.map((r) => r['id']), ['first', 'older']);
    expect(client.hasMoreRooms, false);
    client.dispose();
  });
  test(
    'Concurrent bootstrap is coalesced and request retry preserves nonce',
    () async {
      var calls = 0;
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final client = PartyClient(
        baseUrl: 'http://test.local',
        app: 'anime',
        token: () => 'token',
        httpClient: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('bootstrap')) {
            calls++;
            return pending.future;
          }
          return http.Response('{}', 200);
        }),
      );
      final a = client.refresh(), b = client.refresh();
      expect(identical(a, b), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      pending.complete(
        http.Response(
          jsonEncode({
            'me': {'id': 1},
            'friends': [],
            'requests': [],
            'rooms': [],
            'sessions': [],
            'cursor': 0,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await a;
      await client.sendText('room', 'سلام Android', messageNonce: 'retry_0001');
      await client.sendText('room', 'سلام Android', messageNonce: 'retry_0001');
      expect(requests.last.url.queryParameters['app'], 'anime');
      expect(requests.last.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(requests.last.body)['nonce'], 'retry_0001');
      expect(jsonDecode(requests.last.body)['body'], 'سلام Android');
      client.dispose();
    },
  );

  test(
    'Response from previous credential cannot update another account',
    () async {
      String? token = 'old';
      final pending = Completer<http.Response>();
      final client = PartyClient(
        baseUrl: 'http://test.local',
        app: 'movie',
        token: () => token,
        httpClient: MockClient((r) => pending.future),
      );
      final result = client.call('GET', '/api/party/bootstrap');
      token = 'new';
      pending.complete(http.Response('{"me":{"id":99}}', 200));
      await expectLater(result, throwsA(isA<PartyException>()));
      expect(client.me, isEmpty);
      client.dispose();
    },
  );

  testWidgets(
    'Scheduled start, no echo, offline continuity, drift limit and disposal',
    (tester) async {
      var now = 100000,
          playing = false,
          position = 0,
          plays = 0,
          seeks = 0,
          pauses = 0;
      var speed = 1.0, offline = false;
      final commands = <String>[],
          playChanges = StreamController<bool>.broadcast(sync: true),
          positionChanges = StreamController<Duration>.broadcast(sync: true),
          rateChanges = StreamController<double>.broadcast(sync: true);
      var session = <String, dynamic>{
        'id': 'session1',
        'state': 'waiting',
        'version': 1,
        'position_ms': 30000,
        'anchor_ms': now,
        'duration_ms': 600000,
        'rate': 1.0,
        'host_id': 1,
        'participants': [],
      };
      final client = PartyClient(
        baseUrl: 'http://test.local',
        app: 'movie',
        token: () => 'token',
        clock: PartyClock(localNow: () => now),
        httpClient: MockClient((r) async {
          if (offline) throw Exception('offline');
          if (r.url.path.endsWith('bootstrap')) {
            return http.Response(
              jsonEncode({
                'me': {'id': 1},
                'rooms': [],
                'friends': [],
                'requests': [],
                'sessions': [],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.method == 'POST') {
            final data = jsonDecode(r.body) as Map;
            final action = '${data['action']}';
            commands.add(action);
            if (action == 'ready') {
              session = {
                ...session,
                'state': 'playing',
                'version': 2,
                'anchor_ms': now + 2000,
              };
            }
            if (action == 'pause') {
              session = {
                ...session,
                'state': 'paused',
                'version': 3,
                'position_ms': data['position_ms'],
                'anchor_ms': now,
                'actor': {'name': 'مریم'},
              };
            }
          }
          return http.Response(
            jsonEncode({
              'session': {...session, 'server_now_ms': now},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final controller = WatchPartyController(
        client: client,
        sessionId: 'session1',
        playback: PartyPlayback(
          position: () => Duration(milliseconds: position),
          duration: () => const Duration(minutes: 10),
          playing: () => playing,
          buffering: () => false,
          rate: () => speed,
          seek: (v) async {
            seeks++;
            position = v.inMilliseconds;
            positionChanges.add(v);
          },
          play: () async {
            plays++;
            playing = true;
            playChanges.add(true);
          },
          pause: () async {
            pauses++;
            playing = false;
            playChanges.add(false);
          },
          setRate: (v) async {
            speed = v;
            rateChanges.add(v);
          },
          playingChanges: playChanges.stream,
          positionChanges: positionChanges.stream,
          rateChanges: rateChanges.stream,
        ),
      );
      await controller.join();
      await controller.join();
      expect(client.activePlayers, 1);
      await controller.ready();
      expect(playing, isFalse);
      expect(position, 30000);
      now += 1990;
      await tester.pump(const Duration(milliseconds: 1990));
      expect(plays, 0);
      now += 20;
      await tester.pump(const Duration(milliseconds: 20));
      expect(plays, 1);
      expect(playing, isTrue);
      expect(
        commands.where((c) => c == 'play'),
        isEmpty,
        reason: 'remote start must not echo a local command',
      );
      final previousSeeks = seeks;
      now += 1500;
      position = 31510;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(seeks, previousSeeks);
      playing = false;
      playChanges.add(false);
      await tester.pump();
      expect(commands.where((c) => c == 'pause').length, 1);
      expect(controller.status, contains('مریم'));
      final pausedSnapshot = Map<String, dynamic>.from(session);
      session = {...session, 'state': 'playing', 'version': 2};
      now += 2000;
      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.version,
        3,
        reason: 'stale heartbeat cannot replace a newer pause',
      );
      expect(playing, isFalse);
      session = pausedSnapshot;
      final previousPauses = pauses;
      offline = true;
      now += 4000;
      await tester.pump(const Duration(seconds: 4));
      expect(controller.connected, isFalse);
      expect(pauses, previousPauses);
      controller.dispose();
      expect(client.activePlayers, 0);
      final count = commands.length;
      await tester.pump(const Duration(seconds: 15));
      expect(commands.length, count);
      client.dispose();
      await playChanges.close();
      await positionChanges.close();
      await rateChanges.close();
    },
  );

  testWidgets('Persian inbox works at phone width and desktop width', (
    tester,
  ) async {
    final me = {'id': 1, 'name': 'من', 'public_id': 'MBN-0123456789'},
        peer = {'id': 2, 'name': 'مریم Android', 'public_id': 'MBN-9876543210'};
    final client = PartyClient(
      baseUrl: 'http://test.local',
      app: 'movie',
      token: () => 'token',
      httpClient: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'me': me,
            'friends': [peer],
            'requests': [],
            'sessions': [],
            'cursor': 0,
            'rooms': [
              {
                'id': 'room1',
                'kind': 'direct',
                'members': [
                  {'user_id': 1, 'user': me},
                  {'user_id': 2, 'user': peer},
                ],
                'permissions': {'can_message': true},
                'last_message': {
                  'kind': 'text',
                  'body': 'سلام با Android',
                  'id': 1,
                },
                'unread': 1,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    for (final width in [320.0, 390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: PartyScreen(client: client),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('MBN-0123456789'), findsOneWidget);
      expect(find.text('مریم Android'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    client.dispose();
  });
}
