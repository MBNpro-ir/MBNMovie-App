import 'package:shared_preferences/shared_preferences.dart';

Future<void> writePreferenceBatch(
  SharedPreferences prefs, {
  required Map<String, Object> values,
  Iterable<String> remove = const <String>[],
}) async {
  for (final key in remove) {
    await prefs.remove(key);
  }
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is bool) {
      await prefs.setBool(entry.key, value);
    } else if (value is int) {
      await prefs.setInt(entry.key, value);
    } else if (value is double) {
      await prefs.setDouble(entry.key, value);
    } else if (value is String) {
      await prefs.setString(entry.key, value);
    } else {
      throw ArgumentError.value(
        value,
        entry.key,
        'Unsupported preference type',
      );
    }
  }
}
