import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/announcement_popup.dart';

class Notices extends MbnAuth {
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async => {
    'announcements': List.generate(
      3,
      (i) => {'title': 'Notice ${i + 1}', 'content': 'Body ${i + 1}'},
    ),
  };
}

void main() {
  testWidgets('three announcements require three separate acknowledgements', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final completed = AnnouncementService.checkAndShow(context, Notices());
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      expect(find.text('Notice $i'), findsOneWidget);
      expect(find.byTooltip('بعدی'), findsNothing);
      if (i < 3) expect(find.text('Notice ${i + 1}'), findsNothing);
      await tester.tap(find.text('متوجه شدم'));
      await tester.pumpAndSettle();
    }
    await completed;
    expect(find.byType(Dialog), findsNothing);
  });
}
