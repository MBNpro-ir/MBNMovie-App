import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/account_profile.dart';
import '../services/mbn_auth.dart';
import 'announcement_popup.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.profile, this.size = 82});
  final Map<String, dynamic> profile;
  final double size;
  @override
  Widget build(BuildContext context) {
    final hex = (profile['ring_color'] ?? '#64748B').toString().replaceFirst(
      '#',
      '',
    );
    final color = Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF64748B);
    final path = profile['avatar_url']?.toString() ?? '';
    final url = path.isEmpty
        ? ''
        : '${AccountProfile.server?.baseUrl ?? MbnAuth.defaultBaseUrl}$path';
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
      ),
      child: ClipOval(
        child: url.isEmpty
            ? ColoredBox(
                color: color.withValues(alpha: .12),
                child: Icon(
                  Icons.person_rounded,
                  size: size * .65,
                  color: color,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 512,
                errorBuilder: (_, e, s) =>
                    Icon(Icons.person_rounded, size: size * .65, color: color),
              ),
      ),
    );
  }
}

class DrawerAccountIdentity extends StatefulWidget {
  const DrawerAccountIdentity({
    super.key,
    required this.server,
    required this.openProfile,
  });
  final MbnAuth server;
  final VoidCallback openProfile;
  @override
  State<DrawerAccountIdentity> createState() => _DrawerAccountIdentityState();
}

class _DrawerAccountIdentityState extends State<DrawerAccountIdentity> {
  @override
  void initState() {
    super.initState();
    unawaitedReload();
  }

  Future<void> unawaitedReload() async {
    try {
      await AccountProfile.reload();
      await AccountProfile.flush();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: AccountProfile.current,
        builder: (context, p, _) => Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'نمایش دوبارهٔ اطلاعیه‌های آغاز برنامه',
                  icon: const Icon(Icons.info_outline_rounded, size: 19),
                  onPressed: () => AnnouncementService.checkAndShow(
                    context,
                    widget.server,
                    app: AccountProfile.app,
                    manual: true,
                  ),
                ),
                InkWell(
                  onTap: widget.openProfile,
                  borderRadius: BorderRadius.circular(60),
                  child: AccountAvatar(profile: p),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p['name']?.toString() ?? 'حساب من',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
}

class AccountProfilePanel extends StatefulWidget {
  const AccountProfilePanel({super.key});
  @override
  State<AccountProfilePanel> createState() => _AccountProfilePanelState();
}

class _AccountProfilePanelState extends State<AccountProfilePanel> {
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      await AccountProfile.reload();
      await AccountProfile.flush();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save(Map<String, dynamic> value) async {
    setState(() => _busy = true);
    try {
      await AccountProfile.save(value);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _name() async {
    var entered = AccountProfile.current.value['name']?.toString() ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نام نمایشی'),
        content: TextFormField(
          initialValue: entered,
          onChanged: (value) => entered = value,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'نام اکانت'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, entered),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (name != null && mounted) await _save({'name': name});
  }

  Future<void> _photo() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'عکس',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 4 * 1024 * 1024) {
        throw const FormatException('عکس باید کمتر از ۴ مگابایت باشد.');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 20000000) {
        descriptor.dispose();
        buffer.dispose();
        throw const FormatException('ابعاد عکس بیش از حد بزرگ است.');
      }
      final ratio =
          1024 /
          (descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * ratio.clamp(0.0, 1.0)).round().clamp(
          1,
          1024,
        ),
        targetHeight: (descriptor.height * ratio.clamp(0.0, 1.0)).round().clamp(
          1,
          1024,
        ),
      );
      descriptor.dispose();
      buffer.dispose();
      final frame = await codec.getNextFrame();
      codec.dispose();
      final im = frame.image;
      final side = im.width < im.height ? im.width : im.height;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        im,
        Rect.fromLTWH(
          (im.width - side) / 2,
          (im.height - side) / 2,
          side.toDouble(),
          side.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, 512, 512),
        Paint(),
      );
      final picture = recorder.endRecording();
      final square = await picture.toImage(512, 512);
      picture.dispose();
      im.dispose();
      final data = await square.toByteData(format: ui.ImageByteFormat.png);
      square.dispose();
      final cropped = data!.buffer.asUint8List();
      if (!mounted) return;
      final use = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ذخیرهٔ عکس مربع'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
            child: Image.memory(cropped),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ذخیرهٔ عکس'),
            ),
          ],
        ),
      );
      if (use == true && mounted) {
        await _save({'avatar_base64': base64Encode(cropped)});
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, dynamic>>(
    valueListenable: AccountProfile.current,
    builder: (context, p, _) {
      final stats = Map<String, dynamic>.from(p['stats'] as Map? ?? {});
      final badges = (p['badges'] as List? ?? []).cast<Map>();
      final minutes = ((stats['watch_ms'] as num? ?? 0) / 60000).floor();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            TextButton(onPressed: _reload, child: const Text('تلاش مجدد')),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'پروفایل شما',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'نمایش دوبارهٔ اطلاعیه‌های آغاز برنامه',
                        onPressed: AccountProfile.server == null
                            ? null
                            : () => AnnouncementService.checkAndShow(
                                context,
                                AccountProfile.server!,
                                app: AccountProfile.app,
                                manual: true,
                              ),
                        icon: const Icon(Icons.info_outline_rounded, size: 19),
                      ),
                      AccountAvatar(profile: p, size: 100),
                      const SizedBox(width: 48),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _photo,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('تغییر عکس'),
                      ),
                      if ((p['avatar_url'] ?? '') != '')
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _save({'remove_avatar': true}),
                          child: const Text('حذف عکس'),
                        ),
                    ],
                  ),
                  ListTile(
                    title: Text(p['name']?.toString() ?? 'حساب من'),
                    trailing: IconButton(
                      tooltip: 'ویرایش نام',
                      onPressed: _busy ? null : _name,
                      icon: const Icon(Icons.edit_rounded),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: p['gender']?.toString() ?? 'unset',
                    decoration: const InputDecoration(
                      labelText: 'جنسیت (اختیاری)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'unset', child: Text('ثبت نشده')),
                      DropdownMenuItem(value: 'male', child: Text('مرد')),
                      DropdownMenuItem(value: 'female', child: Text('زن')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) _save({'gender': v});
                          },
                  ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'آمار تماشای شما',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceAround,
                    children: [
                      _stat(
                        'زمان',
                        '${minutes ~/ 60} ساعت و ${minutes % 60} دقیقه',
                      ),
                      _stat('قسمت', '${stats['episodes'] ?? 0}'),
                      _stat('فیلم', '${stats['movies'] ?? 0}'),
                      _stat('سریال', '${stats['series'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'زمان پخش واقعی؛ هر فیلم یا قسمت پس از یک دقیقه تماشا شمرده می‌شود.',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'افتخارات شما',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (badges.isEmpty)
                    const Text('با تماشا، اولین مدالت را دریافت می‌کنی.'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final b in badges)
                        Chip(
                          avatar: Icon(
                            Icons.workspace_premium_rounded,
                            color: Color(
                              int.parse(
                                'FF${b['color'].toString().substring(1)}',
                                radix: 16,
                              ),
                            ),
                          ),
                          label: Text('${b['title']}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'مدال زمان: ۱، ۱۰ و ۵۰ ساعت • فیلم‌باز: ۱۰ فیلم • سریال‌باز: ۲۵ قسمت',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    },
  );
  Widget _stat(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: Colors.white60)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  );
}
