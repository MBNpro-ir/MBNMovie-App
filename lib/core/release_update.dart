import 'dart:convert';

/// Only stable numeric tags are installable. Never compare versions as text.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);
  final int major, minor, patch;
  static AppVersion? parse(String text) {
    final match = RegExp(
      r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})(?:\+\d{1,10})?$',
    ).firstMatch(text);
    if (match == null) return null;
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class ReleaseUpdate {
  const ReleaseUpdate({
    required this.version,
    required this.notes,
    required this.url,
    required this.sha256,
    required this.size,
    required this.filename,
  });
  final AppVersion version;
  final String notes, sha256, filename;
  final Uri url;
  final int size;

  static ReleaseUpdate? fromGitHub(
    Map<String, dynamic> json, {
    required String repository,
    required String platform,
  }) {
    if (json['draft'] != false || json['prerelease'] != false) return null;
    final version = AppVersion.parse(json['tag_name'] as String? ?? '');
    if (version == null) return null;
    final extension = platform == 'Windows-x64' ? 'zip' : 'apk';
    final filename = 'MBNMovie-$platform-$version.$extension';
    for (final value in json['assets'] as List? ?? const []) {
      if (value is! Map ||
          value['name'] != filename ||
          value['state'] != 'uploaded') {
        continue;
      }
      final uri = Uri.tryParse(value['browser_download_url'] as String? ?? '');
      final digest = value['digest'] as String? ?? '';
      final size = value['size'];
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.path != '/$repository/releases/download/v$version/$filename' ||
          !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
          size is! int ||
          size <= 0 ||
          size > 1024 * 1024 * 1024) {
        return null;
      }
      return ReleaseUpdate(
        version: version,
        notes: json['body'] as String? ?? '',
        url: uri,
        sha256: digest.substring(7).toLowerCase(),
        size: size,
        filename: filename,
      );
    }
    return null;
  }

  String encode() => jsonEncode({
    'version': version.toString(),
    'notes': notes,
    'url': url.toString(),
    'sha256': sha256,
    'size': size,
    'filename': filename,
  });

  static ReleaseUpdate? fromStored(
    Map<String, dynamic> data, {
    required String repository,
    required String platform,
  }) => fromGitHub(
    {
      'tag_name': 'v${data['version']}',
      'draft': false,
      'prerelease': false,
      'body': data['notes'],
      'assets': [
        {
          'name': data['filename'],
          'state': 'uploaded',
          'browser_download_url': data['url'],
          'digest': 'sha256:${data['sha256']}',
          'size': data['size'],
        },
      ],
    },
    repository: repository,
    platform: platform,
  );
}

/// Windows archives must contain exactly one MBNMovie bundle, not arbitrary paths.
String safeBundlePath(String entry) {
  final name = entry.replaceAll('\\', '/');
  final parts = name.endsWith('/')
      ? name.substring(0, name.length - 1).split('/')
      : name.split('/');
  final reserved = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  );
  if (parts.length < 2 ||
      parts.first != 'MBNMovie' ||
      parts.any(
        (p) =>
            p.isEmpty ||
            p == '..' ||
            p == '.' ||
            p.contains(':') ||
            RegExp(r'[\x00-\x1f<>"|?*]').hasMatch(p) ||
            p.endsWith(' ') ||
            p.endsWith('.') ||
            reserved.hasMatch(p),
      )) {
    throw const FormatException('مسیر ناامن در بستهٔ بروزرسانی');
  }
  final relative = parts.skip(1).join('/');
  if (relative.isEmpty || relative.startsWith('/')) {
    throw const FormatException('مسیر خالی');
  }
  return relative;
}
