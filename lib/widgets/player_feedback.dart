import 'package:flutter/material.dart';
import '../models/movie_content.dart';

enum PlayerFeedbackKind {
  seekBack,
  seekForward,
  volume,
  brightness,
  systemBrightness,
}

const playerControlsAutoHideDelay = Duration(seconds: 2);
const playerErrorGracePeriod = Duration(milliseconds: 1500);
const windowsResizeSettleDelay = Duration(milliseconds: 140);

bool compactPlayerControlsForWidth(double width) => width < 1180;

bool shouldCompactPlayerControls({
  required bool isDesktop,
  required double width,
}) => isDesktop && compactPlayerControlsForWidth(width);

int playerEpisodePickerColumns(double width) => switch (width) {
  >= 1000 => 6,
  >= 760 => 5,
  >= 540 => 4,
  >= 360 => 3,
  _ => 2,
};

String playerEpisodeQualityBadge(String quality) =>
    quality.startsWith('بدون برچسب کیفیت') ? 'نامشخص' : quality;

bool playbackContinuedAfterError({
  required Duration position,
  required Duration positionAtError,
}) => position > positionAtError + const Duration(milliseconds: 250);

double playerGestureValue(
  double current,
  double verticalDelta,
  double height,
) => (current - verticalDelta / height).clamp(0.0, 1.0);

bool playerTouchGesturesEnabled({
  required bool isAndroid,
  required bool isLocked,
  required bool controlsVisible,
}) {
  // Control visibility is deliberately not part of the decision: gestures
  // must keep working over the player chrome, while the touch lock disables
  // the complete gesture surface.
  return isAndroid && !isLocked;
}

bool shouldRestoreSystemBrightness(double value, Duration held) =>
    value <= .001 && held >= const Duration(milliseconds: 1500);

MovieEpisode? nextEpisodeFor(MovieContent content, MovieEpisode current) {
  if (content.kind == ContentKind.movie) return null;
  for (final season in content.seasons) {
    final currentIndex = season.episodes.indexWhere(
      (item) => item.id == current.id && item.fileUrl == current.fileUrl,
    );
    if (currentIndex < 0) continue;

    // API episode arrays are not guaranteed to be naturally sorted: a text
    // order can put 11 immediately after 1. Keep playback inside the selected
    // season/quality and compare every numeric chunk as a number.
    final ordered = season.episodes.indexed.toList()
      ..sort((a, b) {
        final result = compareEpisodeNamesNatural(a.$2.name, b.$2.name);
        return result != 0 ? result : a.$1.compareTo(b.$1);
      });
    final orderedIndex = ordered.indexWhere(
      (entry) =>
          entry.$2.id == current.id && entry.$2.fileUrl == current.fileUrl,
    );
    return orderedIndex >= 0 && orderedIndex + 1 < ordered.length
        ? ordered[orderedIndex + 1].$2
        : null;
  }
  return null;
}

int compareEpisodeNamesNatural(String left, String right) {
  String latinDigits(String value) => value
      .replaceAll('۰', '0')
      .replaceAll('۱', '1')
      .replaceAll('۲', '2')
      .replaceAll('۳', '3')
      .replaceAll('۴', '4')
      .replaceAll('۵', '5')
      .replaceAll('۶', '6')
      .replaceAll('۷', '7')
      .replaceAll('۸', '8')
      .replaceAll('۹', '9')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');

  final normalizedLeft = latinDigits(left);
  final normalizedRight = latinDigits(right);
  final leftNumbers = RegExp(r'\d+')
      .allMatches(normalizedLeft)
      .map((match) => int.parse(match.group(0)!))
      .toList();
  final rightNumbers = RegExp(r'\d+')
      .allMatches(normalizedRight)
      .map((match) => int.parse(match.group(0)!))
      .toList();
  for (
    var index = 0;
    index < leftNumbers.length && index < rightNumbers.length;
    index++
  ) {
    final result = leftNumbers[index].compareTo(rightNumbers[index]);
    if (result != 0) return result;
  }

  final leftParts = RegExp(
    r'\d+|\D+',
  ).allMatches(normalizedLeft).map((match) => match.group(0)!).toList();
  final rightParts = RegExp(
    r'\d+|\D+',
  ).allMatches(normalizedRight).map((match) => match.group(0)!).toList();
  for (
    var index = 0;
    index < leftParts.length && index < rightParts.length;
    index++
  ) {
    final leftNumber = int.tryParse(leftParts[index]);
    final rightNumber = int.tryParse(rightParts[index]);
    final result = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftParts[index].toLowerCase().compareTo(
            rightParts[index].toLowerCase(),
          );
    if (result != 0) return result;
  }
  return leftParts.length.compareTo(rightParts.length);
}

double nextEpisodeOverlayBottom(bool controlsVisible) =>
    controlsVisible ? 160 : 18;

bool shouldOfferNextEpisode(
  Duration position,
  Duration duration, {
  required bool hasNext,
}) {
  final remaining = duration - position;
  return hasNext &&
      duration > Duration.zero &&
      remaining > Duration.zero &&
      remaining <= const Duration(minutes: 2);
}

class PlayerFeedbackOverlay extends StatelessWidget {
  const PlayerFeedbackOverlay({super.key, required this.kind, this.value});
  final PlayerFeedbackKind kind;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      PlayerFeedbackKind.seekBack => Icons.replay_10_rounded,
      PlayerFeedbackKind.seekForward => Icons.forward_10_rounded,
      PlayerFeedbackKind.volume =>
        value == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      PlayerFeedbackKind.brightness => Icons.brightness_6_rounded,
      PlayerFeedbackKind.systemBrightness => Icons.brightness_auto_rounded,
    };
    final label = switch (kind) {
      PlayerFeedbackKind.seekBack => '۱۰ ثانیه عقب',
      PlayerFeedbackKind.seekForward => '۱۰ ثانیه جلو',
      PlayerFeedbackKind.volume => '${((value ?? 0) * 100).round()}%',
      PlayerFeedbackKind.brightness => '${((value ?? 0) * 100).round()}%',
      PlayerFeedbackKind.systemBrightness => 'نور خودکار سیستم',
    };
    return IgnorePointer(
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xD920232B),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: Colors.white),
              const SizedBox(height: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (value != null &&
                  kind != PlayerFeedbackKind.seekBack &&
                  kind != PlayerFeedbackKind.seekForward) ...[
                const SizedBox(height: 9),
                SizedBox(
                  width: 130,
                  child: LinearProgressIndicator(value: value),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
