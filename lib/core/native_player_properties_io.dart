import 'package:media_kit/media_kit.dart';

Future<void> setNativePlayerProperty(Object player, String name, String value) async {
  if (player is NativePlayer) await player.setProperty(name, value);
}
