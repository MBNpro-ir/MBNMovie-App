import 'dart:typed_data';

abstract final class BrowserFeatures {
  static Future<void> ass(
    String source, {
    List<String> fonts = const [],
  }) async {}
  static void clearAss() {}
  static bool get isMobileBrowser => false;
  static bool get isAndroidBrowser => false;
  static bool openExternal(Uri uri) => false;
  static void setAudioDelay(double value) {}
  static bool get isAppleMobile => false;
  static Future<bool> play({int? handle, bool Function()? active}) async =>
      false;
  static void attachVideo(Object video) {}
  static void detachVideo(Object video) {}
  static bool get castSupported => false;
  static bool get requiresCompatibleVideo => false;
  static void download(String url, String name) {}
  static void saveBytes(Uint8List bytes, String name, String mime) {}
  static Future<bool> fullscreen(bool value) async => false;
  static bool get pipSupported => false;
  static Future<bool> pip() async => false;
  static Future<bool> cast() async => false;
  static void subtitle(String vtt) {}
  static void clearSubtitle() {}
  static void stop() {}
  static void clearAudio() {}
  static void clearPlayPrompt() {}
  static void muteOriginal(bool value) {}
  static Future<void> externalAudio(String url, {double delay = 0}) async {}
}
