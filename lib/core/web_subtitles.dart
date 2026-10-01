class WebSubtitleCue {
  const WebSubtitleCue(this.start, this.end, this.text);
  final double start, end;
  final String text;
}

/// Plain-text SRT, WebVTT and ASS cues for the existing Persian subtitle overlay.
class WebSubtitleDocument {
  WebSubtitleDocument(List<WebSubtitleCue> source)
    : cues = List.of(source)..sort((a, b) => a.start.compareTo(b.start)) {
    var maximum = double.negativeInfinity;
    for (final cue in cues) {
      if (cue.end > maximum) maximum = cue.end;
      _endPrefixes.add(maximum);
    }
  }
  final List<WebSubtitleCue> cues;
  final List<double> _endPrefixes = [];
  static double _time(String value) {
    final parts = value
        .trim()
        .replaceAll(',', '.')
        .split(':')
        .map(double.tryParse)
        .toList();
    if (parts.any((p) => p == null)) return 0;
    return parts.fold<double>(0, (sum, part) => sum * 60 + part!);
  }

  static String _plain(String text) => text
      .replaceAll(RegExp(r'\{[^}]*\}|<[^>]*>'), '')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
  factory WebSubtitleDocument.parse(String source) {
    final normalized = source.replaceAll('\r', '').replaceAll('\uFEFF', '');
    final cues = <WebSubtitleCue>[];
    for (final line in normalized.split('\n')) {
      if (line.startsWith('Dialogue:')) {
        final parts = line.substring(9).trim().split(',');
        if (parts.length >= 10) {
          cues.add(
            WebSubtitleCue(
              _time(parts[1]),
              _time(parts[2]),
              _plain(parts.skip(9).join(',')),
            ),
          );
        }
      }
    }
    if (cues.isEmpty) {
      for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
        final lines = block.split('\n');
        final index = lines.indexWhere((line) => line.contains('-->'));
        if (index < 0 || index + 1 >= lines.length) continue;
        final times = lines[index].split('-->');
        cues.add(
          WebSubtitleCue(
            _time(times[0]),
            _time(times[1].trim().split(' ').first),
            _plain(lines.skip(index + 1).join('\n')),
          ),
        );
      }
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    if (cues.isEmpty) {
      throw const FormatException('فایل زیرنویس SRT، VTT یا ASS معتبر نیست.');
    }
    return WebSubtitleDocument(cues);
  }
  List<String> at(Duration position, {double delay = 0, double scale = 1}) {
    final time = (position.inMilliseconds / 1000 - delay) / scale;
    var low = 0, high = cues.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (cues[middle].start <= time) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final result = <String>[];
    for (
      var index = low - 1;
      index >= 0 && _endPrefixes[index] > time;
      index--
    ) {
      final cue = cues[index];
      if (cue.end > time) result.add(cue.text);
    }
    return result.reversed.toList(growable: false);
  }

  String vtt({double delay = 0, double scale = 1}) {
    String time(double seconds) {
      final ms = (seconds * 1000).round().clamp(0, 1 << 40);
      return '${(ms ~/ 3600000).toString().padLeft(2, '0')}:${(ms ~/ 60000 % 60).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
    }

    return 'WEBVTT\n\n${cues.map((c) => '${time(c.start * scale + delay)} --> ${time(c.end * scale + delay)}\n${c.text}').join('\n\n')}\n';
  }
}
