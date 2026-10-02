import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

class BrowserVideoView extends StatelessWidget {
  const BrowserVideoView({
    super.key,
    required this.player,
    required this.cover,
  });
  final Player player;
  final bool cover;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
