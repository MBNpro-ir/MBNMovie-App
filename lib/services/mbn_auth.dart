import '../core/app_platform.dart';
import '../core/platform_ui.dart' show isAndroidTv;
import 'package:flutter/foundation.dart';
import 'web_gateway.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cross_app_auth.dart';
import 'network_gate.dart';

class MbnAuthException implements Exception {
  const MbnAuthException(this.message, {this.statusCode, this.details});
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;
  @override
  String toString() => message;
}

class MbnProfile {
  const MbnProfile({
    required this.id,
    required this.name,
    required this.email,
    this.username = '',
    required this.mobile,
    required this.role,
    required this.isActive,
    required this.subscriptionExpiresAt,
    required this.hasAnimeonLink,
    this.delfanVerified = false,
    this.delfanMobile = '',
    this.hasDelfanPassword = false,
  });

  final int id;
  final String name;
  final String email;
  final String username;
  final String mobile;
  final String role;
  final bool isActive;
  final int? subscriptionExpiresAt;
  final bool hasAnimeonLink;
  final bool delfanVerified;
  final String delfanMobile;
  final bool hasDelfanPassword;

  static MbnProfile fromJson(Map<String, dynamic> row) => MbnProfile(
    id: (row['id'] as num?)?.toInt() ?? 0,
    name: row['name']?.toString() ?? '',
    email: row['email']?.toString() ?? '',
    username: row['username']?.toString() ?? '',
    mobile: row['mobile']?.toString() ?? '',
    role: row['role']?.toString() ?? 'user',
    isActive: row['is_active'] == true,
    subscriptionExpiresAt: (row['subscription_expires_at'] as num?)?.toInt(),
    hasAnimeonLink: row['has_animeon_link'] == true,
    delfanVerified: row['delfan_verified'] == true,
    delfanMobile: row['delfan_mobile']?.toString() ?? '',
    hasDelfanPassword: row['has_delfan_password'] == true,
  );
}

/// Server-side session for the movie app (https://login.m.mbnpro.ir).
/// The catalog itself stays on guest mode; this account owns the
/// subscription plus synced favorites/playlists/history/progress.
class MbnAuth {
  MbnAuth({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? (kIsWeb ? Uri.base.origin : defaultBaseUrl);

  static const defaultBaseUrl = 'https://login.m.mbnpro.ir';
  static const _tokenKey = 'mbn_secure_token';
  static const _emailKey = 'mbn_session_email';
  static const _secureStorage = FlutterSecureStorage();

  final http.Client _client;
  final NetworkRequestGate _requests = NetworkRequestGate();
  final String baseUrl;
  String? _token;
  int _generation = 0;
  String? get token => _token;
  set token(String? value) {
    if (_token != value) _generation++;
    _token = value;
    WebGateway.token = value;
  }

  MbnProfile? profile;
  String? forcedLogoutMessage;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: query);

  Map<String, String> _headers(String? credential, {bool json = false}) => {
    'X-MBN-Platform': kIsWeb
        ? 'web'
        : isAndroidTv
        ? 'android_tv'
        : Platform.operatingSystem,
    if (json) 'Content-Type': 'application/json',
    if (credential != null) 'Authorization': 'Bearer $credential',
  };

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final credential = token;
    final generation = _generation;
    final uri = _uri(path, query);
    final headers = _headers(credential, json: body != null);
    final encoded = body == null ? null : jsonEncode(body);
    try {
      final response = await _requests.run<http.Response>(
        '$method $uri $generation',
        () async {
          if (_generation != generation) {
            throw http.ClientException('حساب تغییر کرده است.');
          }
          Future<http.Response> send() {
            if (_generation != generation) {
              throw http.ClientException('حساب تغییر کرده است.');
            }
            return sendBuffered(
              _client,
              method,
              uri,
              headers: headers,
              body: encoded,
              followRedirects: false,
            );
          }

          return method == 'GET' ? readWithRetry(send) : send();
        },
        dedupe: method == 'GET',
      );
      if (_generation != generation) {
        throw http.ClientException('حساب تغییر کرده است.');
      }
      return _decode(response);
    } on MbnAuthException {
      rethrow;
    } catch (_) {
      throw const MbnAuthException(
        'اتصال به سرور برقرار نشد؛ دوباره تلاش کنید.',
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) => _requestJson('POST', path, body: body);
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) => _requestJson('GET', path, query: query);
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) => _requestJson('PUT', path, body: body);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      postJson(path, body);

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const MbnAuthException('پاسخ سرور نامعتبر است.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MbnAuthException(
        data['error']?.toString() ?? 'خطا (کد ${response.statusCode}).',
        statusCode: response.statusCode,
        details: data,
      );
    }
    return data;
  }

  /// Signs in with the server password or a 10-minute temp code.
  Future<MbnProfile> login({
    required String identifier,
    required String password,
  }) async {
    final data = await _post('/api/auth/login', {
      'identifier': identifier.trim(),
      'password': password,
      'app': 'movie',
      'shared_token': await CrossAppAuth.readSiblingToken(siblingId: 'MBNime'),
    });
    return loginWithHandoff(data, identifier: identifier);
  }

  Future<MbnProfile> loginWithHandoff(
    Map<String, dynamic> data, {
    required String identifier,
  }) async {
    token = data['token']?.toString();
    if (token == null || token!.isEmpty) {
      throw const MbnAuthException('توکن ورود دریافت نشد.');
    }
    profile = MbnProfile.fromJson(
      (data['user'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    await _persist(identifier.trim());
    return profile!;
  }

  /// Signs in directly with a pre-validated JWT token from sibling app.
  Future<MbnProfile> loginWithToken(String authToken) async {
    final prevToken = token;
    token = authToken;
    try {
      try {
        final exchanged = await postJson('/api/auth/exchange', {
          'target_app': 'movie',
          'previous_token': prevToken,
        });
        if (exchanged['token'] != null) {
          token = exchanged['token'].toString();
        }
      } on MbnAuthException {
        rethrow;
      }
      final data = await getJson('/api/me');
      profile = MbnProfile.fromJson(
        (data['user'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      final identifier = profile!.email.isNotEmpty
          ? profile!.email
          : profile!.username;
      await _persist(identifier);
      return profile!;
    } catch (_) {
      token = prevToken;
      rethrow;
    }
  }

  /// Restores a previously saved session. Never throws.
  Future<bool> restore() async {
    forcedLogoutMessage = null;
    try {
      token = await _secureStorage.read(key: _tokenKey);
      if (token == null || token!.isEmpty) return false;
      final status = await getJson('/api/auth/status');
      if (status['state'] != 'active') {
        forcedLogoutMessage =
            status['message']?.toString() ?? 'حساب شما در دسترس نیست.';
        await logout();
        return false;
      }
      final data = await getJson('/api/me');
      profile = MbnProfile.fromJson(
        (data['user'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _emailKey,
        profile!.email.isNotEmpty ? profile!.email : profile!.username,
      );
      return true;
    } on MbnAuthException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        forcedLogoutMessage = 'نشست شما پایان یافته است؛ دوباره وارد شوید.';
        await logout();
        return false;
      }
      return _restoreOfflineProfile();
    } catch (_) {
      return _restoreOfflineProfile();
    }
  }

  Future<bool> _restoreOfflineProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey);
      if (email == null || email.isEmpty) return false;
      profile = MbnProfile(
        id: 0,
        name: '',
        email: email,
        mobile: '',
        role: 'user',
        isActive: true,
        subscriptionExpiresAt: null,
        hasAnimeonLink: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> accountRestriction() async {
    final status = await getJson('/api/auth/status');
    return status['state'] == 'active'
        ? null
        : (status['message']?.toString() ?? 'حساب شما در دسترس نیست.');
  }

  Future<void> logout() async {
    final oldToken = token;
    if (oldToken != null) {
      sendBuffered(
        _client,
        'POST',
        _uri('/api/auth/logout'),
        headers: {
          'X-MBN-Platform': kIsWeb
              ? 'web'
              : isAndroidTv
              ? 'android_tv'
              : Platform.operatingSystem,
          'Authorization': 'Bearer $oldToken',
        },
        timeout: const Duration(seconds: 5),
        followRedirects: false,
      ).then((_) {}, onError: (Object _) {});
    }
    token = null;
    profile = null;
    await CrossAppAuth.clearSharedToken(token: oldToken);
    try {
      await _secureStorage.delete(key: _tokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_emailKey);
    } catch (_) {}
  }

  Future<void> _persist(String email) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emailKey, email);
      if (token != null && token!.isNotEmpty) {
        await CrossAppAuth.saveSharedToken(token: token!, email: email);
      }
    } catch (_) {}
  }
}
