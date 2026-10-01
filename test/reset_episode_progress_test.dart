import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/watch_progress.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/services/mbn_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => MbnSync.instance.clear());
  test('episode reset removes all quality identities and matching last watch, preserving siblings', () async {
    final last = jsonEncode({'contentId':'c','episodeId':'raw','fileUrl':'https://cdn/one',
      'positionMs':1200000,'durationMs':1800000,'updatedAtMs':1});
    SharedPreferences.setMockInitialValues({'watch_pos_c_group':1200000,
      'watch_dur_c_group':1800000,'watch_done_c_group':true,'watch_time_c_group':1,
      'watch_pos_c_raw':1200000,'watch_pos_c_hd':1200000,'watch_pos_c_next':600000,
      'watch_last_v1':last});
    final calls = <String>[];
    final client = MbnAuth(client:MockClient((r) async {
      calls.add(r.url.path);
      if (r.url.path.endsWith('reset-episode')) {
        expect(jsonDecode(r.body)['episode_ids'],containsAll(['group','raw','hd']));
        return http.Response('{}',200);
      }
      final payload=jsonDecode(r.body)['data']['progress'];
      expect(payload.containsKey('watch_pos_c_group'),false);
      expect(payload['watch_pos_c_next'],600000);
      return http.Response(jsonEncode({'progress':{'updated_at':1,'payload':payload}}),200);
    }))..token='test';
    MbnSync.instance.configure(auth:client);
    expect(await WatchProgressStore().resetEpisode(contentId:'c',episodeIds:{'group','raw','hd'},fileUrls:{'https://cdn/one'}),true);
    final prefs=await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k)=>k.startsWith('watch_')),{'watch_pos_c_next'});
    expect(calls,['/api/sync/progress/reset-episode','/api/sync']);
  });
  test('offline reset is retained before a later pull and preserves unrelated last watch', () async {
    SharedPreferences.setMockInitialValues({'watch_pos_c_group':50000,
      'watch_last_v1':jsonEncode({'contentId':'other','episodeId':'e','fileUrl':'https://cdn/other','positionMs':60000,'durationMs':100000})});
    MbnSync.instance.clear();
    expect(await WatchProgressStore().resetEpisode(contentId:'c',episodeIds:{'group'},fileUrls:{}),false);
    final prefs=await SharedPreferences.getInstance();
    expect(prefs.getInt('watch_pos_c_group'),null);
    expect(prefs.getString('watch_last_v1'),isNotNull);
    expect(prefs.getStringList('mbn_progress_resets_v1'),hasLength(1));
  });
}
