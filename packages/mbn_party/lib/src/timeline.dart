typedef PartyJson = Map<String, dynamic>;

int partyInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

String partyDigits(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹', arabic = '٠١٢٣٤٥٦٧٨٩';
  return value.split('').map((c) {
    final a = persian.indexOf(c), b = arabic.indexOf(c);
    return a >= 0
        ? '$a'
        : b >= 0
        ? '$b'
        : c;
  }).join();
}

int parsePartyTime(
  String hours,
  String minutes,
  String seconds, {
  int? durationMs,
}) {
  int number(String text) {
    text = partyDigits(text.trim());
    if (text.isEmpty) return 0;
    if (!RegExp(r'^\d{1,3}$').hasMatch(text)) {
      throw const FormatException('زمان را با عدد صحیح وارد کن.');
    }
    return int.parse(text);
  }

  final h = number(hours), m = number(minutes), s = number(seconds);
  if (m > 59 || s > 59 || h > 167) {
    throw const FormatException('دقیقه و ثانیه باید بین ۰ و ۵۹ باشند.');
  }
  final total = (h * 3600 + m * 60 + s) * 1000;
  if (durationMs != null && durationMs > 0 && total >= durationMs) {
    throw const FormatException('زمان شروع باید کمتر از مدت ویدیو باشد.');
  }
  return total;
}

String partyTime(int milliseconds) {
  final seconds = (milliseconds ~/ 1000).clamp(0, 604800);
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}

/// HTTP midpoint clock estimate. Lowest-RTT observations dominate; monotonic
/// local time prevents a device wall-clock adjustment from seeking the film.
class PartyClock {
  PartyClock({int Function()? localNow}) : _provided = localNow {
    _epoch = DateTime.now().millisecondsSinceEpoch;
    _watch.start();
  }
  final int Function()? _provided;
  final Stopwatch _watch = Stopwatch();
  late final int _epoch;
  double _offset = 0;
  int? _bestRtt;
  int get localNow => _provided?.call() ?? _epoch + _watch.elapsedMilliseconds;
  int get serverNow => (localNow + _offset).round();
  int? get bestRttMs => _bestRtt;

  void observe({
    required int sentMs,
    required int receivedMs,
    required int serverMs,
  }) {
    final rtt = receivedMs - sentMs;
    if (rtt < 0 || rtt > 10000) return;
    final offset = serverMs - (sentMs + receivedMs) / 2;
    if (_bestRtt == null || rtt <= _bestRtt!) {
      _offset = offset;
      _bestRtt = rtt;
    } else if (rtt <= _bestRtt! + 50) {
      _offset = _offset * .9 + offset * .1;
    }
  }

  int position(PartyJson session) {
    var value = partyInt(session['position_ms']);
    if (session['state'] == 'playing') {
      final speed = (session['rate'] as num?)?.toDouble() ?? 1;
      value +=
          ((serverNow - partyInt(session['anchor_ms'])).clamp(0, 604800000) *
                  speed)
              .round();
    }
    final duration = partyInt(session['duration_ms'], 604800000);
    return value.clamp(0, duration > 0 ? duration : 604800000);
  }
}
