import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/services/playback_activity.dart';

void main() {
  testWidgets(
    'nested players defer background work and Back preserves page state',
    (tester) async {
      var completed = false;
      final controller = TextEditingController(text: 'preserved');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextField(controller: controller),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const _PlayerLease(),
                      ),
                    ),
                    child: const Text('play'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'same page after Back');
      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      expect(PlaybackActivity.active, isTrue);
      PlaybackActivity.whenIdle().then((_) => completed = true);
      final nested = PlaybackActivity.hold();
      nested();
      nested();
      await tester.pump(const Duration(seconds: 1));
      expect(completed, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(PlaybackActivity.active, isFalse);
      expect(completed, isTrue);
      expect(find.text('same page after Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PlayerLease extends StatefulWidget {
  const _PlayerLease();
  @override
  State<_PlayerLease> createState() => _PlayerLeaseState();
}

class _PlayerLeaseState extends State<_PlayerLease> {
  late final VoidCallback release;
  @override
  void initState() {
    super.initState();
    release = PlaybackActivity.hold();
  }

  @override
  void dispose() {
    release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('player')));
}
