Future<void> setNativePlayerProperty(
  Object player,
  String name,
  String value,
) async {}

Future<String?> getNativePlayerProperty(Object player, String name) async =>
    null;

Future<void> addNativeExternalTrack(
  Object player, {
  required String path,
  required String title,
  required bool subtitle,
  required bool select,
}) async {}
