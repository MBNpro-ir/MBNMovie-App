import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;
import '../services/browser_features.dart';

/// Keep Safari's hardware video surface at the viewport's CSS size. No
/// intrinsic-resolution FittedBox, Flutter transform or opacity wraps it.
class BrowserVideoView extends StatefulWidget {
  const BrowserVideoView({
    super.key,
    required this.player,
    required this.cover,
  });
  final Player player;
  final bool cover;
  @override
  State<BrowserVideoView> createState() => _BrowserVideoViewState();
}

class _BrowserVideoViewState extends State<BrowserVideoView> {
  late final Future<int> _handle = widget.player.handle;
  web.HTMLVideoElement? _video;
  void _styleVideo() {
    final video = _video;
    if (video == null) return;
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = widget.cover ? 'cover' : 'contain'
      ..pointerEvents = 'none';
    video.setAttribute('playsinline', '');
    video.setAttribute('webkit-playsinline', '');
  }

  @override
  void didUpdateWidget(BrowserVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) _styleVideo();
  }

  @override
  void dispose() {
    final video = _video;
    if (video != null) BrowserFeatures.detachVideo(video);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _handle,
    builder: (context, snapshot) {
      final handle = snapshot.data;
      if (handle == null) return const SizedBox.shrink();
      return HtmlElementView.fromTagName(
        tagName: 'div',
        onElementCreated: (element) {
          final host = element as web.HTMLDivElement;
          final instances = globalContext.getProperty<JSObject>(
            r'$com.alexmercerind.media_kit.instances'.toJS,
          );
          final video = instances.getProperty<web.HTMLVideoElement>(
            handle.toString().toJS,
          );
          _video = video;
          host.style
            ..width = '100%'
            ..height = '100%'
            ..backgroundColor = 'black'
            ..pointerEvents = 'none';
          _styleVideo();
          host.appendChild(video);
          BrowserFeatures.attachVideo(video);
        },
      );
    },
  );
}
