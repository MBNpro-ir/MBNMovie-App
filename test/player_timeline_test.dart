import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/widgets/player_feedback.dart';
import 'package:mbnmovie/widgets/player_keyboard.dart';
import 'package:mbnmovie/widgets/player_timeline.dart';

void main() {
  testWidgets(
    'Persian player: right advances ten seconds and timeline increases to right',
    (tester) async {
      var position = const Duration(seconds: 30);
      const duration = Duration(seconds: 100);
      await tester.pumpWidget(
        MaterialApp(
          theme: MovieTheme.dark,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => PlayerKeyboard(
                  onCommand: (command) => update(() {
                    if (command == PlayerCommand.forward ||
                        command == PlayerCommand.back) {
                      position = playerSeekTarget(
                        position,
                        duration,
                        command == PlayerCommand.forward ? 10 : -10,
                      );
                    }
                  }),
                  onFocus: () {},
                  onSeekFraction: (_) {},
                  child: Center(
                    child: SizedBox(
                      width: 340,
                      child: PlayerTimeline(
                        position: position,
                        duration: duration,
                        buffer: const Duration(seconds: 80),
                        onSeek: (value) => update(() => position = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final slider = find.byType(Slider);
      expect(Directionality.of(tester.element(slider)), TextDirection.ltr);
      expect(SliderTheme.of(tester.element(slider)).trackGap, 6);
      expect(
        tester.getCenter(find.text('00:30')).dx,
        lessThan(tester.getCenter(find.text('01:40')).dx),
      );
      expect(
        tester.getTopLeft(find.text('00:30')).dy,
        lessThan(tester.getTopLeft(slider).dy),
      );
      await tester.tap(find.byKey(const Key('player-duration-toggle')));
      await tester.pump();
      expect(find.text('-01:10'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, const Duration(seconds: 40));
      expect(tester.widget<Slider>(slider).value, .4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(position, const Duration(seconds: 30));
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + rect.width * .8, rect.center.dy));
      await tester.pumpAndSettle();
      expect(position.inSeconds, greaterThan(65));
      final before = position;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, before + const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );
  test('seek clamps at start and end without reversing direction', () {
    expect(
      playerSeekTarget(
        const Duration(seconds: 5),
        const Duration(seconds: 100),
        -10,
      ),
      Duration.zero,
    );
    expect(
      playerSeekTarget(
        const Duration(seconds: 95),
        const Duration(seconds: 100),
        10,
      ),
      const Duration(seconds: 100),
    );
  });
  test('gestures, brightness hold, and next episode stay deterministic', () {
    expect(playerControlsAutoHideDelay, const Duration(seconds: 2));
    expect(playerErrorGracePeriod, const Duration(milliseconds: 1500));
    expect(windowsResizeSettleDelay, const Duration(milliseconds: 140));
    expect(compactPlayerControlsForWidth(980), isTrue);
    expect(compactPlayerControlsForWidth(1179), isTrue);
    expect(compactPlayerControlsForWidth(1180), isFalse);
    expect(shouldCompactPlayerControls(isDesktop: false, width: 500), isFalse);
    expect(shouldCompactPlayerControls(isDesktop: true, width: 500), isTrue);
    expect(playerEpisodePickerColumns(320), 2);
    expect(playerEpisodePickerColumns(390), 3);
    expect(playerEpisodePickerColumns(720), 4);
    expect(playerEpisodePickerColumns(900), 5);
    expect(playerEpisodePickerColumns(1200), 6);
    expect(playerEpisodeQualityBadge('بدون برچسب کیفیت'), 'نامشخص');
    expect(playerEpisodeQualityBadge('بدون برچسب کیفیت · سرور 2'), 'نامشخص');
    expect(playerEpisodeQualityBadge('720p'), '720p');
    expect(
      playbackContinuedAfterError(
        position: const Duration(seconds: 1),
        positionAtError: Duration.zero,
      ),
      isTrue,
    );
    expect(
      playbackContinuedAfterError(
        position: const Duration(seconds: 10),
        positionAtError: const Duration(seconds: 9),
      ),
      isTrue,
    );
    expect(
      playbackContinuedAfterError(
        position: const Duration(seconds: 9),
        positionAtError: const Duration(seconds: 9),
      ),
      isFalse,
    );
    expect(
      playerTouchGesturesEnabled(
        isAndroid: true,
        isLocked: false,
        controlsVisible: true,
      ),
      isTrue,
    );
    expect(
      playerTouchGesturesEnabled(
        isAndroid: true,
        isLocked: true,
        controlsVisible: false,
      ),
      isFalse,
    );
    expect(playerGestureValue(.5, -50, 100), 1);
    expect(playerGestureValue(.5, 75, 100), 0);
    expect(
      shouldRestoreSystemBrightness(0, const Duration(milliseconds: 1500)),
      isTrue,
    );
    expect(
      shouldRestoreSystemBrightness(0, const Duration(milliseconds: 1499)),
      isFalse,
    );
    const first = MovieEpisode(id: '1', name: '1', fileUrl: 'one');
    const second = MovieEpisode(id: '2', name: '2', fileUrl: 'two');
    const content = MovieContent(
      id: 'x',
      title: '',
      subtitle: '',
      description: '',
      year: 0,
      rating: 0,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(id: 's', name: '', episodes: [first, second]),
      ],
    );
    expect(nextEpisodeFor(content, first), second);
    expect(nextEpisodeFor(content, second), isNull);
    const tenth = MovieEpisode(id: '10', name: '*10', fileUrl: 'ten');
    const eleventh = MovieEpisode(id: '11', name: '*11', fileUrl: 'eleven');
    const third = MovieEpisode(id: '3', name: '*۳', fileUrl: 'three');
    const unsortedContent = MovieContent(
      id: 'natural',
      title: '',
      subtitle: '',
      description: '',
      year: 0,
      rating: 0,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'selected-quality',
          name: '',
          episodes: [first, eleventh, tenth, third, second],
        ),
        MovieSeason(id: 'other-quality', name: '', episodes: [eleventh]),
      ],
    );
    expect(nextEpisodeFor(unsortedContent, first), second);
    expect(nextEpisodeFor(unsortedContent, second), third);
    expect(nextEpisodeFor(unsortedContent, tenth), eleventh);
    expect(nextEpisodeFor(unsortedContent, eleventh), isNull);
    expect(compareEpisodeNamesNatural('قسمت ۲', 'قسمت 11'), lessThan(0));
    expect(nextEpisodeOverlayBottom(true), 160);
    expect(nextEpisodeOverlayBottom(false), 18);
    expect(
      shouldOfferNextEpisode(
        const Duration(minutes: 8),
        const Duration(minutes: 10),
        hasNext: true,
      ),
      isTrue,
    );
    expect(
      shouldOfferNextEpisode(
        const Duration(minutes: 7, seconds: 59),
        const Duration(minutes: 10),
        hasNext: true,
      ),
      isFalse,
    );
  });
}
