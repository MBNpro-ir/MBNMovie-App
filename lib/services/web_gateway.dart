import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'network_gate.dart';

/// Browser traffic stays on HTTPS and uses the account server's catalog bridge.
abstract final class WebGateway {
  static String? _token;
  static int _generation = 0;
  static final http.Client _client = http.Client();
  static final NetworkRequestGate _requests = NetworkRequestGate();
  static int _preparingCount = 0;
  static String? get token => _token;
  static set token(String? value) {
    if (value != _token) {
      _generation++;
      mediaTracks.clear();
    }
    _token = value;
  }

  static final Map<String, Map> mediaTracks = {};
  static final preparingVideo = ValueNotifier<bool>(false);
  static Uri endpoint(String path, [Map<String, String>? query]) =>
      Uri.parse(Uri.base.origin).replace(path: path, queryParameters: query);
  static String image(String url) => !kIsWeb || !url.startsWith('http')
      ? url
      : endpoint('/api/web/image', {'url': url}).toString();
  static Future<String> externalAudio(String url) =>
      media(url, externalAudio: true);
  static Future<http.Response> _request(
    String path,
    Map<String, dynamic> body, {
    bool Function()? active,
  }) async {
    final generation = _generation;
    final credential = token;
    final encoded = jsonEncode(body);
    void check() {
      if (generation != _generation ||
          credential == null ||
          active?.call() == false) {
        throw StateError('جلسه پایان یافت.');
      }
    }

    final response = await _requests.run('$generation $path $encoded', () {
      check();
      return sendBuffered(
        _client,
        'POST',
        endpoint(path),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $credential',
        },
        body: encoded,
        timeout: const Duration(seconds: 25),
        maxBytes: 2 * 1024 * 1024,
        followRedirects: false,
      );
    });
    check();
    return response;
  }

  static Future<http.Response> subtitle(String url) =>
      _request('/api/web/subtitle', {'url': url});
  static Future<String> media(
    String url, {
    bool externalAudio = false,
    bool includeTracks = false,
    bool Function()? active,
  }) async {
    if (!kIsWeb || !url.startsWith('http')) return url;
    final initialGeneration = _generation;
    final response = await _request('/api/web/media-ticket', {
      'url': url,
      if (externalAudio) 'external_audio': true,
    }, active: active);
    final data = jsonDecode(response.body) as Map;
    if (response.statusCode != 200) {
      throw StateError(data['error']?.toString() ?? 'پخش در دسترس نیست.');
    }
    var ticket = data['ticket'].toString();
    final extension = Uri.parse(url).path.toLowerCase();
    if (!externalAudio && includeTracks && !extension.endsWith('.m3u8')) {
      _preparingCount++;
      preparingVideo.value = true;
      try {
        var ready = false;
        final deadline = DateTime.now().add(const Duration(minutes: 30));
        while (DateTime.now().isBefore(deadline)) {
          if (_generation != initialGeneration ||
              token == null ||
              active?.call() == false) {
            throw StateError('جلسه پایان یافت.');
          }
          final prepared = await _request('/api/web/media-prepare', {
            'ticket': ticket,
          }, active: active);
          if (_generation != initialGeneration || active?.call() == false) {
            throw StateError('Playback ended');
          }
          final result = jsonDecode(prepared.body) as Map;
          if (prepared.statusCode != 200 || result['status'] == 'failed') {
            throw StateError(
              result['error']?.toString() ??
                  'آماده‌سازی صدا، زیرنویس و پخش وب انجام نشد.',
            );
          }
          if (result['status'] == 'ready') {
            ticket = result['ticket'].toString();
            if (mediaTracks.length > 8) mediaTracks.clear();
            mediaTracks[url] = result['tracks'] as Map? ?? {};
            ready = true;
            break;
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        if (!ready) throw StateError('آماده‌سازی پخش بیش از حد طول کشید.');
      } finally {
        _preparingCount--;
        preparingVideo.value = _preparingCount > 0;
      }
    }
    return endpoint('/api/web/media', {
      'ticket': ticket,
      if (data['format'] == 'm3u8') 'format': 'm3u8',
    }).toString();
  }
}

class WebCatalogClient extends http.BaseClient {
  WebCatalogClient({http.Client? client, Uri? endpoint})
    : _inner = client ?? http.Client(),
      _endpoint =
          endpoint ??
          (kIsWeb
              ? WebGateway.endpoint('/api/web/proxy')
              : Uri.parse('https://login.m.mbnpro.ir/api/web/proxy'));
  final http.Client _inner;
  final Uri _endpoint;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final generation = WebGateway._generation;
    final credential = WebGateway.token;
    if (credential == null) {
      throw http.ClientException('نشست شما پایان یافته است.');
    }
    final response = await sendBuffered(
      _inner,
      'POST',
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $credential',
      },
      body: jsonEncode({
        'url': request.url.toString(),
        'method': request.method,
        'headers': request.headers.map(
          (k, v) => MapEntry(
            k
                .split('-')
                .map((s) => s[0].toUpperCase() + s.substring(1))
                .join('-'),
            v,
          ),
        ),
        'body': base64Encode(body),
      }),
      timeout: const Duration(seconds: 35),
      followRedirects: false,
      abortTrigger: request is http.Abortable ? request.abortTrigger : null,
    );
    if (generation != WebGateway._generation) {
      throw http.ClientException('حساب تغییر کرده است.');
    }
    final headers = Map<String, String>.from(response.headers);
    if (headers['x-upstream-cookie'] != null) {
      headers['set-cookie'] = headers['x-upstream-cookie']!;
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
