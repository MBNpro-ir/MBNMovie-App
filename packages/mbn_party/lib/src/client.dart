import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'timeline.dart';
export 'timeline.dart';

String partyNonce() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class PartyException implements Exception {
  const PartyException(
    this.message, {
    this.status = 0,
    this.code = '',
    this.data = const {},
  });
  final String message, code;
  final int status;
  final PartyJson data;
  @override
  String toString() => message;
}

class PartyClient extends ChangeNotifier with WidgetsBindingObserver {
  PartyClient({
    required this.baseUrl,
    required this.app,
    required this.token,
    http.Client? httpClient,
    PartyClock? clock,
  }) : _http = httpClient ?? http.Client(),
       clock = clock ?? PartyClock() {
    WidgetsBinding.instance.addObserver(this);
  }
  final String baseUrl, app;
  final String? Function() token;
  final http.Client _http;
  final PartyClock clock;
  PartyJson me = {};
  List<PartyJson> friends = [],
      requests = [],
      rooms = [],
      sessions = [],
      events = [];
  bool loaded = false, connected = true;
  bool hasMoreRooms = false, loadingRooms = false;
  int _roomOffset = 100;
  List<PartyJson> _extraRooms = [];
  Set<Object?> _primaryRoomIds = {};
  String? error;
  int _generation = 0, _cursor = 0, _viewers = 0, _failures = 0;
  bool _disposed = false, _polling = false, _foreground = true;
  Future<void>? _refreshing;
  final Set<Completer<void>> _aborts = {};
  Timer? _timer;
  int activePlayers = 0;
  int soloPlayers = 0;
  int get userId => partyInt(me['id']);
  int get unread =>
      rooms.fold(0, (n, r) => n + partyInt(r['unread'])) +
      requests.where((r) => partyInt(r['recipient_id']) == userId).length;
  bool get hasActiveParty => sessions.any((s) => s['state'] != 'closed');
  String get publicId => me['public_id']?.toString() ?? '…';

  Future<PartyJson> call(String method, String path, [PartyJson? data]) async {
    if (_disposed || token() == null) {
      throw const PartyException('برای پارتی وارد حساب شو.', status: 401);
    }
    final generation = _generation, credential = token();
    final original = Uri.parse('$baseUrl$path');
    final uri = original.replace(
      queryParameters: {...original.queryParameters, 'app': app},
    );
    final abort = Completer<void>();
    _aborts.add(abort);
    final timeout = Timer(const Duration(seconds: 8), () {
      if (!abort.isCompleted) abort.complete();
    });
    final req = http.AbortableRequest(method, uri, abortTrigger: abort.future)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $credential',
      });
    if (data != null) req.body = jsonEncode({...data, 'app': app});
    final sent = clock.localNow;
    late http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await _http.send(req),
      ))().timeout(const Duration(seconds: 8));
    } catch (_) {
      if (!_disposed && generation == _generation) connected = false;
      throw const PartyException('ارتباط پارتی قطع است؛ پخش مستقل ادامه دارد.');
    } finally {
      timeout.cancel();
      _aborts.remove(abort);
    }
    if (_disposed || generation != _generation || token() != credential) {
      throw const PartyException('حساب تغییر کرده است.', status: 401);
    }
    PartyJson result;
    try {
      result = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } catch (_) {
      throw const PartyException('پاسخ پارتی معتبر نیست.');
    }
    final snapshot = result['session'];
    final serverMs = partyInt(
      result['server_now_ms'] ??
          (snapshot is Map ? snapshot['server_now_ms'] : null),
    );
    if (serverMs > 0) {
      clock.observe(
        sentMs: sent,
        receivedMs: clock.localNow,
        serverMs: serverMs,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PartyException(
        result['error']?.toString() ?? 'درخواست انجام نشد.',
        status: response.statusCode,
        code: result['code']?.toString() ?? '',
        data: result,
      );
    }
    connected = true;
    return result;
  }

  List<PartyJson> _list(Object? value) => value is List
      ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
      : [];

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    if (_disposed) return;
    try {
      final data = await call('GET', '/api/party/bootstrap');
      if (_disposed) return;
      me = Map<String, dynamic>.from(data['me'] as Map);
      friends = _list(data['friends']);
      requests = _list(data['requests']);
      final latest = _list(data['rooms']);
      _primaryRoomIds = latest.map((r) => r['id']).toSet();
      final ids = latest.map((r) => r['id']).toSet(),
          friendIds = friends.map((r) => partyInt(r['id'])).toSet();
      _extraRooms = _extraRooms
          .where(
            (r) =>
                !ids.contains(r['id']) &&
                (r['kind'] == 'group' ||
                    _list(r['members']).any(
                      (m) =>
                          partyInt(m['user_id']) != userId &&
                          friendIds.contains(partyInt(m['user_id'])),
                    )),
          )
          .toList();
      rooms = [...latest, ..._extraRooms];
      sessions = _list(data['sessions']);
      if (_roomOffset == 100) hasMoreRooms = data['has_more_rooms'] == true;
      // A bootstrap can race with incoming messages. Preserve the event cursor
      // after initial load so the next poll still delivers those message IDs.
      if (!loaded) _cursor = partyInt(data['cursor']);
      loaded = true;
      error = null;
      _failures = 0;
      notifyListeners();
    } on PartyException catch (e) {
      if (_disposed) return;
      error = e.message;
      _failures++;
      notifyListeners();
    } finally {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_foreground || token() == null) return;
    final seconds = _failures > 0
        ? (5 * (1 << _failures.clamp(0, 3))).clamp(5, 60)
        : _viewers > 0
        ? 2
        : soloPlayers > 0
        ? 45
        : 20;
    _timer = Timer(Duration(seconds: seconds), _poll);
  }

  Future<void> _poll() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      if (!loaded) {
        await refresh();
        return;
      }
      final result = await call('GET', '/api/party/updates?after=$_cursor');
      _cursor = partyInt(result['cursor']);
      events = _list(result['events']);
      _failures = 0;
      error = null;
      if (result['reset'] == true || events.isNotEmpty) {
        if (result['reset'] == true) {
          _extraRooms = [];
          _roomOffset = 100;
          loaded = false;
        }
        final removed = events
            .where((e) => ['room_removed', 'room_deleted'].contains(e['kind']))
            .map((e) => e['entity_id'])
            .toSet();
        _extraRooms.removeWhere((r) => removed.contains(r['id']));
        await refresh();
      }
    } on PartyException catch (e) {
      if (!_disposed) {
        error = e.message;
        _failures++;
        notifyListeners();
      }
    } finally {
      _polling = false;
      _schedule();
    }
  }

  VoidCallback watch() {
    _viewers++;
    unawaited(refresh());
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      _viewers = (_viewers - 1).clamp(0, 100);
      _schedule();
    };
  }

  void setSoloPlayer(bool value) {
    soloPlayers = (soloPlayers + (value ? 1 : -1)).clamp(0, 100);
    _schedule();
  }

  Future<void> moreRooms() async {
    if (_disposed || loadingRooms || !hasMoreRooms) return;
    loadingRooms = true;
    notifyListeners();
    try {
      final page = await call('GET', '/api/party/rooms?offset=$_roomOffset');
      if (_disposed) return;
      final byId = {for (final r in rooms) r['id']: r};
      for (final r in _list(page['rooms'])) {
        byId[r['id']] = r;
      }
      rooms = byId.values.toList();
      _extraRooms = rooms
          .where((r) => !_primaryRoomIds.contains(r['id']))
          .toList();
      _roomOffset = partyInt(page['next_offset']);
      hasMoreRooms = page['has_more'] == true;
    } finally {
      loadingRooms = false;
      if (!_disposed) notifyListeners();
    }
  }

  void updateSession(PartyJson value) {
    if (_disposed) return;
    final index = sessions.indexWhere((s) => s['id'] == value['id']);
    if (value['state'] == 'closed') {
      if (index >= 0) {
        sessions.removeAt(index);
        notifyListeners();
      }
    } else if (index < 0) {
      sessions = [value, ...sessions];
      notifyListeners();
    } else {
      sessions[index] = value;
    }
    // Playback polls do not rebuild the app on every heartbeat.
  }

  Future<PartyJson?> find(String text) async =>
      (await call(
            'GET',
            '/api/party/search?q=${Uri.encodeQueryComponent(text)}',
          ))['user']
          as PartyJson?;
  Future<void> addFriend(int uid) async {
    await call('POST', '/api/party/friends', {'user_id': uid});
    await refresh();
  }

  Future<void> replyFriend(int id, String action) async {
    await call('POST', '/api/party/friends/requests/$id', {'action': action});
    await refresh();
  }

  Future<void> removeFriend(int uid) async {
    await call('DELETE', '/api/party/friends/$uid');
    await refresh();
  }

  Future<void> block(int uid, {bool value = true}) async {
    await call(
      value ? 'POST' : 'DELETE',
      '/api/party/blocks/$uid',
      value ? {} : null,
    );
    await refresh();
  }

  Future<PartyJson> createRoom({
    required List<int> members,
    bool group = false,
    String title = '',
  }) async {
    final data = await call('POST', '/api/party/rooms', {
      'kind': group ? 'group' : 'direct',
      'members': members,
      'title': title,
    });
    await refresh();
    return Map<String, dynamic>.from(data['room'] as Map);
  }

  Future<PartyJson> room(String id) async => Map<String, dynamic>.from(
    (await call('GET', '/api/party/rooms/$id'))['room'] as Map,
  );
  Future<PartyJson> messages(String id, {int before = 0}) =>
      call('GET', '/api/party/rooms/$id/messages?before=$before');
  Future<PartyJson> message(int id) async => Map<String, dynamic>.from(
    (await call('GET', '/api/party/messages/$id'))['message'] as Map,
  );
  Future<void> sendText(
    String room,
    String text, {
    int? replyTo,
    String? messageNonce,
  }) async {
    await call('POST', '/api/party/rooms/$room/messages', {
      'kind': 'text',
      'body': text,
      'nonce': messageNonce ?? partyNonce(),
      'reply_to': ?replyTo,
    });
  }

  Future<void> sendMedia(String room, PartyJson media) async {
    await call('POST', '/api/party/rooms/$room/messages', {
      'kind': 'media',
      'payload': media,
      'nonce': partyNonce(),
    });
  }

  Future<void> reaction(int id, String emoji, {required bool active}) async {
    await call('POST', '/api/party/messages/$id/reactions', {
      'emoji': emoji,
      'active': active,
    });
  }

  Future<void> editMessage(int id, String text) async {
    await call('PATCH', '/api/party/messages/$id', {'body': text});
  }

  Future<void> deleteMessage(int id) async {
    await call('DELETE', '/api/party/messages/$id');
  }

  Future<void> read(String room, int last) async {
    await call('POST', '/api/party/rooms/$room/read', {'message_id': last});
  }

  Future<void> member(
    String room,
    int uid,
    PartyJson data, {
    String method = 'PATCH',
  }) async {
    await call(
      method,
      '/api/party/rooms/$room/members/$uid',
      method == 'DELETE' ? null : data,
    );
    await refresh();
  }

  Future<void> renameRoom(String room, String title) async {
    await call('PATCH', '/api/party/rooms/$room', {'title': title});
    await refresh();
  }

  Future<void> deleteRoom(String room) async {
    await call('DELETE', '/api/party/rooms/$room');
    await refresh();
  }

  Future<PartyJson> createSession(
    String room,
    PartyJson media,
    int position,
  ) async {
    final value = Map<String, dynamic>.from(
      (await call('POST', '/api/party/rooms/$room/sessions', {
            'payload': media,
            'position_ms': position,
            'nonce': partyNonce(),
          }))['session']
          as Map,
    );
    updateSession(value);
    notifyListeners();
    return value;
  }

  Future<PartyJson> session(String id) async {
    final value = Map<String, dynamic>.from(
      (await call('GET', '/api/party/sessions/$id'))['session'] as Map,
    );
    updateSession(value);
    return value;
  }

  Future<PartyJson> command(
    String id,
    String action, {
    required String clientId,
    int? version,
    int? position,
    int? duration,
    double? rate,
    String? commandNonce,
  }) async {
    final result = await call('POST', '/api/party/sessions/$id/commands', {
      'action': action,
      'client_id': clientId,
      'nonce': commandNonce ?? partyNonce(),
      'version': ?version,
      'position_ms': ?position,
      'duration_ms': ?duration,
      'rate': ?rate,
    });
    final value = Map<String, dynamic>.from(result['session'] as Map);
    updateSession(value);
    return value;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(refresh());
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _http.close();
    for (final abort in _aborts) {
      if (!abort.isCompleted) abort.complete();
    }
    _aborts.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

typedef PartyOpenMedia =
    Future<void> Function(
      BuildContext context,
      PartyJson media,
      String? sessionId,
    );

/// Stable notifier shared by app chrome and routes, replaced on account change.
class PartyHub extends ChangeNotifier {
  PartyHub._();
  static final instance = PartyHub._();
  PartyClient? client;
  PartyOpenMedia? openMedia;
  bool reduceMotion = false;
  void configure(PartyClient? value) {
    client?.removeListener(_changed);
    client?.dispose();
    client = value;
    client?.addListener(_changed);
    notifyListeners();
    if (value != null) unawaited(value.refresh());
  }

  void _changed() => notifyListeners();
}
