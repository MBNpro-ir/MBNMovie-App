import '../core/app_platform.dart';
import 'package:flutter/foundation.dart';
import '../services/web_gateway.dart';
import '../services/browser_features.dart';
import 'package:flutter/material.dart';
import '../models/movie_content.dart';
import '../services/device_bridge.dart';
import '../services/download_manager.dart';
import '../services/external_apps.dart';
import '../screens/download_manager_screen.dart';

Future<void> showDownloadChoice(
  BuildContext context, {
  required MovieContent content,
  required MovieSeason season,
  required List<MovieEpisode> episodes,
}) async {
  if (kIsWeb) {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(height: 360, child: ListView(children: [
        const ListTile(title: Text('دانلود با مرورگر'), subtitle: Text('فایل‌ها در بخش Downloads مرورگر یا برنامه Files آیفون ذخیره می‌شوند. هر فایل را جدا انتخاب کن.')),
        for (final episode in episodes) ListTile(title: Text(episode.name), leading: const Icon(Icons.download),
          onTap: () async {
            try {
              final url = Uri.parse(await WebGateway.media(episode.fileUrl));
              final name = Uri.parse(episode.fileUrl).pathSegments.last;
              BrowserFeatures.download(url.replace(queryParameters: {...url.queryParameters, 'download': name}).toString(), name);
            } catch (e) {
              if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }),
      ]))));
    return;
  }
  final internal = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'با کدام دانلودر دانلود شود؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline),
            title: const Text('دانلودر داخلی (پیشنهادی)'),
            subtitle: const Text(
              'صف، توقف و ادامه، ذخیرهٔ مرتب و اعلان پیشرفت',
            ),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(
              Platform.isAndroid
                  ? 'دانلودر خارجی · ADM'
                  : 'دانلودر خارجی · IDM',
            ),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    ),
  );
  if (internal == null || !context.mounted) return;
  try {
    if (internal) {
      if (!await DeviceBridge.storageGranted()) {
        if (!context.mounted) return;
        final grant = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('دسترسی مدیریت فایل'),
            content: const Text(
              'برای دانلود مستقیم و مدیریت فایل‌ها در Downloads/MBNMovie باید دسترسی مدیریت فایل را فعال کنی. بدون این دسترسی دانلود داخلی در این مسیر ممکن نیست؛ پخش و دانلود خارجی همچنان قابل استفاده‌اند. پس از دادن دسترسی برگرد و دانلود را دوباره بزن.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('فعلاً نه'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تنظیم دسترسی'),
              ),
            ],
          ),
        );
        if (grant == true) await DeviceBridge.requestStorage();
        return;
      }
      final count = await DownloadManager.instance.add(
        content,
        season,
        episodes,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'فایل‌ها قبلاً دانلود شده‌اند یا در صف هستند؛ لینک‌ها را هم بررسی کن.'
                : '$count فایل به صف دانلود اضافه شد.',
          ),
          action: SnackBarAction(
            label: 'مدیریت دانلود ها',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const DownloadManagerScreen()),
            ),
          ),
        ),
      );
    } else {
      final result = await ExternalApps.downloadAll([
        for (final episode in episodes)
          (
            url: episode.fileUrl,
            fileName:
                '${content.title}-${season.name}-${episode.name}.${episode.fileType.isEmpty ? 'mp4' : episode.fileType}'
                    .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-'),
          ),
      ]);
      if (!context.mounted || result == ExternalLaunchResult.launched) return;
      if (result == ExternalLaunchResult.missing) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${Platform.isAndroid ? 'ADM' : 'IDM'} نصب نیست'),
            content: const Text(
              'می‌توانی دانلودر خارجی را نصب کنی یا از دانلودر داخلی استفاده کنی.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('بستن'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  ExternalApps.openOfficialDownload(
                    Platform.isAndroid
                        ? ExternalApps.admStoreUrl
                        : ExternalApps.idmDownloadUrl,
                  );
                },
                child: const Text('دانلود رسمی'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ارسال لینک انجام نشد؛ کیفیت دیگر یا دانلودر داخلی را امتحان کن.',
            ),
          ),
        );
      }
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'شروع دانلود انجام نشد؛ اینترنت، دسترسی فایل و فضای خالی را بررسی کن.',
          ),
        ),
      );
    }
  }
}
