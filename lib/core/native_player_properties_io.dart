import 'package:media_kit/media_kit.dart';

Future<void> setNativePlayerProperty(
  Object player,
  String name,
  String value,
) async {
  if (player is NativePlayer) await player.setProperty(name, value);
}

Future<String?> getNativePlayerProperty(Object player, String name) async =>
    player is NativePlayer ? await player.getProperty(name) : null;

Future<void> addNativeExternalTrack(
  Object player, {
  required String path,
  required String title,
  required bool subtitle,
  required bool select,
}) async {
  if (player is NativePlayer) {
    await player.command([
      subtitle ? 'sub-add' : 'audio-add',
      path,
      select ? 'cached' : 'auto',
      title,
    ]);
  }
}
