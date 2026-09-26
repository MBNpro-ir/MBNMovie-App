import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lazy horizontal shelf with physical-direction navigation in both RTL/LTR.
class BrowsableShelf extends StatefulWidget {
  const BrowsableShelf({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.showNavigation,
    this.controller,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool showNavigation;

  /// Optional external controller (for auto-fill checks). When omitted an
  /// internal controller is used and disposed by this widget.
  final ScrollController? controller;

  @override
  State<BrowsableShelf> createState() => _BrowsableShelfState();
}

class _BrowsableShelfState extends State<BrowsableShelf> {
  ScrollController? _internal;
  ScrollController get _controller =>
      widget.controller ?? (_internal ??= ScrollController());

  void _page(bool forward) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels + (forward ? 1 : -1) * position.viewportDimension * .8)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 230,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final navigate =
            widget.showNavigation &&
            widget.itemCount * 160 + 28 > constraints.maxWidth;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        return Stack(
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                  },
                  scrollbars: false,
                ),
                child: ListView.separated(
                  controller: _controller,
                  padding: EdgeInsets.symmetric(horizontal: navigate ? 52 : 20),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: widget.itemBuilder,
                ),
              ),
            ),
            if (navigate)
              for (final left in [true, false])
                Positioned(
                  left: left ? 4 : null,
                  right: left ? null : 4,
                  top: 88,
                  child: IconButton.filledTonal(
                    tooltip: left == rtl ? 'موارد بعدی' : 'موارد قبلی',
                    onPressed: () => _page(left == rtl),
                    icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
                  ),
                ),
          ],
        );
      },
    ),
  );
}
