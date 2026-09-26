import 'package:flutter/material.dart';
import '../core/player_preferences.dart';
import '../services/device_bridge.dart';
import 'default_preference_prompt.dart';

Future<String?> showWirelessDisplaySheet(
  BuildContext context, {
  required Future<bool?> Function(String? initialDestination) onCast,
}) async {
  final preferred = await PlaybackPreferenceStore.defaultStreamer();
  if (!context.mounted) return null;
  if (preferred == PlaybackPreferenceStore.miracast) {
    return _openWirelessDisplay(context, recordUse: false);
  }
  if (preferred != PlaybackPreferenceStore.askEveryTime) {
    return await onCast(preferred) == true ? 'cast' : null;
  }
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const BackButtonIcon(),
                label: const Text('بازگشت'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'تلویزیون یا مانیتور بدون سیم',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.connected_tv),
              title: const Text('پخش مستقیم روی تلویزیون'),
              subtitle: const Text(
                'Chromecast / DLNA و دستگاه‌های پشتیبانی‌شده',
              ),
              onTap: () async {
                final connected = await onCast(null);
                if (connected == true && context.mounted) {
                  Navigator.pop(context, 'cast');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.screen_share),
              title: const Text('Wireless Display / Miracast'),
              subtitle: const Text(
                'اتصال نمایشگر از تنظیمات دستگاه و نمایش پلیر داخلی',
              ),
              onTap: () async {
                final result = await _openWirelessDisplay(context);
                if (result != null && context.mounted) {
                  Navigator.pop(context, result);
                }
              },
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                'Wireless Display را روی نمایشگر روشن کن. این روش به پشتیبانی سخت‌افزار و سیستم‌عامل نیاز دارد و ممکن است کل صفحه و اعلان‌های دستگاه را نمایش دهد. در بعضی گوشی‌ها Miracast پشتیبانی نمی‌شود.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _openWirelessDisplay(
  BuildContext context, {
  bool recordUse = true,
}) async {
  try {
    if (recordUse) {
      await maybeSuggestDefaultStreamer(
        context,
        value: PlaybackPreferenceStore.miracast,
        label: 'Wireless Display / Miracast',
      );
      if (!context.mounted) return null;
    }
    if (!await DeviceBridge.wirelessDisplay()) throw StateError('unsupported');
    if (!context.mounted) return null;
    final play = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اتصال نمایشگر'),
        content: const Text(
          'نمایشگر را در پنجرهٔ اتصال سیستم انتخاب کن. پس از اتصال، پخش داخلی را شروع کن. در Windows برای نمایش یکسان صفحه‌ها می‌توانی از Win+P و گزینهٔ Duplicate استفاده کنی.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('بازگشت'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('شروع پخش داخلی'),
          ),
        ],
      ),
    );
    return play == true ? 'wireless' : null;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'پنجرهٔ اتصال باز نشد. از تنظیمات Cast گوشی یا Win+K در Windows استفاده کن؛ دستگاه باید Miracast را پشتیبانی کند.',
          ),
        ),
      );
    }
    return null;
  }
}
