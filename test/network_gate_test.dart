import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:mbnmovie/services/network_gate.dart';
import 'package:mbnmovie/services/mbn_auth.dart';

void main() {
  test('deduplicates reads and caps concurrent operations', () async {
    final gate = NetworkRequestGate(maxConcurrent: 2);
    final release = <Completer<void>>[];
    var active = 0, peak = 0, calls = 0;
    Future<int> op() async {
      calls++;
      active++;
      if (active > peak) peak = active;
      final done = Completer<void>();
      release.add(done);
      await done.future;
      active--;
      return 42;
    }

    final a = gate.run('same', op);
    final b = gate.run('same', op);
    final c = gate.run('other', op);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(peak, 2);
    for (final done in release) done.complete();
    expect(await a, 42);
    expect(await b, 42);
    expect(await c, 42);
  });

  test('identical reads share failures, which are never cached', () async {
    final gate = NetworkRequestGate(maxConcurrent: 2);
    final done = Completer<int>();
    var calls = 0;
    final readers = List.generate(
      100,
      (_) => gate.run('same', () {
        calls++;
        return done.future;
      }),
    );
    done.complete(42);
    expect(await Future.wait(readers), everyElement(42));
    expect(calls, 1);
    await expectLater(
      gate.run('same', () async => throw StateError('offline')),
      throwsStateError,
    );
    expect(await gate.run('same', () async => 7), 7);
  });

  test(
    'bounded FIFO rejects overflow and expires waiting work without sending it',
    () async {
      final gate = NetworkRequestGate(
        maxConcurrent: 1,
        maxPending: 1,
        queueTimeout: const Duration(milliseconds: 30),
      );
      final done = Completer<int>();
      final first = gate.run('first', () => done.future);
      var queuedCalls = 0;
      final queued = gate.run('queued', () async {
        queuedCalls++;
        return 2;
      });
      final expired = expectLater(
        queued,
        throwsA(isA<NetworkQueueException>()),
      );
      await expectLater(
        gate.run('overflow', () async => 3),
        throwsA(isA<NetworkQueueException>()),
      );
      await expired;
      expect(queuedCalls, 0);
      done.complete(1);
      expect(await first, 1);
      expect(await gate.run('queued', () async => 4), 4);
    },
  );

  test(
    'different operations respect FIFO; writes are never deduplicated',
    () async {
      final gate = NetworkRequestGate(maxConcurrent: 1);
      final release = Completer<void>();
      final order = <int>[];
      final first = gate.run('first', () async {
        order.add(1);
        await release.future;
      });
      final second = gate.run('write', () async => order.add(2), dedupe: false);
      final third = gate.run('write', () async => order.add(3), dedupe: false);
      expect(order, [1]);
      release.complete();
      await Future.wait([first, second, third]);
      expect(order, [1, 2, 3]);
    },
  );

  test(
    'HTTP response size is limited with and without Content-Length',
    () async {
      for (final declared in [true, false]) {
        final client = MockClient.streaming(
          (request, body) async => http.StreamedResponse(
            Stream.value(List.filled(9, 65)),
            200,
            contentLength: declared ? 9 : null,
          ),
        );
        await expectLater(
          sendBuffered(
            client,
            'GET',
            Uri.parse('https://example.com'),
            maxBytes: 8,
          ),
          throwsA(isA<http.ClientException>()),
        );
        client.close();
      }
    },
  );

  test(
    'stalled real HTTP body times out and the next request completes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final release = Completer<void>();
      server.listen((request) async {
        try {
          if (request.uri.path == '/stall') {
            request.response.add([65]);
            await request.response.flush();
            await release.future;
          } else {
            request.response.write('ok');
          }
          await request.response.close();
        } catch (_) {}
      });
      final client = IOClient(HttpClient());
      final origin = 'http://127.0.0.1:${server.port}';
      try {
        await expectLater(
          sendBuffered(
            client,
            'GET',
            Uri.parse('$origin/stall'),
            timeout: const Duration(milliseconds: 200),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(
          (await sendBuffered(client, 'GET', Uri.parse('$origin/ok'))).body,
          'ok',
        );
      } finally {
        release.complete();
        client.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'only 502/504 reads retry once; rate limits and authorization return immediately',
    () async {
      for (final status in [401, 403, 429, 500, 502, 503, 504]) {
        var calls = 0;
        final result = await readWithRetry(() async {
          calls++;
          return http.Response('{}', status);
        });
        expect(result.statusCode, status);
        expect(calls, [502, 504].contains(status) ? 2 : 1);
      }
      var calls = 0;
      await readWithRetry(() async {
        calls++;
        return http.Response('{}', 502, headers: {'retry-after': '60'});
      });
      expect(calls, 1);
    },
  );

  test(
    'an earlier login response cannot apply even if its token is restored',
    () async {
      final response = Completer<http.Response>();
      final account = MbnAuth(client: MockClient((_) => response.future));
      account.token = 'old';
      final request = account.getJson('/api/me');
      final rejected = expectLater(request, throwsA(isA<MbnAuthException>()));
      await Future<void>.delayed(Duration.zero);
      account.token = null;
      account.token = 'old';
      response.complete(http.Response('{"user":{}}', 200));
      await rejected;
    },
  );

  test('failed account writes send once and preserve the status', () async {
    var calls = 0;
    final account = MbnAuth(
      client: MockClient((_) async {
        calls++;
        return http.Response('{"error":"busy"}', 502);
      }),
    );
    await expectLater(
      account.putJson('/api/sync', {'data': {}}),
      throwsA(
        isA<MbnAuthException>().having((e) => e.statusCode, 'status', 502),
      ),
    );
    expect(calls, 1);
  });
}
