import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/watch_clock.dart';

void main() {
  test(
    'actual playback excludes seeking, pauses, stalls and invalid rates',
    () {
      var now = 0;
      final clock = WatchClock(now: () => now);
      void tick(int position, {bool active = true, double rate = 1}) {
        clock.tick(
          Duration(milliseconds: position),
          active: active,
          rate: rate,
        );
      }

      tick(0);
      now = 1000;
      tick(1000);
      expect(clock.pending, 1000);
      now = 2000;
      tick(90000);
      expect(clock.pending, 1000); // seek
      now = 3000;
      tick(90000, active: false);
      now = 4000;
      tick(91000);
      expect(clock.pending, 1000); // first resumed tick
      now = 5000;
      tick(92000);
      expect(clock.pending, 2000);
      now = 6000;
      tick(92000);
      expect(clock.pending, 2000); // stall
      now = 7000;
      tick(94000, rate: 2);
      expect(clock.pending, 3000);
      now = 17000;
      tick(104000);
      expect(clock.pending, 3000); // background gap
      now = 18000;
      tick(105000, rate: 0);
      expect(clock.pending, 3000);
      expect(clock.take(), 3000);
      expect(clock.take(), 0);
    },
  );
}
