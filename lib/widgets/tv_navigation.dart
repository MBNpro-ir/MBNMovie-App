import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/platform_ui.dart';

/// Remote OK uses ActivateIntent just like Enter on a keyboard. Keep arrows
/// directional so focus can move spatially through shelves and dialogs.
class TvNavigation extends StatelessWidget {
  const TvNavigation({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isAndroidTv) return child;
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(navigationMode: NavigationMode.directional),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: child,
        ),
      ),
    );
  }
}
