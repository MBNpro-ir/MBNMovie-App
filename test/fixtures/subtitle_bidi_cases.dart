class SubtitleBidiCase {
  const SubtitleBidiCase(
    this.id,
    this.text, {
    this.ltr = const [],
    this.rtl = const [],
  });
  final String id, text;
  final List<(String, String)> ltr, rtl;
}

/// Map a visible token to its UTF-16 selection offsets, skipping invisible
/// bidi formatting characters inserted around/within a subtitle expression.
(int, int) subtitleTokenRange(String text, String token) {
  final visible = StringBuffer(), offsets = <int>[];
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x061C ||
        unit == 0x200E ||
        unit == 0x200F ||
        (unit >= 0x202A && unit <= 0x202E) ||
        (unit >= 0x2066 && unit <= 0x2069)) {
      continue;
    }
    visible.writeCharCode(unit);
    offsets.add(i);
  }
  final plain = visible.toString();
  final start = token == '.' ? plain.lastIndexOf(token) : plain.indexOf(token);
  if (start < 0) throw StateError('Missing token $token in $plain');
  return (offsets[start], offsets[start + token.length - 1] + 1);
}

const subtitleBidiCases = [
  SubtitleBidiCase(
    'legacy-two-line-screenshot',
    '،احتمالش زیاده مرخص بشه\n.باشه، خداحافظ',
    rtl: [('احتمالش', 'بشه'), ('باشه', 'خداحافظ'), ('خداحافظ', '.')],
  ),
  // Legacy logical sources reproduce the misplaced marks in the report.
  SubtitleBidiCase(
    'legacy-comma-screenshot',
    '،احتمالش زیاده مرخص بشه',
    rtl: [
      ('احتمالش', 'زیاده'),
      ('زیاده', 'مرخص'),
      ('مرخص', 'بشه'),
      ('بشه', '،'),
    ],
  ),
  SubtitleBidiCase(
    'legacy-period-screenshot',
    '.باشه، خداحافظ',
    rtl: [('باشه', '،'), ('،', 'خداحافظ'), ('خداحافظ', '.')],
  ),
  SubtitleBidiCase(
    'legacy-mixed-question',
    '؟نتیجه (MRI, CT) آماده است',
    ltr: [('MRI', ','), (',', 'CT')],
    rtl: [('نتیجه', 'MRI'), ('CT', 'آماده'), ('است', '؟')],
  ),
  SubtitleBidiCase(
    'legacy-dialogue',
    '!بالاخره خوش اومدی -',
    rtl: [
      ('-', 'بالاخره'),
      ('بالاخره', 'خوش'),
      ('خوش', 'اومدی'),
      ('اومدی', '!'),
    ],
  ),
  SubtitleBidiCase(
    'visual-order-mixed-acronym',
    'هم روی صورتت هست KS و نهایتا یه زخم',
    ltr: [('KS', 'و')],
    rtl: [
      ('و', 'نهایتا'),
      ('نهایتا', 'یه'),
      ('یه', 'زخم'),
      ('زخم', 'KS'),
      ('KS', 'هم'),
      ('هم', 'روی'),
      ('روی', 'صورتت'),
      ('صورتت', 'هست'),
    ],
  ),
  SubtitleBidiCase(
    'reported-persian',
    'آره، بچه های احمق خنگ.',
    rtl: [('آره', '،'), ('،', 'بچه'), ('بچه', 'خنگ'), ('خنگ', '.')],
  ),
  SubtitleBidiCase(
    'latin-list',
    'نتیجه (MRI, CT) آماده است.',
    ltr: [('MRI', ','), (',', 'CT')],
    rtl: [('نتیجه', 'MRI'), ('CT', 'آماده'), ('است', '.')],
  ),
  SubtitleBidiCase(
    'abbreviation',
    'سریال House (M.D.) را دیدم.',
    ltr: [('House', 'M.D')],
    rtl: [('سریال', 'House'), ('M.D', 'را'), ('دیدم', '.')],
  ),
  SubtitleBidiCase(
    'nested-brackets',
    'نتیجه (آزمایش MRI [T1, T2]) آماده است؟',
    ltr: [('MRI', 'T1'), ('T1', ','), (',', 'T2')],
    rtl: [
      ('نتیجه', 'آزمایش'),
      ('آزمایش', 'MRI'),
      ('T2', 'آماده'),
      ('است', '؟'),
    ],
  ),
  SubtitleBidiCase(
    'number-unit',
    'قیمت 12.50 USD است.',
    ltr: [('12.50', 'USD')],
    rtl: [('قیمت', '12.50'), ('USD', 'است'), ('است', '.')],
  ),
  SubtitleBidiCase(
    'resolution',
    'کیفیت 720p انتخاب شد.',
    ltr: [('720', 'p')],
    rtl: [('کیفیت', '720'), ('p', 'انتخاب'), ('شد', '.')],
  ),
  SubtitleBidiCase(
    'path',
    r'مسیر C:\Users\Ali\file.srt است.',
    ltr: [('C:', 'Users'), ('Users', 'Ali'), ('Ali', 'file.srt')],
    rtl: [('مسیر', 'C:'), ('file.srt', 'است'), ('است', '.')],
  ),
  SubtitleBidiCase(
    'url',
    'آدرس https://example.com/a?x=1&y=2 است.',
    ltr: [('https', 'example.com'), ('example.com', 'x=1'), ('x=1', 'y=2')],
    rtl: [('آدرس', 'https'), ('y=2', 'است'), ('است', '.')],
  ),
  SubtitleBidiCase(
    'version',
    'نسخه Windows 10, version 2.0 (x64) نصب شد.',
    ltr: [
      ('Windows', '10'),
      ('10', 'version'),
      ('version', '2.0'),
      ('2.0', 'x64'),
    ],
    rtl: [('نسخه', 'Windows'), ('x64', 'نصب'), ('شد', '.')],
  ),
  SubtitleBidiCase(
    'english',
    'Hello, world!',
    ltr: [('Hello', ','), (',', 'world'), ('world', '!')],
  ),
  SubtitleBidiCase(
    'negative-unit',
    'دما -12.5 C است.',
    ltr: [('-', '12.5'), ('12.5', 'C')],
    rtl: [('دما', '-'), ('C', 'است'), ('است', '.')],
  ),
  SubtitleBidiCase(
    'c-plus-plus',
    'زبان C++ است.',
    ltr: [('C', '++')],
    rtl: [('است', '.')],
  ),
  SubtitleBidiCase(
    'c-sharp',
    'زبان C# است.',
    ltr: [('C', '#')],
    rtl: [('است', '.')],
  ),
  SubtitleBidiCase(
    'quoted-english',
    'او گفت: «Hello, world!» و رفت.',
    ltr: [('Hello', ','), (',', 'world'), ('world', '!')],
    rtl: [('او', 'گفت'), ('گفت', 'Hello'), ('و', 'رفت'), ('رفت', '.')],
  ),
  SubtitleBidiCase(
    'presentation-forms',
    '\uFE81\uFEAD\uFEE9.',
    rtl: [('\uFE81', '\uFEAD'), ('\uFEAD', '\uFEE9'), ('\uFEE9', '.')],
  ),
];
