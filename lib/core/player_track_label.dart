/// Never expose a media URL or its authentication ticket as a track name.
String playerTrackLabel(
  String id,
  String? title,
  String? language, {
  String appName = 'MBNime',
}) {
  if (id == 'auto') return 'انتخاب خودکار';
  if (id == 'no') return 'خاموش';
  bool usable(String text) =>
      text.trim().isNotEmpty &&
      !RegExp(
        r'^(?:https?:|blob:|data:|file:)',
        caseSensitive: false,
      ).hasMatch(text.trim()) &&
      !text.contains('ticket=');
  final raw = title?.trim() ?? '';
  final lang = language?.trim().toLowerCase() ?? '';
  final name = usable(raw)
      ? raw.replaceAll(RegExp(r'anime\s*on', caseSensitive: false), appName)
      : '';
  final readable =
      const {
        'fa': 'فارسی',
        'fas': 'فارسی',
        'per': 'فارسی',
        'en': 'انگلیسی',
        'eng': 'انگلیسی',
        'ja': 'ژاپنی',
        'jpn': 'ژاپنی',
        'ar': 'عربی',
        'ara': 'عربی',
      }[lang] ??
      (usable(lang) && lang != 'und' ? lang : '');
  final parts = [name, readable].where((s) => s.isNotEmpty).toSet();
  if (parts.isNotEmpty) return parts.join(' · ');
  return int.tryParse(id) != null ? 'ترک $id' : 'ترک بدون نام';
}
