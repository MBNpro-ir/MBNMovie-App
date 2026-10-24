// Non-production E2E against tools/party_preview_server.py on loopback.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:mbn_party/mbn_party.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../tools/party_preview.dart' as preview;

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!condition()) {
    debugPrint(
      'PARTY_QA_VISIBLE: ${tester.allWidgets.whereType<Text>().map((w) => w.data).whereType<String>().join(' | ')}',
    );
  }
  expect(condition(), true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Persian invite opens real player, waits, starts and accepts peer controls',
    (tester) async {
      debugPrint('PARTY_QA: starting preview');
      await preview.main();
      debugPrint('PARTY_QA: preview main returned');
      final initialClient = PartyHub.instance.client!;
      for (final session in initialClient.sessions.toList()) {
        if (partyInt(session['host_id']) == initialClient.userId) {
          await initialClient.command(
            session['id'].toString(),
            'end',
            clientId: partyNonce(),
          );
        }
      }
      await _until(
        tester,
        () => find.text('ارسال فیلم و دعوت به تماشا').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('ارسال فیلم و دعوت به تماشا'));
      debugPrint('PARTY_QA: tapped invite');
      await _until(
        tester,
        () => find.text('ارسال برای دوستان').evaluate().isNotEmpty,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('مریم').last);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('شروع تماشا با دوست از زمان دلخواه'));
      await tester.pump(const Duration(milliseconds: 350));
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '۰');
      await tester.enterText(fields.at(1), '۰');
      await tester.enterText(fields.at(2), '۲۰');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('ارسال').last);
      await _until(tester, () => find.byType(Video).evaluate().isNotEmpty);
      final player = tester.widget<Video>(find.byType(Video)).controller.player;
      final sender = PartyHub.instance.client!;
      await _until(
        tester,
        () => find.byType(WatchPartyBanner).evaluate().isNotEmpty,
      );
      final controller = tester
          .widget<WatchPartyBanner>(find.byType(WatchPartyBanner))
          .controller;
      await _until(tester, () => controller.prepared);
      await _until(tester, () => player.state.position.inMilliseconds >= 19200);
      expect(player.state.playing, false);
      expect(player.state.position.inMilliseconds, closeTo(20000, 800));
      final scope = sender.app;
      final identity =
          jsonDecode(
                (await http.get(
                  Uri.parse(
                    'http://127.0.0.1:18641/preview/identity?app=$scope&user=2',
                  ),
                )).body,
              )
              as Map;
      final peer = PartyClient(
        baseUrl: 'http://127.0.0.1:18641',
        app: scope,
        token: () => identity['token'].toString(),
      );
      final sid = controller.sessionId, peerId = partyNonce();
      await peer.command(sid, 'join', clientId: peerId);
      await peer.command(
        sid,
        'ready',
        clientId: peerId,
        duration: player.state.duration.inMilliseconds,
      );
      await _until(
        tester,
        () =>
            player.state.playing &&
            player.state.position.inMilliseconds > 20500,
      );
      var session = await peer.session(sid);
      await peer.command(
        sid,
        'pause',
        clientId: peerId,
        version: partyInt(session['version']),
        position: player.state.position.inMilliseconds,
      );
      await _until(
        tester,
        () => !player.state.playing && controller.status.contains('مریم'),
      );
      session = await peer.session(sid);
      await peer.command(
        sid,
        'seek',
        clientId: peerId,
        version: partyInt(session['version']),
        position: 45000,
      );
      await _until(
        tester,
        () =>
            player.state.position.inMilliseconds > 44000 &&
            player.state.position.inMilliseconds < 46000,
      );
      await sender.command(sid, 'end', clientId: controller.clientId);
      await _until(tester, () => controller.closed);
      expect(controller.status, contains('پارتی بسته شد'));
      await tester.pumpWidget(const SizedBox());
      PartyHub.instance.configure(null);
      peer.dispose();
      expect(tester.takeException(), isNull);
      debugPrint(
        'PARTY_NATIVE_E2E_OK app=$scope; Persian time=20s; peer pause/seek/end; real video',
      );
    },
  );
}
