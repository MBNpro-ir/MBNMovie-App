import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/title_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'English defaults once and explicit Persian choice survives reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      await TitleLanguage.initialize();
      expect(TitleLanguage.english, isTrue);
      expect(
        TitleLanguage.titleFor('6510', 'fallback').toLowerCase(),
        'five feet apart',
      );
      await TitleLanguage.setEnglish(false);
      await TitleLanguage.initialize();
      expect(TitleLanguage.english, isFalse);
      expect(TitleLanguage.titleFor('6510', 'fallback'), 'یک و نیم متر فاصله');
    },
  );
}
