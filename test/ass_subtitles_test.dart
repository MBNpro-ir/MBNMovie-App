import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/ass_subtitles.dart';
import 'package:mbnmovie/core/player_preferences.dart';
import 'package:mbnmovie/widgets/subtitle_appearance_panel.dart';

const source = '''[Script Info]
PlayResX: 1280
PlayResY: 720
[V4+ Styles]
Format: Name, Fontname
Style: Default,Vazirmatn
[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:02.00,0:00:05.50,Default,{\\pos(300,100)\\c&H0000FF&}سلام, دنیا
''';

void main() {
  test(
    'ASS detection uses codec/file extension and preserves authored design and timing',
    () {
      expect(isAssTrack(SubtitleTrack('1', null, null, codec: 'ass')), isTrue);
      expect(
        isAssTrack(SubtitleTrack.uri('https://example.com/sub.SSA?ticket=1')),
        isTrue,
      );
      expect(
        isAssTrack(SubtitleTrack('1', 'Class English', null, codec: 'subrip')),
        isFalse,
      );
      expect(isAssDocument(source), isTrue);
      expect(isAssDocument('1\n00:00:01,000 --> 00:00:02,000\ntext'), isFalse);
      final adjusted = timedAss(source, delay: 1, scale: 2);
      expect(adjusted, contains('0:00:05.00,0:00:12.00'));
      expect(adjusted, contains(r'{\pos(300,100)\c&H0000FF&}سلام, دنیا'));
      expect(adjusted, contains('Style: Default,Vazirmatn'));
    },
  );
  test(
    'plain mode is default and original ASS preference persists independently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(SubtitlePreferences.fromStore(prefs).originalAss, isFalse);
      await prefs.setBool('sub_original_ass', true);
      final stored = SubtitlePreferences.fromStore(prefs);
      expect(stored.originalAss, isTrue);
      expect(stored.copyWith(size: 22).originalAss, isTrue);
    },
  );
  testWidgets(
    'ASS activation requires warning confirmation and plain mode restores controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      SubtitlePreferences? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleAppearancePanel(
              initial: const SubtitlePreferences(),
              assAvailable: true,
              onChanged: (p) => latest = p,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('original-ass-switch')));
      await tester.pumpAndSettle();
      expect(latest, isNull);
      expect(find.text('نمایش طراحی اصلی ASS'), findsOneWidget);
      await tester.tap(find.text('انصراف'));
      await tester.pumpAndSettle();
      expect(latest, isNull);
      await tester.tap(find.byKey(const Key('original-ass-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فعال کردن'));
      await tester.pumpAndSettle();
      expect(latest?.originalAss, isTrue);
      expect(
        tester.widget<AbsorbPointer>(find.byType(AbsorbPointer).last).absorbing,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('original-ass-switch')));
      await tester.pumpAndSettle();
      expect(latest?.originalAss, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 844.0]) {
    testWidgets('ASS option follows shadow at width $width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleAppearancePanel(
              initial: const SubtitlePreferences(),
              assAvailable: true,
              compactLayout: true,
              twoColumnLayout: width >= 600,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      final ass = find.byKey(const Key('original-ass-switch'));
      await tester.ensureVisible(ass);
      expect(
        tester.getTopLeft(ass).dy,
        greaterThan(
          tester.getBottomLeft(find.text('سایه و حاشیه برای خوانایی')).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('ASS option hidden for other subtitle formats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleAppearancePanel(
            initial: const SubtitlePreferences(),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('original-ass-switch')), findsNothing);
  });
}
