import 'dart:math' as math;

class VideoOutputSize {
  const VideoOutputSize(this.width, this.height);
  final int width;
  final int height;
}

/// Bound only the render surface; the source decoder and its quality stay
/// unchanged. Null bounds retain upstream behavior; never upscale the source.
VideoOutputSize boundedVideoOutput(int width, int height, {
  int? maxWidth, int? maxHeight,
}) {
  if (width <= 0 || height <= 0) return VideoOutputSize(width, height);
  var scale = 1.0;
  if (maxWidth != null && maxWidth > 0) scale = math.min(scale, maxWidth / width);
  if (maxHeight != null && maxHeight > 0) scale = math.min(scale, maxHeight / height);
  return VideoOutputSize(math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()));
}
