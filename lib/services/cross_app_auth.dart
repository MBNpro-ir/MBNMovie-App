import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

abstract final class CrossAppAuth {
  /// File used to share credentials between MBN apps.
  static File _sharedAuthFile() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      return File(p.join(appData, 'com.mbn', 'shared_auth.json'));
    }
    const downloadPath = '/storage/emulated/0/Download/.mbn_shared_auth.json';
    return File(downloadPath);
  }

  /// Saves the current session token to a location readable by sibling MBN apps.
  static Future<void> saveSharedToken({
    required String token,
    required String email,
  }) async {
    try {
      final file = _sharedAuthFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'token': token,
          'email': email,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  /// Checks if a session for sibling app (e.g. 'MBNime') exists on this device.
  static Future<bool> hasSiblingSession({String siblingId = 'MBNime'}) async {
    final token = await readSiblingToken(siblingId: siblingId);
    return token != null && token.isNotEmpty;
  }

  /// Attempts to read the sibling app's authentication token silently.
  static Future<String?> readSiblingToken({String siblingId = 'MBNime'}) async {
    // 1. First try shared auth file
    try {
      final shared = _sharedAuthFile();
      if (await shared.exists()) {
        final content = await shared.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        final token = map['token']?.toString();
        if (token != null && token.isNotEmpty) return token;
      }
    } catch (_) {}

    // 2. On Windows: Try decrypting MBNime's flutter_secure_storage.dat directly via DPAPI
    if (Platform.isWindows) {
      try {
        final appData = Platform.environment['APPDATA'] ?? '';
        final file = File(
          p.join(appData, 'com.mbn', siblingId, 'flutter_secure_storage.dat'),
        );
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            final decrypted = _decryptDpapi(bytes);
            if (decrypted != null && decrypted.isNotEmpty) {
              final map = jsonDecode(decrypted) as Map<String, dynamic>;
              final token = map['mbn_secure_token']?.toString();
              if (token != null && token.isNotEmpty) {
                // Also write to shared auth file for fast subsequent reads
                unawaited(
                  saveSharedToken(
                    token: token,
                    email: map['mbn_session_email']?.toString() ?? '',
                  ),
                );
                return token;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fallback on Android for secondary paths
    if (Platform.isAndroid) {
      for (final altPath in [
        '/sdcard/Download/.mbn_shared_auth.json',
        '/storage/emulated/0/Download/.mbn_shared_auth.json',
      ]) {
        try {
          final file = File(altPath);
          if (await file.exists()) {
            final content = await file.readAsString();
            final map = jsonDecode(content) as Map<String, dynamic>;
            final token = map['token']?.toString();
            if (token != null && token.isNotEmpty) return token;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  static String? _decryptDpapi(List<int> bytes) {
    try {
      final crypt32 = DynamicLibrary.open('crypt32.dll');
      final unprotect = crypt32.lookupFunction<
        _CryptUnprotectDataNative,
        _CryptUnprotectDataDart
      >('CryptUnprotectData');

      return using((Arena arena) {
        final inBlob = arena<_DataBlob>();
        final inData = arena<Uint8>(bytes.length);
        for (var i = 0; i < bytes.length; i++) {
          inData[i] = bytes[i];
        }
        inBlob.ref.cbData = bytes.length;
        inBlob.ref.pbData = inData;

        final outBlob = arena<_DataBlob>();
        final res = unprotect(
          inBlob,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          0,
          outBlob,
        );
        if (res != 0 &&
            outBlob.ref.pbData != nullptr &&
            outBlob.ref.cbData > 0) {
          final outBytes = outBlob.ref.pbData.asTypedList(outBlob.ref.cbData);
          return utf8.decode(outBytes);
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }
}
