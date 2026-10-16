import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mbnmovie/widgets/server_status_gate.dart';

void main() {
  testWidgets('does not block taps while the status probe is pending', (
    tester,
  ) async {
    var taps = 0;
    ServerStatusGate.bypassForTesting = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerStatusGate(
          // Port 1 has no listener in the test environment, so this remains
          // in `checking` long enough to exercise the first-frame behavior.
          baseUrl: 'http://127.0.0.1:1',
          child: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('لمس'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('لمس'));
    await tester.pump();
    expect(taps, 1);

    ServerStatusGate.bypassForTesting = true;
    await tester.pumpWidget(const SizedBox());
  });
}
