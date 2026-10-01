import 'dart:math' as math;
import 'package:flutter/material.dart';

class PlayerHeaderAction {
  const PlayerHeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.button,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget button;
}

/// Keep one row and put only the actions that cannot fit into the menu.
class AdaptivePlayerHeader extends StatelessWidget {
  const AdaptivePlayerHeader({
    super.key,
    required this.back,
    required this.title,
    required this.actions,
    required this.onMenuOpened,
    required this.onMenuClosed,
  });
  final Widget back, title;
  final List<PlayerHeaderAction> actions;
  final VoidCallback onMenuOpened, onMenuClosed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const buttonSize = 50.0, gap = 8.0, leadingWidth = 64.0;
      final titleWidth = constraints.maxWidth < 500 ? 64.0 : 120.0;
      final slots = math.max(
        1,
        ((constraints.maxWidth - leadingWidth - titleWidth + gap) /
                (buttonSize + gap))
            .floor(),
      );
      final visible = actions.length <= slots
          ? actions.length
          : math.max(0, slots - 1);
      final hidden = actions.skip(visible).toList();
      return Row(
        children: [
          SizedBox(width: buttonSize, height: buttonSize, child: back),
          const SizedBox(width: 14),
          Expanded(child: title),
          for (final action in actions.take(visible)) ...[
            const SizedBox(width: gap),
            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: action.button,
            ),
          ],
          if (hidden.isNotEmpty) ...[
            const SizedBox(width: gap),
            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: PopupMenuButton<int>(
                key: const Key('player-header-overflow'),
                tooltip: 'گزینه‌های بیشتر',
                padding: EdgeInsets.zero,
                color: const Color(0xFF252A35),
                onOpened: onMenuOpened,
                onCanceled: onMenuClosed,
                onSelected: (index) {
                  onMenuClosed();
                  hidden[index].onTap();
                },
                itemBuilder: (_) => [
                  for (var i = 0; i < hidden.length; i++)
                    PopupMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          Icon(hidden[i].icon, color: Colors.white),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              hidden[i].label,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xCC252A35),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}
