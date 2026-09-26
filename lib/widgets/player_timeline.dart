import 'package:flutter/material.dart';

/// Media time always increases left-to-right, independently of UI language.
class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.onSeek,
  });
  final Duration position, duration, buffer;
  final ValueChanged<Duration> onSeek;
  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  double? _drag;
  bool _showRemaining = false;
  @override
  Widget build(BuildContext context) {
    final length = widget.duration.inMilliseconds;
    final value =
        _drag ??
        (length <= 0
            ? 0.0
            : (widget.position.inMilliseconds / length).clamp(0.0, 1.0));
    final destination = Duration(milliseconds: (value * length).round());
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ExcludeSemantics(child: Text(playerTime(destination))),
                Semantics(
                  button: true,
                  label: _showRemaining ? 'زمان باقی‌مانده' : 'زمان کل',
                  child: InkWell(
                    key: const Key('player-duration-toggle'),
                    onTap: () =>
                        setState(() => _showRemaining = !_showRemaining),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      child: Text(
                        _showRemaining
                            ? '-${playerTime(remainingPlayerTime(destination, widget.duration))}'
                            : playerTime(widget.duration),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'زمان پخش',
            child: Slider(
              value: value,
              secondaryTrackValue: length <= 0
                  ? 0
                  : (widget.buffer.inMilliseconds / length).clamp(0.0, 1.0),
              label: playerTime(destination),
              semanticFormatterCallback: (_) =>
                  '${playerTime(destination)} / ${playerTime(widget.duration)}',
              onChangeStart: length <= 0
                  ? null
                  : (value) => setState(() => _drag = value),
              onChanged: length <= 0
                  ? null
                  : (value) => setState(() => _drag = value),
              onChangeEnd: length <= 0
                  ? null
                  : (value) {
                      setState(() => _drag = null);
                      widget.onSeek(
                        Duration(milliseconds: (value * length).round()),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
}

Duration remainingPlayerTime(Duration position, Duration duration) =>
    duration > position ? duration - position : Duration.zero;

String playerTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
