import 'package:flutter_test/flutter_test.dart';
import 'package:mbn_party/mbn_party.dart';

void main() {
  test('Persian and Arabic time digits and short videos', () {
    expect(parsePartyTime('', '۰۲', '٣٠', durationMs: 180000), 150000);
    expect(parsePartyTime('0', '0', '0'), 0);
    for (final values in [
      ('1', '0', '0'),
      ('', '60', '0'),
      ('', '', '60'),
      ('-1', '', ''),
      ('168', '', ''),
      ('', '1.5', ''),
    ]) {
      expect(
        () =>
            parsePartyTime(values.$1, values.$2, values.$3, durationMs: 180000),
        throwsFormatException,
      );
    }
    expect(
      () => parsePartyTime('', '3', '', durationMs: 180000),
      throwsFormatException,
    );
  });
  test(
    'Midpoint clock rejects slower asymmetric samples; play respects rate and duration',
    () {
      var now = 1000;
      final clock = PartyClock(localNow: () => now);
      clock.observe(sentMs: 1000, receivedMs: 1100, serverMs: 2050);
      expect(clock.bestRttMs, 100);
      now = 2000;
      expect(clock.serverNow, 3000);
      clock.observe(sentMs: 1000, receivedMs: 2000, serverMs: 9000);
      expect(clock.serverNow, 3000);
      final playing = {
        'state': 'playing',
        'position_ms': 10000,
        'anchor_ms': 2000,
        'duration_ms': 12000,
        'rate': 1.5,
      };
      expect(clock.position(playing), 11500);
      now = 4000;
      expect(clock.position(playing), 12000);
      expect(clock.position({...playing, 'state': 'paused'}), 10000);
      expect(clock.position({...playing, 'anchor_ms': 10000}), 10000);
    },
  );
}
