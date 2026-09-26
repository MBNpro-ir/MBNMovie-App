import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/services/mbn_auth.dart';

void main() {
  test('disabled account status carries a forced logout reason', () async {
    final auth = MbnAuth(client: MockClient((request) async {
      expect(request.url.path, '/api/auth/status');
      expect(request.headers['Authorization'], 'Bearer example');
      return http.Response.bytes(
        utf8.encode('{"state":"disabled","message":"حساب غیرفعال شده است."}'),
        200,
      );
    }), baseUrl: 'https://example.test');
    auth.token = 'example';
    expect(await auth.accountRestriction(), 'حساب غیرفعال شده است.');
  });

  test('active account stays signed in and network failure is distinct', () async {
    final active = MbnAuth(client: MockClient((_) async =>
      http.Response('{"state":"active","message":""}', 200)),
      baseUrl: 'https://example.test');
    expect(await active.accountRestriction(), isNull);
    final offline = MbnAuth(client: MockClient((_) async =>
      throw Exception('offline')), baseUrl: 'https://example.test');
    await expectLater(offline.accountRestriction(), throwsA(isA<Exception>()));
  });
}
