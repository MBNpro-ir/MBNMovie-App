import 'dart:async';
import 'browser_features.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Browser traffic stays on HTTPS and uses the account server's catalog bridge.
abstract final class WebGateway {
  static String? token;
  static final preparingVideo = ValueNotifier<bool>(false);
  static Uri endpoint(String path, [Map<String, String>? query]) =>
      Uri.parse(Uri.base.origin).replace(path: path, queryParameters: query);
  static String image(String url) => !kIsWeb || !url.startsWith('http')
      ? url : endpoint('/api/web/image', {'url': url}).toString();
  static Future<String> externalAudio(String url) => media(url, externalAudio: true);
  static Future<String> media(String url, {bool externalAudio = false}) async {
    if (!kIsWeb || !url.startsWith('http')) return url;
    final response = await http.post(endpoint('/api/web/media-ticket'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'url': url, if (externalAudio) 'external_audio': true}));
    final data = jsonDecode(response.body) as Map;
    if (response.statusCode != 200) throw StateError(data['error']?.toString() ?? 'پخش در دسترس نیست.');
    var ticket = data['ticket'].toString();
    final extension = Uri.parse(url).path.toLowerCase();
    if (!externalAudio && BrowserFeatures.requiresCompatibleVideo &&
        !extension.endsWith('.mp4') && !extension.endsWith('.m4v') && !extension.endsWith('.m3u8')) {
      preparingVideo.value = true;
      try {
      final initialToken = token;
      var ready = false;
      final deadline = DateTime.now().add(const Duration(minutes: 30));
      while (DateTime.now().isBefore(deadline)) {
        if (token != initialToken || token == null) throw StateError('جلسه پایان یافت.');
        final prepared = await http.post(endpoint('/api/web/media-prepare'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({'ticket': ticket}));
        final result = jsonDecode(prepared.body) as Map;
        if (prepared.statusCode != 200 || result['status'] == 'failed') {
          throw StateError(result['error']?.toString() ?? 'آماده‌سازی پخش در Safari انجام نشد.');
        }
        if (result['status'] == 'ready') { ticket = result['ticket'].toString(); ready = true; break; }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!ready) throw StateError('آماده‌سازی پخش بیش از حد طول کشید.');
      } finally { preparingVideo.value = false; }
    }
    return endpoint('/api/web/media', {'ticket': ticket, if (data['format'] == 'm3u8') 'format': 'm3u8'}).toString();
  }
}

class WebCatalogClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final response = await _inner.post(WebGateway.endpoint('/api/web/proxy'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${WebGateway.token}'},
      body: jsonEncode({'url': request.url.toString(), 'method': request.method,
        'headers': request.headers.map((k, v) => MapEntry(
          k.split('-').map((s) => s[0].toUpperCase() + s.substring(1)).join('-'), v)),
        'body': base64Encode(body)}));
    final headers = Map<String, String>.from(response.headers);
    if (headers['x-upstream-cookie'] != null) headers['set-cookie'] = headers['x-upstream-cookie']!;
    return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode,
      headers: headers, request: request, reasonPhrase: response.reasonPhrase);
  }
  @override
  void close() => _inner.close();
}
