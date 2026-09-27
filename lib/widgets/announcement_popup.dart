import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../services/mbn_auth.dart';

class AnnouncementService {
  static bool _showing = false;

  static Future<void> checkAndShow(BuildContext context, MbnAuth auth, {String app = 'movie'}) async {
    if (_showing) return;
    try {
      final res = await auth.getJson('/api/announcements', query: {'app': app});
      final list = (res['announcements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (list.isEmpty || !context.mounted) return;

      _showing = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _AnnouncementDialog(announcements: list),
      );
    } catch (_) {
      // Background check failure must be completely silent
    } finally {
      _showing = false;
    }
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog({required this.announcements});
  final List<Map<String, dynamic>> announcements;

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  int _currentIndex = 0;

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    final val = int.tryParse(cleaned, radix: 16);
    return val != null ? Color(val) : null;
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.announcements[_currentIndex];
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final mediaType = item['media_type']?.toString() ?? 'none';
    final mediaUrl = item['media_url']?.toString() ?? '';
    final buttons = (item['action_buttons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final count = widget.announcements.length;

    return Dialog(
      backgroundColor: const Color(0xFF1E212A),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: MovieColors.orange.withValues(alpha: .3), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF229ED9), Color(0xFF1E88E5)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.campaign_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 5),
                        Text(
                          'اطلاعیه',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (count > 1) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_currentIndex + 1} از $count',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Media Section
                    if (mediaType == 'image' && mediaUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          height: 200,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .04),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (mediaType == 'video' && mediaUrl.isNotEmpty) ...[
                      InkWell(
                        onTap: () => _launch(mediaUrl),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.deepPurple.shade900, Colors.black87],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 48),
                              SizedBox(height: 8),
                              Text('مشاهده ویدیوی اطلاعیه', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Title
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Content text
                    SelectableText(
                      content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFD1D5DB),
                        height: 1.7,
                      ),
                    ),

                    // Custom Action Buttons
                    if (buttons.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      for (final btn in buttons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ElevatedButton(
                            onPressed: () => _launch(btn['url']?.toString() ?? ''),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _parseColor(btn['bg_color']?.toString()) ?? const Color(0xFF229ED9),
                              foregroundColor: _parseColor(btn['text_color']?.toString()) ?? Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.open_in_new_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  btn['text']?.toString() ?? 'کلیک کنید',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Colors.white12),
            // Bottom bar with Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  if (count > 1) ...[
                    IconButton(
                      tooltip: 'قبلی',
                      onPressed: _currentIndex > 0 ? () => setState(() => _currentIndex--) : null,
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    ),
                    IconButton(
                      tooltip: 'بعدی',
                      onPressed: _currentIndex < count - 1 ? () => setState(() => _currentIndex++) : null,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('متوجه شدم'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
