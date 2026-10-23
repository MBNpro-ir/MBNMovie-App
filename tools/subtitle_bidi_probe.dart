// Render the production subtitle widget in CanvasKit for browser regression
// checks. Build this target separately; it is never used by the application.
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mbnmovie/core/subtitle_bidi.dart';
import 'package:mbnmovie/widgets/player_subtitle_text.dart';

import '../test/fixtures/subtitle_bidi_cases.dart';

final settings = ValueNotifier((
  index: 0,
  width: 760.0,
  rtl: true,
  font: 'Vazirmatn',
));
final subtitleKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final (family, asset) in [
    ('Vazirmatn', 'Vazirmatn-Regular.ttf'),
    ('NotoSansArabic', 'NotoSansArabic-Variable.ttf'),
    ('NotoNaskhArabic', 'NotoNaskhArabic-Variable.ttf'),
    ('MarkaziText', 'MarkaziText-Variable.ttf'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$asset'))).load();
  }
  globalContext.setProperty(
    'mbnSubtitleCount'.toJS,
    subtitleBidiCases.length.toJS,
  );
  globalContext.setProperty(
    'mbnSubtitleId'.toJS,
    ((JSNumber index) => subtitleBidiCases[index.toDartInt].id.toJS).toJS,
  );
  globalContext.setProperty(
    'mbnSubtitleSet'.toJS,
    ((JSNumber index, JSNumber width, JSBoolean rtl, JSString font) {
      settings.value = (
        index: index.toDartInt,
        width: width.toDartDouble,
        rtl: rtl.toDart,
        font: font.toDart,
      );
    }).toJS,
  );
  globalContext.setProperty(
    'mbnSubtitleState'.toJS,
    (() {
      final paragraph = subtitleKey.currentContext?.findRenderObject();
      if (paragraph is! RenderParagraph || !paragraph.hasSize) return '{}'.toJS;
      final sample = subtitleBidiCases[settings.value.index];
      final text = paragraph.text.toPlainText();
      final expected = subtitleDisplayText([
        sample.canonicalText,
      ], normalized: true);
      if (text != expected ||
          paragraph.text.style?.fontFamily != settings.value.font) {
        return '{}'.toJS;
      }
      Map<String, double>? box(String token) {
        final (start, end) = subtitleTokenRange(text, token);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
          boxHeightStyle: ui.BoxHeightStyle.max,
        );
        if (boxes.isEmpty) return null;
        final rect = boxes.first.toRect();
        return {'x': rect.center.dx, 'y': rect.top};
      }

      final pairs = [
        for (final (rtl, pairs) in [(false, sample.ltr), (true, sample.rtl)])
          for (final (first, second) in pairs)
            {
              'first': first,
              'second': second,
              'rtl': rtl,
              'a': box(first),
              'b': box(second),
            },
      ];
      if (pairs.any((pair) => pair['a'] == null || pair['b'] == null))
        return '{}'.toJS;
      return jsonEncode({
        'id': sample.id,
        'width': paragraph.size.width,
        'font': settings.value.font,
        'pairs': pairs,
      }).toJS;
    }).toJS,
  );
  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: settings,
          builder: (_, value, _) => Directionality(
            textDirection: value.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: value.width,
                child: PlayerSubtitleText(
                  key: subtitleKey,
                  lines: [subtitleBidiCases[value.index].canonicalText],
                  normalized: true,
                  style: TextStyle(
                    fontFamily: value.font,
                    fontSize: 24,
                    color: Colors.yellow,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
