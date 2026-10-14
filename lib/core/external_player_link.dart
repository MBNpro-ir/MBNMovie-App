/// OS launch URLs contain a short-lived media ticket, never an account JWT.
Uri? externalPlayerLink({
  required String player,
  required String platform,
  required String url,
  required String title,
  required String appScheme,
}) {
  final source = Uri.tryParse(url);
  if (source == null ||
      !['https', 'http'].contains(source.scheme) ||
      source.host.isEmpty ||
      source.userInfo.isNotEmpty) {
    return null;
  }
  if (platform == 'ios' && player == 'vlc') {
    return Uri(
      scheme: 'vlc-x-callback',
      host: 'x-callback-url',
      path: '/stream',
      queryParameters: {'url': source.toString(), 'filename': title},
    );
  }
  // Classic VLC for Windows does not install a browser URL handler.
  // The web client uses a VLC-compatible playlist instead of opening MBN.
  if (platform == 'android') {
    final package = switch (player) {
      'vlc' => 'org.videolan.vlc',
      'mxPlayer' => 'com.mxtech.videoplayer.ad',
      'mxPlayerPro' => 'com.mxtech.videoplayer.pro',
      _ => null,
    };
    if (package == null || source.fragment.isNotEmpty) return null;
    return Uri.parse(
      'intent://${source.toString().split('://').last}'
      '#Intent;scheme=${source.scheme};package=$package;action=android.intent.action.VIEW;type=video/*;end',
    );
  }
  return null;
}

/// Only the short-lived relay ticket is exported, never an account credential.
String? externalPlayerPlaylist({required String url, required String title}) {
  final source = Uri.tryParse(url);
  if (source == null ||
      source.scheme != 'https' ||
      !['anime.mbnpro.ir', 'movie.mbnpro.ir'].contains(source.host) ||
      source.userInfo.isNotEmpty ||
      source.fragment.isNotEmpty ||
      source.path != '/api/web/media' ||
      source.queryParameters['ticket']?.isNotEmpty != true)
    return null;
  final label = title.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return '#EXTM3U\n#EXTENC:UTF-8\n#EXTINF:-1,$label\n${source.toString()}\n';
}
