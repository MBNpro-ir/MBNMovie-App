// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

class _Paths extends PathProviderWindows {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

Future<void> isolatePreviewPreferences(String user) async {
  if (Platform.isWindows) {
    final path = '${Directory.systemTemp.path}/mbn-party-preview-movie-$user';
    await Directory(path).create(recursive: true);
    SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
      ..pathProvider = _Paths(path);
  } else {
    SharedPreferences.setMockInitialValues({});
  }
}
