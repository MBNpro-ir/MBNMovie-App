import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/episode_catalog.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/widgets/player_season_selector.dart';

const seasons = [
  EpisodeSeasonGroup(id: 'one', name: 'فصل ۱', episodes: []),
  EpisodeSeasonGroup(id: 'two', name: 'فصل ۲', episodes: []),
  EpisodeSeasonGroup(id: 'three', name: 'فصل ۳', episodes: []),
];

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DevicePerformance.appleMobileWeb = false;
  });
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      testWidgets(
        '$platform season selector at $size preserves its player panel',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var selected = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => StatefulBuilder(
                        builder: (context, update) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: PlayerSeasonSelector(
                            seasons: seasons,
                            selectedIndex: selected,
                            onChanged: (value) =>
                                update(() => selected = value),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          if (platform == TargetPlatform.windows) {
            expect(find.byType(DropdownButtonFormField<int>), findsNothing);
            expect(find.byType(ChoiceChip), findsNWidgets(3));
            await tester.tap(find.text('فصل ۲'));
          } else {
            expect(find.byType(ChoiceChip), findsNothing);
            await tester.tap(find.byKey(const Key('player-season-dropdown')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('فصل ۲').last);
          }
          await tester.pumpAndSettle();
          expect(selected, 1);
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
  testWidgets('Apple web uses dropdown regardless of desktop host platform', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    DevicePerformance.appleMobileWeb = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerSeasonSelector(
            seasons: seasons,
            selectedIndex: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
