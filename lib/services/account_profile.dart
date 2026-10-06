import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mbn_auth.dart';

/// Account-scoped receipts survive connection failure; server deduplicates IDs.
class AccountProfile {
  static final current = ValueNotifier<Map<String, dynamic>>({});
  static MbnAuth? server;
  static String app = 'movie';
  static bool _sending = false;
  static Future<void> _writes = Future.value();
  static int? _owner;
  static int? get owner => _owner;
  static void configure(MbnAuth? value) {
    server = value;
    int? owner;
    try {
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(value!.token!.split('.')[1]),
                  ),
                ),
              )
              as Map;
      owner = int.tryParse('${payload['sub']}');
    } catch (_) {}
    if (owner != _owner) current.value = {};
    _owner = owner;
  }

  static Future<Map<String, dynamic>> reload() async {
    final source = server;
    final owner = _owner;
    if (source == null) return {};
    final body = await source.getJson('/api/me/profile');
    final result = Map<String, dynamic>.from(body['profile'] as Map);
    if (identical(server, source) && _owner == owner) current.value = result;
    return result;
  }

  static Future<void> save(Map<String, dynamic> data) async {
    final source = server;
    final owner = _owner;
    if (source == null) return;
    final body = await source.putJson('/api/me/profile', data);
    if (identical(server, source) && _owner == owner) {
      current.value = Map<String, dynamic>.from(body['profile'] as Map);
    }
  }

  static String get _queueKey => 'mbn_watch_receipts_${app}_$_owner';
  static Future<void> record(
    String content,
    String episode,
    String kind,
    int ms, {
    int? expectedOwner,
  }) {
    if (expectedOwner != null && expectedOwner != _owner) return Future.value();
    final owner = _owner;
    final source = server;
    final key = _queueKey;
    final epoch = current.value['epoch'];
    if (source == null || owner == null || epoch is! int || ms <= 0) {
      return Future.value();
    }
    final event = {
      'id':
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      'content_id': content,
      'episode_id': episode,
      'kind': kind,
      'elapsed_ms': ms.clamp(1, 60000),
      'epoch': epoch,
    };
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final queue = (jsonDecode(prefs.getString(key) ?? '[]') as List)
        ..add(event);
      if (queue.length > 10000) queue.removeRange(0, queue.length - 10000);
      await prefs.setString(key, jsonEncode(queue));
    });
    return _writes.then((_) {
      unawaited(flush());
    });
  }

  static Future<void> flush() async {
    if (_sending || server == null || _owner == null) return;
    _sending = true;
    final key = _queueKey;
    final source = server!;
    final owner = _owner;
    try {
      await _writes;
      if (owner != _owner || !identical(source, server)) return;
      final prefs = await SharedPreferences.getInstance();
      final pending = jsonDecode(prefs.getString(key) ?? '[]') as List;
      if (pending.isEmpty) return;
      final batch = pending.take(100).toList();
      if (owner != _owner || !identical(source, server)) return;
      final body = await source.postJson('/api/me/watch', {
        'app': app,
        'events': batch,
      });
      // Serialize removal with new receipts so a late response cannot lose them.
      _writes = _writes.then((_) async {
        final latest = jsonDecode(prefs.getString(key) ?? '[]') as List;
        final ids = {for (final e in batch) (e as Map)['id']};
        latest.removeWhere((e) => ids.contains((e as Map)['id']));
        await prefs.setString(key, jsonEncode(latest));
      });
      await _writes;
      if (identical(server, source) && owner == _owner) {
        current.value = Map<String, dynamic>.from(body['profile'] as Map);
      }
    } catch (_) {
      // Retain receipts for the next player flush or account-screen refresh.
    } finally {
      _sending = false;
    }
  }
}
