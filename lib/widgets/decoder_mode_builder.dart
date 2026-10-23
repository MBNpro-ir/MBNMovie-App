import 'package:flutter/material.dart';
import '../core/player_preferences.dart';
import '../core/video_decode_mode.dart';

/// Snapshot local preferences once, before constructing the native player.
/// Server changes apply on the next player route, never during playback.
class DecoderModeBuilder extends StatefulWidget {
  const DecoderModeBuilder({super.key, required this.builder});
  final Widget Function(VideoDecodeMode mode) builder;

  @override
  State<DecoderModeBuilder> createState() => _DecoderModeBuilderState();
}

class _DecoderModeBuilderState extends State<DecoderModeBuilder> {
  late final Future<VideoDecodeMode> _mode =
      PlaybackPreferenceStore.decoderMode();

  @override
  Widget build(BuildContext context) => FutureBuilder<VideoDecodeMode>(
    future: _mode,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return widget.builder(snapshot.data ?? VideoDecodeMode.hardware);
    },
  );
}
