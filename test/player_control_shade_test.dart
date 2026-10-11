import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mbnmovie/widgets/player_control_shade.dart';

void main() {
  testWidgets('control shade leaves the video center clear and hit-testable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          child: ColoredBox(
            color: Colors.white,
            child: PlayerControlShade(
              minimum: const EdgeInsets.only(top: 24, bottom: 20),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    expect(taps, 1);
    final paint = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(PlayerControlShade),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await tester.runAsync(() async {
      for (final size in [
        const Size(320, 180),
        const Size(844, 390),
        const Size(390, 844),
        const Size(1920, 1080),
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
        paint.paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int redAt(int y) =>
            pixels.getUint8((y * image.width + image.width ~/ 2) * 4);
        expect(redAt(1), lessThan(100));
        expect(redAt(image.height - 2), lessThan(100));
        for (final fraction in [.25, .4, .5, .6, .67]) {
          expect(
            redAt((image.height * fraction).floor()),
            255,
            reason: 'Middle of $size must stay clear',
          );
        }
        image.dispose();
        picture.dispose();
      }
    });
  });
}
