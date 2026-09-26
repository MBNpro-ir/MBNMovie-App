import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef HandoffPost =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> body,
    );

/// A short-lived, one-time server exchange. The redeem secret remains only
/// in the target app's secure storage; neither password nor session token is
/// passed through Android intents or Windows registry.
abstract final class AuthHandoff {
  static const _storage = FlutterSecureStorage();
  static String _key(String id) => 'mbn_handoff_secret_$id';

  static Future<String> create({
    required HandoffPost post,
    required String sourceApp,
    required String targetApp,
  }) async {
    final random = Random.secure();
    final secret = base64UrlEncode(
      List<int>.generate(48, (_) => random.nextInt(256)),
    );
    final response = await post('/api/auth/handoff/create', {
      'source_app': sourceApp,
      'target_app': targetApp,
      'secret_hash': sha256.convert(utf8.encode(secret)).toString(),
    });
    final id = response['request_id']?.toString() ?? '';
    if (id.isEmpty) throw StateError('درخواست ورود مشترک ساخته نشد.');
    await _storage.write(key: _key(id), value: secret);
    return id;
  }

  static Future<Map<String, dynamic>?> status({
    required HandoffPost post,
    required String id,
  }) async {
    final secret = await _storage.read(key: _key(id));
    if (secret == null) return null;
    return post('/api/auth/handoff/status', {
      'request_id': id,
      'secret': secret,
    });
  }

  static Future<Map<String, dynamic>?> consume({
    required HandoffPost post,
    required String id,
    required String targetApp,
  }) async {
    final secret = await _storage.read(key: _key(id));
    if (secret == null) return null;
    final result = await post('/api/auth/handoff/consume', {
      'request_id': id,
      'secret': secret,
      'target_app': targetApp,
    });
    await clear(id);
    return result;
  }

  static Future<void> approve({
    required HandoffPost post,
    required String id,
  }) async {
    await post('/api/auth/handoff/approve', {'request_id': id});
  }

  static Future<void> deny({
    required HandoffPost post,
    required String id,
  }) async {
    await post('/api/auth/handoff/deny', {'request_id': id});
  }

  static Future<void> clear(String id) => _storage.delete(key: _key(id));
}
