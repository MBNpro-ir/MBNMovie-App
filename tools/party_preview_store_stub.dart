// The synthetic preview must never read or overwrite the normal app preferences.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:shared_preferences/shared_preferences.dart';

Future<void> isolatePreviewPreferences(String user) async {
  SharedPreferences.setMockInitialValues({});
}
