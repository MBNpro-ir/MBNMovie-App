import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/core/app_platform.dart';
import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/services/mbn_auth.dart';

void main() {
  test(
    'account requests describe native platform and television explicitly',
    () async {
      final seen = <http.Request>[];
      final transport = MockClient((request) async {
        seen.add(request);
        return http.Response('{}', 200);
      });
      final api = MbnAuth(client: transport, baseUrl: 'https://example.test');
      addTearDown(() => isAndroidTv = false);
      await api.postJson('/api/auth/login', {});
      await api.getJson('/api/me');
      await api.putJson('/api/sync', {});
      expect(
        seen.map((r) => r.headers['X-MBN-Platform']),
        everyElement(Platform.operatingSystem),
      );
      isAndroidTv = true;
      await api.getJson('/api/me');
      expect(seen.last.headers['X-MBN-Platform'], 'android_tv');
    },
  );
}
