import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/release_update.dart';
import 'package:mbnmovie/services/app_updater.dart';
import 'package:mbnmovie/screens/update_screen.dart';
import 'release_update_test.dart' show releaseJson;

void main() {
  testWidgets('known update blocks the app with a non-dismissible gate', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'mbnmovie-mandatory-update-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final updater =
        AppUpdater.testing(
            currentVersion: '1.0.0',
            cacheDirectory: directory,
            route: (uri) => uri,
            platform: 'Windows-x64',
          )
          ..release = ReleaseUpdate.fromGitHub(
            releaseJson(version: '2.0.0'),
            repository: AppUpdater.repository,
            platform: 'Windows-x64',
          )
          ..phase = UpdatePhase.downloading
          ..progress = .42;
    await tester.pumpWidget(
      MaterialApp(
        home: MandatoryUpdateGate(
          updater: updater,
          child: const Scaffold(body: Text('محتوای برنامه')),
        ),
      ),
    );
    expect(find.text('به‌روزرسانی در حال دانلود است'), findsOneWidget);
    expect(find.text('42٪ دانلود شده'), findsOneWidget);
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
      isFalse,
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const Key('mandatory-update-blocked-content')),
          )
          .ignoring,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(390, 844), Size(1440, 900)]) {
    testWidgets('update screen is responsive at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: UpdateScreen()));
      await tester.pumpAndSettle();
      expect(find.text('به‌روزرسانی برنامه'), findsOneWidget);
      expect(find.text('وضعیت به‌روزرسانی'), findsOneWidget);
      expect(find.text('بررسی دوباره'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'fresh Windows cache reproduces old failure and creates unique stages',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mbnmovie-stage-regression-',
      );
      try {
        await expectLater(
          Directory('${root.path}/stage-').createTemp(),
          throwsA(isA<FileSystemException>()),
        );
        final first = await AppUpdater.createInstallStage(root);
        final second = await AppUpdater.createInstallStage(root);
        expect(await first.exists(), isTrue);
        expect(first.parent.path, root.path);
        expect(first.path, isNot(second.path));
        await first.delete();
        await second.delete();
      } finally {
        await root.delete();
      }
    },
  );

  for (final choice in ['درخواست دوباره', 'دانلود از گیت‌هاب', 'بعداً']) {
    testWidgets('denied install permission offers $choice', (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showInstallPermissionPrompt(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('اجازهٔ نصب لازم است'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(
        selected,
        choice == 'درخواست دوباره'
            ? 'retry'
            : choice == 'دانلود از گیت‌هاب'
            ? 'github'
            : null,
      );
    });
  }
}
