import 'package:mbnmovie/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('MBNMovie starts with its branded launch experience', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    var sharedReads = 0;
    await tester.pumpWidget(MbnmovieApp(sharedTokenReader: () async { sharedReads++; return null; }));
    // On Windows hosts the custom title bar renders an extra 'MBNMovie'
    // next to the splash brand mark, so accept one or more matches.
    expect(find.text('MBNMovie'), findsWidgets);
    expect(find.text('دنیای تماشا، دوباره روشن شد'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 5));
    // No saved session in tests: the server login gate is shown. Network is
    // unavailable in widget tests, so restore always fails here.
    expect(find.text('خوش برگشتی'), findsOneWidget);
    expect(sharedReads, greaterThanOrEqualTo(1));
    expect(find.text('ورود به MBNMovie'), findsOneWidget);
  });
}
