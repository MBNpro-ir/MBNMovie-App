import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/services/web_gateway.dart';

void main() {
  test(
    'offline direct media is limited to HTTPS browser-native containers',
    () {
      expect(canPlayDirectWhenOffline('https://cdn.example/a.MP4?key=1'), true);
      expect(canPlayDirectWhenOffline('https://cdn.example/a.m4v'), true);
      for (final url in [
        'http://cdn.example/a.mp4',
        'file:///a.mp4',
        'https://cdn.example/a.mkv',
        'https://cdn.example/a.m3u8',
        'https://cdn.example/stream?file=a.mp4',
      ]) {
        expect(canPlayDirectWhenOffline(url), false, reason: url);
      }
    },
  );
}
