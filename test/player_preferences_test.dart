import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/player_preferences.dart';
import 'package:mbnmovie/screens/settings_screen.dart';
import 'package:mbnmovie/widgets/default_preference_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('player suggestion appears once after more than three uses', () async {
    expect(await PlaybackPreferenceStore.recordPlayerUse('internal'), isFalse);
    expect(await PlaybackPreferenceStore.recordPlayerUse('internal'), isFalse);
    expect(await PlaybackPreferenceStore.recordPlayerUse('internal'), isFalse);
    expect(await PlaybackPreferenceStore.recordPlayerUse('internal'), isTrue);
    expect(await PlaybackPreferenceStore.recordPlayerUse('internal'), isFalse);
  });

  test('streamer suggestion appears once after more than two uses', () async {
    expect(await PlaybackPreferenceStore.recordStreamerUse('dlna'), isFalse);
    expect(await PlaybackPreferenceStore.recordStreamerUse('dlna'), isFalse);
    expect(await PlaybackPreferenceStore.recordStreamerUse('dlna'), isTrue);
    expect(await PlaybackPreferenceStore.recordStreamerUse('dlna'), isFalse);
  });

  test('configured default suppresses usage suggestions', () async {
    await PlaybackPreferenceStore.setDefaultPlayer('vlc');
    await PlaybackPreferenceStore.setDefaultStreamer('googleCast');
    expect(await PlaybackPreferenceStore.defaultPlayer(), 'vlc');
    expect(await PlaybackPreferenceStore.defaultStreamer(), 'googleCast');
    expect(await PlaybackPreferenceStore.recordPlayerUse('vlc'), isFalse);
    expect(
      await PlaybackPreferenceStore.recordStreamerUse('googleCast'),
      isFalse,
    );
  });

  test(
    'subtitle personalization round-trips through the shared model',
    () async {
      final prefs = await SharedPreferences.getInstance();
      const value = SubtitlePreferences(
        fontFamily: 'NotoNaskhArabic',
        size: 37,
        lineHeight: 1.7,
        color: Color(0xFFFFA000),
        backgroundColor: Color(0xFF3A3F4B),
        backgroundOpacity: .8,
        cornerRadius: 18,
        bottomPadding: 92,
        bold: false,
        shadow: false,
        delay: 1.25,
        timingScale: .95,
      );
      await value.save(prefs);
      final loaded = SubtitlePreferences.fromStore(prefs);
      expect(loaded.fontFamily, value.fontFamily);
      expect(loaded.size, value.size);
      expect(loaded.color, value.color);
      expect(loaded.delay, value.delay);
      expect(loaded.timingScale, value.timingScale);
    },
  );

  testWidgets('settings page exposes player, streamer and subtitle controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('پخش و انتقال پیش‌فرض'), findsOneWidget);
    expect(find.text('پخش‌کنندهٔ پیش‌فرض'), findsOneWidget);
    expect(find.text('روش انتقال تصویر پیش‌فرض'), findsOneWidget);
    expect(find.text('پلیر'), findsOneWidget);
    expect(find.text('زیرنویس'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('subtitle-two-line-preview')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('subtitle-two-line-preview')), findsOneWidget);
    expect(
      find.text(
        'این یک پیش‌نمایش زیرنویس فارسی است\nتغییرات خط دوم هم‌زمان نمایش داده می‌شود',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings page uses the wide layout without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('پخش و انتقال پیش‌فرض'), findsOneWidget);
    expect(find.byKey(const Key('subtitle-two-line-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('smart player suggestion can set the default', (tester) async {
    for (var i = 0; i < 3; i++) {
      await PlaybackPreferenceStore.recordPlayerUse('internal');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybeSuggestDefaultPlayer(
              context,
              value: 'internal',
              label: 'پلیر داخلی',
            ),
            child: const Text('انتخاب'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('انتخاب'));
    await tester.pumpAndSettle();
    expect(find.text('این پلیر را پیش‌فرض کنم؟'), findsOneWidget);
    expect(
      find.textContaining('از بخش تنظیمات قابل تغییر است'),
      findsOneWidget,
    );
    await tester.tap(find.text('پیش‌فرض شود'));
    await tester.pumpAndSettle();
    expect(
      await PlaybackPreferenceStore.defaultPlayer(),
      PlaybackPreferenceStore.internalPlayer,
    );
  });
}
