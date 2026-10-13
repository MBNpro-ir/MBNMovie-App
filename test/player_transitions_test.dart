import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/player_transitions.dart';

void main() {
  test('EOF is ignored when decoder reports it before the end', () {
    expect(
      isNaturalPlaybackEnd(
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 40),
        transitioning: false,
        seeking: false,
        hasError: false,
      ),
      isFalse,
    );
    expect(
      isNaturalPlaybackEnd(
        position: const Duration(minutes: 39, seconds: 59),
        duration: const Duration(minutes: 40),
        transitioning: false,
        seeking: false,
        hasError: false,
      ),
      isTrue,
    );
  });
  test('quality restore retries a decoder reset', () async {
    var position = Duration.zero;
    var seeks = 0, starts = 0;
    final result = await restorePlaybackPosition(
      requested: const Duration(minutes: 12),
      duration: () => const Duration(minutes: 40),
      position: () => position,
      seek: (value) async {
        seeks++;
        position = value;
      },
      start: () async {
        starts++;
        if (starts == 1) position = Duration.zero;
      },
      active: () => true,
      playing: true,
      wait: (_) async {
        if (starts > 1) position = const Duration(minutes: 12);
      },
    );
    expect(result, const Duration(minutes: 12));
    expect(seeks, 2);
  });
}
