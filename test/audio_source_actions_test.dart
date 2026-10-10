import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mbnmovie/widgets/audio_source_actions.dart';

void main() {
  test(
    'audio URLs accept signed direct links but reject invalid schemes and hosts',
    () {
      expect(
        externalAudioUrl(' https://example.com/a.m4a?token=test ')?.query,
        'token=test',
      );
      for (final url in [
        '',
        'https:',
        'file:///a.mp3',
        'javascript:alert(1)',
        'https://user:pass@example.com/a',
      ]) {
        expect(externalAudioUrl(url), isNull);
      }
    },
  );
  testWidgets(
    'selected local audio is passed as external track with filename',
    (tester) async {
      AudioTrack? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: AudioSourceActions(
              pickFile: () async => XFile('C:/audio/dub.mp3'),
              onSelected: (track) async {
                selected = track;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('فایل'));
      await tester.pumpAndSettle();
      expect(selected?.uri, isTrue);
      expect(selected?.id, 'C:/audio/dub.mp3');
      expect(selected?.title, 'dub.mp3');
    },
  );
  testWidgets(
    'invalid link stays editable; valid link loads without leaking dialog controller',
    (tester) async {
      AudioTrack? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: AudioSourceActions(
              onSelected: (track) async {
                selected = track;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('لینک'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https:');
      await tester.tap(find.text('افزودن'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text('افزودن لینک صدا'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/dub.m4a',
      );
      await tester.tap(find.text('افزودن'));
      await tester.pumpAndSettle();
      expect(selected?.id, 'https://example.com/dub.m4a');
      expect(selected?.uri, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'file cancellation is silent and a playback error remains recoverable',
    (tester) async {
      var canceled = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: AudioSourceActions(
              pickFile: () async => canceled ? null : XFile('C:/audio/bad.mp3'),
              onSelected: (_) async => throw StateError('unreadable'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('فایل'));
      await tester.pumpAndSettle();
      expect(find.textContaining('صدا اضافه نشد'), findsNothing);
      canceled = false;
      await tester.tap(find.text('فایل'));
      await tester.pumpAndSettle();
      expect(find.textContaining('صدا اضافه نشد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
