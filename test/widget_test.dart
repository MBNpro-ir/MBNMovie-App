import 'package:mbnmovie/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sibling login requires pressing the login button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    var sharedReads = 0;
    await tester.pumpWidget(
      MbnmovieApp(
        sharedTokenReader: () async {
          sharedReads++;
          return null;
        },
      ),
    );
    expect(find.text('دنیای تماشا، دوباره روشن شد'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('خوش برگشتی'), findsOneWidget);
    expect(sharedReads, 0);

    // Neither the periodic account check nor returning to the app adopts a
    // sibling account. Only an explicit press reads its shared credential.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 7));
    expect(sharedReads, 0);
    final button = find.text('ورود با حساب MBNime');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(sharedReads, 1);
    expect(find.text('خوش برگشتی'), findsOneWidget);
    expect(
      find.text(
        'حساب فعالی در برنامه MBNime یافت نشد. ابتدا در MBNime وارد شوید.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
