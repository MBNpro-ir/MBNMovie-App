import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/services/session_watch.dart';

void main() {
  test('a blocked sync never delays session revocation', () async {
    final events = StreamController<List<int>>();
    final blockedSync = Completer<void>();
    final started = Completer<void>(), revoked = Completer<void>();
    var syncCalls = 0;
    final watch = SessionWatch(
      (_) async => revoked.complete(),
      onSync: () async {
        syncCalls++;
        if (!started.isCompleted) started.complete();
        await blockedSync.future;
      },
      clientFactory: () => MockClient.streaming(
        (request, body) async => http.StreamedResponse(events.stream, 200),
      ),
    );
    try {
      watch.track('qa', 'https://example.invalid');
      events.add(
        utf8.encode('data: {"state":"active","sync_revision":"1"}\n\n'),
      );
      await started.future.timeout(const Duration(seconds: 1));
      for (var i = 2; i < 20; i++) {
        events.add(
          utf8.encode('data: {"state":"active","sync_revision":"$i"}\n\n'),
        );
      }
      events.add(utf8.encode('data: {"state":"revoked"}\n\n'));
      await revoked.future.timeout(const Duration(seconds: 1));
      expect(blockedSync.isCompleted, false);
      expect(syncCalls, 1);
    } finally {
      watch.dispose();
      blockedSync.complete();
      await events.close();
    }
  });
}
