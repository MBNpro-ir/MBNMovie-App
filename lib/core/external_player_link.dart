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
  if (platform == 'windows' &&
      player == 'vlc' &&
      source.scheme == 'https' &&
      ['anime.mbnpro.ir', 'movie.mbnpro.ir'].contains(source.host) &&
      source.path == '/api/web/media' &&
      source.queryParameters['ticket']?.isNotEmpty == true) {
    return Uri(
      scheme: appScheme,
      host: 'vlc',
      queryParameters: {'url': source.toString()},
    );
  }
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
