import 'dart:convert';
import 'network_gate.dart';
import 'package:http/browser_client.dart';

/// Both web origins use a host-only HttpOnly cookie on the account host.
abstract final class CrossAppAuth {
  static bool isValidJwt(String? token) => token?.split('.').length == 3;
  static String get _app =>
      Uri.base.host.startsWith('movie.') ? 'movie' : 'anime';
  static Future<String?> _request(
    Map<String, dynamic> body, {
    String? token,
  }) async {
    if (!{'anime.mbnpro.ir', 'movie.mbnpro.ir'}.contains(Uri.base.host)) {
      return null;
    }
    final client = BrowserClient()..withCredentials = true;
    try {
      final response = await sendBuffered(
        client,
        'POST',
        Uri.parse('https://login.a.mbnpro.ir/api/auth/shared'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'target_app': _app, ...body}),
        timeout: const Duration(seconds: 8),
        followRedirects: false,
        maxBytes: 64 * 1024,
      );
      if (response.statusCode != 200) return null;
      return (jsonDecode(response.body) as Map<String, dynamic>)['token']
          as String?;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<void> saveSharedToken({
    required String token,
    required String email,
  }) async {
    await _request({}, token: token);
  }

  static Future<void> clearSharedToken({String? token}) async {
    await _request({'action': 'clear', 'token': token});
  }

  static Future<bool> hasSiblingSession({String siblingId = ''}) async =>
      await readSiblingToken() != null;
  static Future<String?> readSiblingToken({String siblingId = ''}) =>
      _request({});
}
