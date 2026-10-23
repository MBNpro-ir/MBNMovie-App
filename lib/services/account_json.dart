import 'dart:convert';
import 'package:flutter/foundation.dart';

String _encode(Map<String, dynamic> body) => jsonEncode(body);
Map<String, dynamic> _decode(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

Future<String> encodeAccountJson(Map<String, dynamic> body) =>
    compute(_encode, body, debugLabel: 'account JSON encode');

Future<Map<String, dynamic>> decodeAccountJson(Uint8List bytes) async =>
    bytes.length < 64 * 1024
    ? _decode(bytes)
    : await compute(_decode, bytes, debugLabel: 'account JSON decode');
