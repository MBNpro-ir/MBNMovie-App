// Browsers isolate each app's session by origin.
abstract final class CrossAppAuth {
  static bool isValidJwt(String? token) => token?.split('.').length == 3;
  static Future<void> saveSharedToken({required String token, required String email}) async {}
  static Future<void> clearSharedToken() async {}
  static Future<bool> hasSiblingSession({String siblingId = ''}) async => false;
  static Future<String?> readSiblingToken({String siblingId = ''}) async => null;
}
