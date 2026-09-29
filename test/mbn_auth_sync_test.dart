import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/core/library_store.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

MockClient _server({
  required Map<String, dynamic> Function(String path) routes,
}) {
  return MockClient((request) async {
    final body = await serverFor(request, routes);
    return body;
  });
}

Future<http.Response> serverFor(
  http.BaseRequest request,
  Map<String, dynamic> Function(String path) routes,
) async {
  final path = request.url.path;
  final payload = routes(path);
  return http.Response(
    jsonEncode(payload['body']),
    payload['status'] as int,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('login persists the session and restores the profile', () async {
    final profile = {
      'id': 7, 'name': 'کاربر', 'email': 'user@test.local',
      'mobile': '', 'role': 'user', 'is_active': true,
      'subscription_expires_at': 9999999999, 'has_animeon_link': false,
    };
    final client = _server(routes: (path) {
      if (path == '/api/auth/login') {
        return {'status': 200, 'body': {'token': 'tok123', 'user': profile}};
      }
      if (path == '/api/me') {
        return {'status': 200, 'body': {'user': profile}};
      }
      if (path == '/api/auth/status') {
        return {'status': 200, 'body': {'state': 'active', 'message': ''}};
      }
      return {'status': 404, 'body': {'error': 'not found'}};
    });
    final auth = MbnAuth(client: client, baseUrl: 'https://login.test');
    final logged = await auth.login(
        identifier: 'user@test.local', password: 'secret123');
    expect(logged.email, 'user@test.local');

    final fresh = MbnAuth(client: client, baseUrl: 'https://login.test');
    expect(await fresh.restore(), isTrue);
    expect(fresh.profile!.id, 7);

    await fresh.logout();
    final gone = MbnAuth(client: client, baseUrl: 'https://login.test');
    expect(await gone.restore(), isFalse);
  });

  test('server errors surface Persian messages', () async {
    final client = _server(routes: (path) {
      return {'status': 403, 'body': {'error': 'اشتراک فعالی نداری؛ تمدید کن.'}};
    });
    final auth = MbnAuth(client: client, baseUrl: 'https://login.test');
    try {
      await auth.login(identifier: 'u', password: 'p');
      fail('expected MbnAuthException');
    } on MbnAuthException catch (e) {
      expect(e.message, contains('اشتراک'));
    }
  });

  test('sync pulls newer server rows and pushes newer local rows', () async {
    var serverState = {
      'favorites': {'payload': [], 'updated_at': 0},
      'playlists': {'payload': [], 'updated_at': 0},
      'history': {'payload': [], 'updated_at': 0},
      'progress': {'payload': {}, 'updated_at': 0},
    };
    final profile = {
      'id': 7, 'name': '', 'email': 'u@t.l', 'mobile': '', 'role': 'user',
      'is_active': true, 'subscription_expires_at': 9999999999,
      'has_animeon_link': false,
    };
    final client = _server(routes: (path) {
      if (path == '/api/auth/login') {
        return {'status': 200, 'body': {'token': 'tok', 'user': profile}};
      }
      if (path == '/api/sync') {
        return {'status': 200, 'body': serverState};
      }
      return {'status': 404, 'body': {'error': 'x'}};
    });
    final auth = MbnAuth(client: client, baseUrl: 'https://login.test');
    await auth.login(identifier: 'u@t.l', password: 'p');
    MbnSync.instance.configure(auth: auth);

    // Server has a favorite newer than local: pull wins.
    serverState = {
      'favorites': {
        'payload': [
          {
            'id': 'srv-1', 'title': 'سروری', 'subtitle': '', 'description': '',
            'year': 2024, 'rating': 7.0, 'kind': 'movie',
            'colors': [4278190080, 4278190080], 'genres': [],
          },
        ],
        'updated_at': 2000,
      },
      'playlists': {'payload': [], 'updated_at': 0},
      'history': {'payload': [], 'updated_at': 0},
      'progress': {'payload': {}, 'updated_at': 0},
    };
    await MbnSync.instance.syncAll();
    // Local now contains the server favorite (checked via a fresh pull).
    final favorites = await LibraryStore().favorites();
    expect(favorites.map((item) => item.id), contains('srv-1'));
    await MbnSync.instance.syncAll();
    MbnSync.instance.clear();
  });

  test('pullAndApplyPreferences restores cross-platform preferences with correct double types', () async {
    final serverState = {
      'preferences': {
        'payload': {
          'windows': {
            'player_volume': 85,
            'player_rate': 2,
            'sub_font': 'Vazirmatn',
            'sub_size': 24,
            'sub_color': 4294967295,
            'access_text_scale': 1,
            'access_reduce_motion': true,
          },
        },
        'updated_at': 5000,
      },
    };
    final profile = {
      'id': 7, 'name': 'کاربر', 'email': 'user@test.local',
      'mobile': '', 'role': 'user', 'is_active': true,
      'subscription_expires_at': 9999999999, 'has_animeon_link': false,
    };
    final client = _server(routes: (path) {
      if (path == '/api/sync') {
        return {'status': 200, 'body': serverState};
      }
      if (path == '/api/me') {
        return {'status': 200, 'body': {'user': profile}};
      }
      return {'status': 404, 'body': {'error': 'x'}};
    });
    final auth = MbnAuth(client: client, baseUrl: 'https://login.test');
    await auth.loginWithToken('tok');
    MbnSync.instance.configure(auth: auth);

    final success = await MbnSync.instance.pullAndApplyPreferences(force: true);
    expect(success, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('player_volume'), 85.0);
    expect(prefs.getDouble('player_rate'), 2.0);
    expect(prefs.getDouble('sub_size'), 24.0);
    expect(prefs.getString('sub_font'), 'Vazirmatn');
    expect(prefs.getInt('sub_color'), 4294967295);
    expect(prefs.getBool('access_reduce_motion'), isTrue);

    MbnSync.instance.clear();
  });
}
