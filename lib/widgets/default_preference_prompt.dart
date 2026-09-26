import 'package:flutter/material.dart';

import '../core/player_preferences.dart';

Future<void> maybeSuggestDefaultPlayer(
  BuildContext context, {
  required String value,
  required String label,
}) async {
  final shouldSuggest = await PlaybackPreferenceStore.recordPlayerUse(value);
  if (!shouldSuggest || !context.mounted) return;
  final accepted = await _showSuggestion(
    context,
    title: 'این پلیر را پیش‌فرض کنم؟',
    message:
        'چند بار از «$label» استفاده کردی. می‌توانی آن را پخش‌کنندهٔ پیش‌فرض کنی تا از این به بعد ویدیوها مستقیم با آن باز شوند. این انتخاب همیشه از بخش تنظیمات قابل تغییر است.',
  );
  if (accepted == true) {
    await PlaybackPreferenceStore.setDefaultPlayer(value);
  }
}

Future<void> maybeSuggestDefaultStreamer(
  BuildContext context, {
  required String value,
  required String label,
}) async {
  final shouldSuggest = await PlaybackPreferenceStore.recordStreamerUse(value);
  if (!shouldSuggest || !context.mounted) return;
  final accepted = await _showSuggestion(
    context,
    title: 'این روش انتقال پیش‌فرض شود؟',
    message:
        'چند بار از «$label» برای انتقال تصویر استفاده کردی. می‌توانی آن را پیش‌فرض کنی تا دفعه‌های بعد مستقیم همین روش باز شود. این انتخاب از بخش تنظیمات قابل تغییر است.',
  );
  if (accepted == true) {
    await PlaybackPreferenceStore.setDefaultStreamer(value);
  }
}

Future<bool?> _showSuggestion(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<bool>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('فعلاً نه'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(dialogContext, true),
        icon: const Icon(Icons.push_pin_rounded),
        label: const Text('پیش‌فرض شود'),
      ),
    ],
  ),
);
