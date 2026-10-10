import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// A dedicated live connection; the regular account timer remains a fallback.
class SessionWatch {
  SessionWatch(this.onRevoked, {this.onSync, this.app = 'anime'});
  final Future<void> Function(String) onRevoked;
  final Future<void> Function()? onSync;
  final String app;
  String? _syncRevision;
  http.Client? _client;
  Completer<void>? _abort;
  Timer? _retry;
  String? _token;
  String _base = '';
  int _generation = 0;
  int _failures = 0;
  void track(String? token, String base) {
    if (_token == token && _base == base) return;
    _generation++;
    _failures = 0;
    _syncRevision = null;
    if (_abort?.isCompleted == false) _abort!.complete();
    _client?.close();
    _retry?.cancel();
    _token = token;
    _base = base;
    if (token != null) unawaited(_connect(_generation));
  }

  Future<void> _connect(int generation) async {
    final client = http.Client();
    final abort = Completer<void>();
    _abort = abort;
    _client = client;
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.parse(
          '$_base/api/auth/events',
        ).replace(queryParameters: {'app': app}),
        abortTrigger: abort.future,
      )..headers['Authorization'] = 'Bearer $_token';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (generation != _generation) return;
      if (response.statusCode == 401 || response.statusCode == 403) {
        await onRevoked('نشست شما پایان یافته است؛ دوباره وارد شوید.');
        return;
      }
      if (response.statusCode != 200) throw StateError('stream unavailable');
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (generation != _generation) return;
        if (line.startsWith('data: ')) {
          _failures = 0;
          final event = jsonDecode(line.substring(6)) as Map;
          if (event['state'] != 'active') {
            await onRevoked(
              event['message']?.toString() ?? 'نشست شما پایان یافت.',
            );
            return;
          }
          final revision = event['sync_revision'];
          if (revision is String && revision != _syncRevision) {
            _syncRevision = revision;
            try {
              await onSync?.call();
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Reconnect after network changes; do not sign out on a network failure.
    } finally {
      if (!abort.isCompleted) abort.complete();
      client.close();
      if (generation == _generation && _token != null) {
        final seconds = min(30, 2 * (1 << min(_failures++, 4)));
        _retry = Timer(
          Duration(milliseconds: seconds * 1000 + Random().nextInt(500)),
          () => unawaited(_connect(generation)),
        );
      }
    }
  }

  void dispose() {
    _generation++;
    _token = null;
    _retry?.cancel();
    if (_abort?.isCompleted == false) _abort!.complete();
    _client?.close();
  }
}
