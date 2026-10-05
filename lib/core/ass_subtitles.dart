import 'package:media_kit/media_kit.dart';

bool isAssTrack(SubtitleTrack track) {
  if (track.id == 'no') return false;
  final codec = track.codec?.toLowerCase();
  if (codec == 'ass' || codec == 'ssa') return true;
  return RegExp(
        r'\.(ass|ssa)(?:$|[?#])',
        caseSensitive: false,
      ).hasMatch(track.id) ||
      RegExp(r'\.(ass|ssa)$', caseSensitive: false).hasMatch(track.title ?? '');
}

bool isAssDocument(String source) =>
    RegExp(
      r'^\[V4\+? Styles\]',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(source.replaceAll('\r', '')) &&
    RegExp(
      r'^\[Events\]',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(source.replaceAll('\r', ''));

/// Preserve styles, drawing commands and overrides while adjusting cue timing.
String timedAss(String source, {double delay = 0, double scale = 1}) {
  var start = 1, end = 2;
  String timestamp(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 3) return text;
    final h = double.tryParse(parts[0]), m = double.tryParse(parts[1]);
    final s = double.tryParse(parts[2]);
    if (h == null || m == null || s == null) return text;
    final total = (((h * 3600 + m * 60 + s) * scale + delay) * 100)
        .round()
        .clamp(0, 999999999);
    return '${total ~/ 360000}:${((total ~/ 6000) % 60).toString().padLeft(2, '0')}:${((total ~/ 100) % 60).toString().padLeft(2, '0')}.${(total % 100).toString().padLeft(2, '0')}';
  }

  var events = false;
  return source
      .split('\n')
      .map((line) {
        final trimmed = line.trim();
        if (trimmed.startsWith('[')) {
          events = trimmed.toLowerCase() == '[events]';
        }
        if (!events) return line;
        if (trimmed.toLowerCase().startsWith('format:')) {
          final fields = trimmed
              .substring(7)
              .split(',')
              .map((s) => s.trim().toLowerCase())
              .toList();
          start = fields.indexOf('start');
          end = fields.indexOf('end');
        }
        if (!trimmed.toLowerCase().startsWith('dialogue:') ||
            start < 0 ||
            end < 0) {
          return line;
        }
        final fields = trimmed.substring(9).split(',');
        if (fields.length <= start || fields.length <= end) return line;
        fields[start] = timestamp(fields[start]);
        fields[end] = timestamp(fields[end]);
        return 'Dialogue: ${fields.join(',').trimLeft()}';
      })
      .join('\n');
}
