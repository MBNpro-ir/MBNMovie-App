import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/responsive_web_layout.dart';

void main() {
  testWidgets('panel with internal close has exactly one close action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerWebPanel(
            showCloseButton: false,
            child: IconButton(
              tooltip: 'بستن پنل',
              onPressed: () {},
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('بستن پنل'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
  testWidgets('phone sheet remains bounded with a long list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final closed = showResponsivePlayerPanel(
      compactLayout: true,
      context: context,
      builder: (_) => SizedBox(
        height: 2000,
        child: Column(
          children: [
            const Text('Panel heading'),
            Expanded(
              child: ListView(
                children: List.generate(40, (i) => Text('Item $i')),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getSize(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(box.width, lessThanOrEqualTo(366));
    expect(box.height, lessThanOrEqualTo(598));
    expect(tester.takeException(), isNull);
    Navigator.pop(tester.element(find.byType(BottomSheet)));
    await tester.pumpAndSettle();
    await closed;
  });

  testWidgets('preparation and buffering share exactly one indicator', (
    tester,
  ) async {
    final preparing = ValueNotifier(true);
    addTearDown(preparing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerLoadingIndicator(
            preparing: preparing,
            buffering: true,
            enabled: true,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('در حال آماده‌سازی پخش…'), findsOneWidget);
    preparing.value = false;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('در حال آماده‌سازی پخش…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1366, 768),
    const Size(1920, 1080),
  ]) {
    testWidgets('panel and subtitle actions fit $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: PlayerWebPanel(
              maxWidth: 840,
              child: SizedBox(
                height: 560,
                child: Column(
                  children: [
                    SubtitlePanelToolbar(
                      onReset: () {},
                      onSave: () => saved = true,
                    ),
                    Expanded(
                      child: ListView(
                        children: List.generate(
                          20,
                          (i) => ListTile(title: Text('Setting $i')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byKey(const Key('player-web-panel')));
      expect(panel.width, lessThanOrEqualTo(840));
      expect(panel.left, greaterThanOrEqualTo(20));
      expect(panel.right, lessThanOrEqualTo(size.width - 20));
      expect(
        tester.getBottomRight(find.text('ذخیره')).dy,
        lessThan(size.height),
      );
      await tester.tap(find.text('ذخیره'));
      expect(saved, isTrue);
    });
  }

  testWidgets('detail stays centered at readable width on a large monitor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveContentFrame(
            child: SizedBox.expand(key: Key('content')),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byKey(const Key('content')));
    expect(bounds.width, 1180);
    expect(bounds.center.dx, 960);
  });

  testWidgets('preparation replaces play and returns it when ready', (
    tester,
  ) async {
    final preparing = ValueNotifier(true);
    addTearDown(preparing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: preparing,
                builder: (_, value, _) => value
                    ? const PlaybackPreparationNotice()
                    : const SizedBox.shrink(),
              ),
              Center(
                child: PreparationControls(
                  preparing: preparing,
                  child: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                    tooltip: 'Play',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('در حال آماده‌سازی پخش…'), findsOneWidget);
    expect(find.byTooltip('Play'), findsNothing);
    preparing.value = false;
    await tester.pump();
    expect(find.text('در حال آماده‌سازی پخش…'), findsNothing);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
