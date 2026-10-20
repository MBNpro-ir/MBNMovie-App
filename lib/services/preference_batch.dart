import 'package:shared_preferences/shared_preferences.dart';

import 'preference_batch_stub.dart'
    if (dart.library.io) 'preference_batch_io.dart'
    as platform;

/// Writes a group of preferences without forcing one full-file write per key.
Future<void> writePreferenceBatch(
  SharedPreferences prefs, {
  required Map<String, Object> values,
  Iterable<String> remove = const <String>[],
}) => platform.writePreferenceBatch(prefs, values: values, remove: remove);
