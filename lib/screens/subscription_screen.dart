import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';

/// Reads the current account from the server each time the page opens.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.loadProfile});

  final Future<Map<String, dynamic>> Function() loadProfile;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static final _support = Uri.parse('https://t.me/mbnproo');
  late Future<Map<String, dynamic>> _profile = widget.loadProfile();

  Future<void> _reload() async {
    final next = widget.loadProfile();
    setState(() => _profile = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _openSupport() async {
    try {
      if (await launchUrl(_support, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('باز کردن پشتیبانی انجام نشد.')),
      );
    }
  }

  String _digits(Object value) => '$value'.replaceAllMapped(
    RegExp(r'\d'),
    (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match.group(0)!)],
  );

  Widget _info(String title, String value, IconData icon) => ListTile(
    leading: Icon(icon, color: MovieColors.cyan),
    title: Text(title, style: const TextStyle(color: MovieColors.muted)),
    subtitle: Text(value, style: const TextStyle(fontSize: 16)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مدیریت اشتراک'),
      actions: [
        IconButton(
          tooltip: 'تازه‌سازی',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _profile,
        builder: (context, snapshot) {
          final user = (snapshot.data?['user'] as Map?)
              ?.cast<String, dynamic>();
          final loading = snapshot.connectionState != ConnectionState.done;
          final active = user?['is_active'] == true;
          final admin = user?['role'] == 'admin';
          final seconds = (user?['subscription_expires_at'] as num?)?.toInt();
          final expiry = seconds == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          final remaining = expiry?.difference(DateTime.now());
          final valid =
              active && (admin || (remaining != null && !remaining.isNegative));
          final status = !active
              ? 'حساب غیرفعال'
              : admin
              ? 'دسترسی مدیر'
              : valid
              ? 'اشتراک فعال'
              : 'اشتراک پایان یافته';
          final remainingLabel = admin
              ? 'بدون محدودیت زمانی'
              : remaining == null || remaining.isNegative
              ? 'زمانی باقی نمانده است'
              : remaining.inDays > 0
              ? '${_digits(remaining.inDays)} روز و ${_digits(remaining.inHours % 24)} ساعت'
              : remaining.inHours > 0
              ? '${_digits(remaining.inHours)} ساعت و ${_digits(remaining.inMinutes % 60)} دقیقه'
              : '${_digits(remaining.inMinutes.clamp(0, 59))} دقیقه';

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (user == null) ...[
                const SizedBox(height: 50),
                const Center(child: Text('اطلاعات اشتراک دریافت نشد.')),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تلاش دوباره'),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: valid
                          ? [
                              MovieColors.orange.withValues(alpha: .38),
                              MovieColors.surfaceHigh,
                            ]
                          : [
                              Colors.red.withValues(alpha: .22),
                              MovieColors.surfaceHigh,
                            ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: valid ? MovieColors.orange : Colors.redAccent,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        valid ? Icons.verified_rounded : Icons.schedule_rounded,
                        color: valid ? MovieColors.cyan : Colors.redAccent,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        remainingLabel,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Column(
                    children: [
                      _info(
                        'نام',
                        (user['name']?.toString().isNotEmpty ?? false)
                            ? user['name'].toString()
                            : 'ثبت نشده',
                        Icons.person_outline_rounded,
                      ),
                      _info(
                        'ایمیل',
                        user['email']?.toString() ?? 'ثبت نشده',
                        Icons.alternate_email_rounded,
                      ),
                      _info(
                        'شماره تماس',
                        (user['mobile']?.toString().isNotEmpty ?? false)
                            ? user['mobile'].toString()
                            : 'ثبت نشده',
                        Icons.phone_outlined,
                      ),
                      _info(
                        'پایان اشتراک',
                        admin
                            ? 'بدون محدودیت'
                            : expiry == null
                            ? 'ثبت نشده'
                            : MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(expiry),
                        Icons.event_rounded,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openSupport,
                icon: const Icon(Icons.support_agent_rounded),
                label: const Text('ارتباط با پشتیبانی و تمدید اشتراک'),
              ),
              const SizedBox(height: 8),
              const Text(
                'پشتیبانی تلگرام: @mbnproo',
                textAlign: TextAlign.center,
                style: TextStyle(color: MovieColors.muted),
              ),
            ],
          );
        },
      ),
    ),
  );
}
