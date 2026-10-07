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
}
