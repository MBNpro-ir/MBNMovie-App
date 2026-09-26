import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/movie_api.dart';

/// Persists the login session so the user stays signed in across restarts.
///
/// Signed-in state = a stored account email. The server cookie is restored
/// opportunistically. Only an explicit [logout] clears the stored session.
class SessionStore {
  SessionStore(this.api);

  static const _emailKey = 'mbnmovie_secure_email';
  static const _cookieKey = 'mbnmovie_secure_session';
  static const _sessionKey = 'mbnmovie_secure_session_v1';
  static const _signedOutKey = 'mbnmovie_signed_out';
  static const _legacyEmailKey = 'mbnmovie_session_email';
  static const _secureStorage = FlutterSecureStorage();

  final MovieApi api;
  String? email;

  bool get isLoggedIn => email != null && email!.isNotEmpty;

  /// Restores a previously saved session. Never throws: a storage failure
  /// (e.g. a corrupt file) simply means "not logged in".
  /// A durable signed-out marker always wins over leftover secure values so
  /// a failed delete can never silently resurrect the previous account.
  Future<void> restore() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final signedOut = prefs?.getBool(_signedOutKey) ?? false;

    final record = await _readSessionRecord();
    if (!signedOut && record != null) {
      email = record.email;
      api.restoreCookie(record.cookie);
    } else {
      // Legacy split keys are only honored as a complete pair; a lone
      // email (e.g. interrupted write) is never treated as signed in.
      final restoredEmail = await _readKey(_emailKey);
      final cookie = await _readKey(_cookieKey);
      if (!signedOut &&
          restoredEmail != null &&
          restoredEmail.isNotEmpty &&
          cookie != null &&
          cookie.isNotEmpty) {
        email = restoredEmail;
        api.restoreCookie(cookie);
        // Opportunistically migrate to the atomic record.
        await _writeSessionRecord(email!, cookie);
      } else {
        email = null;
        api.clearSession();
        if (signedOut) {
          // Best-effort cleanup of leftovers from a previously failed delete.
          await _deleteKey(_emailKey);
          await _deleteKey(_cookieKey);
          await _deleteKey(_sessionKey);
        }
      }
    }

    // Remove the local-only preview session from earlier builds.
    try {
      final instance = prefs ?? await SharedPreferences.getInstance();
      await instance.remove(_legacyEmailKey);
    } catch (_) {
      // Best effort only; a prefs failure must not affect the session.
    }
  }

  Future<void> login({required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final success = await api.login(email: normalizedEmail, password: password);
    if (!success || api.sessionCookie == null) {
      throw const MovieApiException('ایمیل یا رمز عبور درست نیست.');
    }
    await _persist(normalizedEmail);
  }

  Future<void> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final success = await api.register(
      name: name,
      email: normalizedEmail,
      mobile: mobile,
      password: password,
    );
    if (!success || api.sessionCookie == null) {
      throw const MovieApiException(
        'ثبت‌نام انجام نشد؛ ممکن است ایمیل قبلاً استفاده شده باشد.',
      );
    }
    await _persist(normalizedEmail);
  }

  /// Imports an opaque session code instead of embedding an account password
  /// in the application. The official server validates the included session
  /// before it is persisted locally.
  Future<void> loginWithCode(String code) async {
    final decoded = _decodeLoginCode(code);
    api.restoreCookie(decoded.cookie);
    if (!await api.validateCurrentSession()) {
      api.clearSession();
      throw const MovieApiException('کد ورود نامعتبر یا منقضی شده است.');
    }
    await _persist(decoded.email);
  }

  String createLoginCode() {
    final currentEmail = email;
    final cookie = api.sessionCookie;
    if (currentEmail == null || cookie == null) {
      throw const MovieApiException('ابتدا باید وارد حساب شوید.');
    }
    final payload = utf8.encode(
      jsonEncode({'v': 1, 'e': currentEmail, 's': cookie}),
    );
    return 'MBN1.${base64Url.encode(payload).replaceAll('=', '')}';
  }

  Future<void> _persist(String normalizedEmail) async {
    // Persist BEFORE exposing the session: if device storage fails we must
    // not let the user in for this run only to sign them out on restart.
    final cookie = api.sessionCookie;
    if (cookie == null || cookie.isEmpty) {
      throw const MovieApiException('نشست ورود ذخیره نشد؛ دوباره تلاش کن.');
    }
    try {
      await _writeSessionRecord(normalizedEmail, cookie);
      final roundTrip = await _readSessionRecord();
      if (roundTrip == null ||
          roundTrip.email != normalizedEmail ||
          roundTrip.cookie != cookie) {
        throw const MovieApiException('ذخیره نشست ناموفق بود.');
      }
      // Legacy split keys stay for downgrade tolerance; failures here must
      // not invalidate the already-verified atomic record.
      try {
        await _secureStorage.write(key: _emailKey, value: normalizedEmail);
      } catch (_) {}
      try {
        await _secureStorage.write(key: _cookieKey, value: cookie);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_signedOutKey);
      } catch (_) {}
    } on MovieApiException {
      // Never expose a session that was not durably stored.
      api.clearSession();
      rethrow;
    } catch (_) {
      api.clearSession();
      throw const MovieApiException('نشست ورود ذخیره نشد؛ دوباره تلاش کن.');
    }
    email = normalizedEmail;
  }

  static _LoginCode _decodeLoginCode(String raw) {
    try {
      final text = raw.trim();
      if (!text.startsWith('MBN1.')) throw const FormatException();
      final encoded = text.substring(5);
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final data = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (data is! Map<String, dynamic> || data['v'] != 1) {
        throw const FormatException();
      }
      final email = data['e']?.toString().trim().toLowerCase() ?? '';
      final cookie = data['s']?.toString().trim() ?? '';
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
          !RegExp(r'^ci_session=[^;\s]+$').hasMatch(cookie)) {
        throw const FormatException();
      }
      return _LoginCode(email, cookie);
    } catch (_) {
      throw const MovieApiException('فرمت کد ورود درست نیست.');
    }
  }

  /// Signs out and wipes the stored session. Memory is always cleared, even
  /// if a storage delete fails. A durable signed-out marker is written first
  /// so a failed delete can never silently restore the previous account on
  /// the next launch; verification failures are surfaced to the caller.
  Future<void> logout() async {
    Object? failure;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedOutKey, true);
    } catch (e) {
      failure = e;
    }
    for (final key in [_sessionKey, _emailKey, _cookieKey]) {
      try {
        await _secureStorage.delete(key: key);
      } catch (e) {
        failure ??= e;
      }
    }
    api.clearSession();
    email = null;
    if (failure != null) {
      // Verify whether any credential survived; the signed-out marker
      // already blocks silent restore, but the user must know cleanup
      // needs a retry.
      final leftover = await _readSessionRecord();
      final legacyEmail = await _readKey(_emailKey);
      final legacyCookie = await _readKey(_cookieKey);
      if (leftover != null || legacyEmail != null || legacyCookie != null) {
        throw const MovieApiException(
          'خروج انجام شد اما پاک‌سازی حافظه امن کامل نشد؛ یک‌بار دیگر خروج را بزن.',
        );
      }
    }
  }

  static Future<void> _writeSessionRecord(String email, String cookie) async {
    final payload = jsonEncode({'v': 1, 'e': email, 's': cookie});
    await _secureStorage.write(key: _sessionKey, value: payload);
  }

  static Future<_SessionRecord?> _readSessionRecord() async {
    final raw = await _readKey(_sessionKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['v'] != 1) return null;
      final email = data['e']?.toString().trim().toLowerCase() ?? '';
      final cookie = data['s']?.toString().trim() ?? '';
      if (email.isEmpty || cookie.isEmpty) return null;
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return null;
      if (!RegExp(r'^ci_session=[^;\s]+$').hasMatch(cookie)) return null;
      return _SessionRecord(email, cookie);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteKey(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}
  }

  static Future<String?> _readKey(String key) async {
    try {
      final value = await _secureStorage.read(key: key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }
}

class _LoginCode {
  const _LoginCode(this.email, this.cookie);
  final String email;
  final String cookie;
}

class _SessionRecord {
  const _SessionRecord(this.email, this.cookie);
  final String email;
  final String cookie;
}
