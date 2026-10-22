import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Process-wide switch used when the account server is unavailable.
///
/// Media URLs and local downloads remain independent from this switch. It
/// only stops account/sync traffic from retrying while the user is in the
/// explicitly-confirmed offline mode.
abstract final class OfflineMode {
  static final ValueNotifier<bool> changes = ValueNotifier<bool>(false);

  static bool get active => changes.value;

  static void enter() {
    if (!changes.value) changes.value = true;
  }

  static void leave() {
    if (changes.value) changes.value = false;
  }
}

/// Bounded FIFO queue. Identical reads share only their in-flight future;
/// completed results and failures are never cached here.
class NetworkRequestGate {
  NetworkRequestGate({
    this.maxConcurrent = 4,
    this.maxPending = 24,
    this.queueTimeout = const Duration(seconds: 10),
  }) : assert(maxConcurrent > 0),
       assert(maxPending > 0);
  final int maxConcurrent, maxPending;
  final Duration queueTimeout;
  final Queue<_PendingRequest> _queue = Queue();
  final Map<String, Future<Object?>> _inFlight = {};
  int _active = 0;

  Future<T> run<T>(
    String key,
    Future<T> Function() operation, {
    bool dedupe = true,
  }) {
    final existing = dedupe ? _inFlight[key] : null;
    if (existing != null) return existing.then((value) => value as T);
    if (_active >= maxConcurrent && _queue.length >= maxPending) {
      return Future.error(const NetworkQueueException());
    }
    final result = Completer<T>();
    // Store the original future: a detached .then creates unhandled errors.
    if (dedupe) _inFlight[key] = result.future;
    late final _PendingRequest pending;
    void forget() {
      if (dedupe) _inFlight.remove(key);
    }

    pending = _PendingRequest(() async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        forget();
      }
    });
    _queue.add(pending);
    pending.timer = Timer(queueTimeout, () {
      if (_queue.remove(pending)) {
        forget();
        result.completeError(const NetworkQueueException());
      }
    });
    _drain();
    return result.future;
  }

  void _drain() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final pending = _queue.removeFirst();
      pending.timer?.cancel();
      _active++;
      unawaited(
        pending.run().whenComplete(() {
          _active--;
          _drain();
        }),
      );
    }
  }
}

class _PendingRequest {
  _PendingRequest(this.run);
  final Future<void> Function() run;
  Timer? timer;
}

class NetworkQueueException implements Exception {
  const NetworkQueueException();
  @override
  String toString() =>
      'درخواست‌های زیادی در انتظار است؛ کمی بعد دوباره تلاش کنید.';
}

/// Cancels the real HTTP request at its deadline instead of just abandoning
/// a Future. Covers both response headers and body; rejects oversized bodies.
Future<http.Response> sendBuffered(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Duration timeout = const Duration(seconds: 20),
  int maxBytes = 16 * 1024 * 1024,
  bool followRedirects = true,
  Future<void>? abortTrigger,
}) async {
  final abort = Completer<void>();
  void cancel() {
    if (!abort.isCompleted) abort.complete();
  }

  if (abortTrigger != null) {
    unawaited(
      abortTrigger.then((_) => cancel(), onError: (Object _) => cancel()),
    );
  }
  final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)
    ..followRedirects = followRedirects;
  request.headers.addAll(headers ?? const {});
  if (body is String) {
    request.body = body;
  } else if (body is List<int>) {
    request.bodyBytes = body;
  } else if (body is Map<String, String>) {
    request.bodyFields = body;
  }
  Future<http.Response> receive() async {
    final response = await client.send(request);
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw http.ClientException('پاسخ سرور بیش از حد بزرگ است.', uri);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw http.ClientException('پاسخ سرور بیش از حد بزرگ است.', uri);
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(
      bytes.takeBytes(),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  try {
    return await receive().timeout(timeout);
  } finally {
    cancel();
  }
}

/// Read operations may retry short-lived transport/gateway failures. Writes,
/// authorization failures and permanent server errors are returned directly.
Future<http.Response> readWithRetry(
  Future<http.Response> Function() send, {
  int maxAttempts = 2,
}) async {
  final attempts = max(1, min(maxAttempts, 4));
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      final response = await send();
      final retryable =
          response.statusCode == 408 ||
          response.statusCode == 502 ||
          response.statusCode == 504;
      if (!retryable || attempt == attempts) return response;
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      if (retryAfter != null && retryAfter > 2) return response;
      await _retryDelay(response);
    } on TimeoutException {
      if (attempt == attempts) rethrow;
      await _retryDelay();
    } on http.ClientException {
      if (attempt == attempts) rethrow;
      await _retryDelay();
    }
  }
  throw StateError('unreachable');
}

Future<void> _retryDelay([http.Response? response]) async {
  final retryAfter = int.tryParse(response?.headers['retry-after'] ?? '');
  if (retryAfter != null && retryAfter > 2) return;
  await Future<void>.delayed(
    Duration(
      milliseconds: retryAfter != null
          ? max(0, retryAfter) * 1000
          : 300 + Random().nextInt(250),
    ),
  );
}
