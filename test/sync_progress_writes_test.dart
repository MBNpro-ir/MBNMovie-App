import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';

class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore(super.data) : super.withData();
  final writes = <String>[];
  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writes.add(key);
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unchanged remote history does not rewrite thousands of progress keys',
    () async {
      final progress = {for (var i = 0; i < 5000; i++) 'watch_pos_qa_$i': i};
      SharedPreferences.setMockInitialValues({});
      final store = _CountingStore({
        for (final e in progress.entries) 'flutter.${e.key}': e.value,
        'flutter.watch_pos_deleted_one': 1,
        'flutter.watch_pos_malformed_one': 5,
      });
      SharedPreferencesStorePlatform.instance = store;
      final auth = MbnAuth(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'progress': {
                'updated_at': 2000,
                'payload': {
                  ...progress,
                  'watch_pos_qa_1': 1234,
                  'watch_pos_malformed_one': null,
                },
              },
            }),
            200,
          ),
        ),
      )..token = 'qa';
      MbnSync.instance.configure(auth: auth);
      try {
        await MbnSync.instance.syncAll();
        final progressWrites = store.writes
            .where((k) => k.startsWith('flutter.watch_'))
            .toList();
        expect(progressWrites, ['flutter.watch_pos_qa_1']);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('watch_pos_qa_1'), 1234);
        expect(prefs.containsKey('watch_pos_deleted_one'), false);
        expect(prefs.getInt('watch_pos_malformed_one'), 5);
      } finally {
        MbnSync.instance.clear();
        SharedPreferences.setMockInitialValues({});
      }
    },
  );
}
