import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

Future<void> writePreferenceBatch(
  SharedPreferences prefs, {
  required Map<String, Object> values,
  Iterable<String> remove = const <String>[],
}) async {
  final store = SharedPreferencesStorePlatform.instance;
  if (store is SharedPreferencesWindows) {
    // SharedPreferences stores its legacy keys with the flutter. prefix.
    // Reload once so its public in-memory cache observes the single write.
    await store.updateValues({
      for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
    }, remove: remove.map((key) => 'flutter.$key'));
    await prefs.reload();
    return;
  }

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
