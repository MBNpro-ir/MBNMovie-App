import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';

class JalaliDate {
  final int year;
  final int month;
  final int day;
  const JalaliDate(this.year, this.month, this.day);

  static const _monthNames = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
  ];

  String get monthName => (month >= 1 && month <= 12) ? _monthNames[month - 1] : '';

  String formatFull() => '$day $monthName $year';

  static JalaliDate fromDateTime(DateTime date) {
    int gy = date.year - 1600;
    int gm = date.month - 1;
    int gd = date.day - 1;

    var gDaysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var jDaysInMonth = [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29];

    int gDayNo = 365 * gy + ((gy + 3) ~/ 4) - ((gy + 99) ~/ 100) + ((gy + 399) ~/ 400);

    for (int i = 0; i < gm; ++i) {
      gDayNo += gDaysInMonth[i];
    }
    if (gm > 1 && ((gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0))) {
      gDayNo++;
    }
    gDayNo += gd;

    int jDayNo = gDayNo - 79;
    int jNp = jDayNo ~/ 12053;
    jDayNo %= 12053;

    int jy = 979 + 33 * jNp + 4 * (jDayNo ~/ 1461);
    jDayNo %= 1461;

    if (jDayNo >= 366) {
      jy += (jDayNo - 1) ~/ 365;
      jDayNo = (jDayNo - 1) % 365;
    }

    int jm = 0;
    for (int i = 0; i < 11 && jDayNo >= jDaysInMonth[i]; ++i) {
      jDayNo -= jDaysInMonth[i];
      jm++;
    }
    int jd = jDayNo + 1;
    return JalaliDate(jy, jm + 1, jd);
  }
}

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
        const SnackBar(content: Text('باز کردن تلگرام پشتیبانی انجام نشد.')),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label کپی شد: $text'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _digits(Object value) => '$value'.replaceAllMapped(
    RegExp(r'\d'),
    (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match.group(0)!)],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت اشتراک'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'تازه‌سازی اطلاعات',
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
            final user = (snapshot.data?['user'] as Map?)?.cast<String, dynamic>();
            final loading = snapshot.connectionState != ConnectionState.done;

            if (loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (user == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 64, color: MovieColors.muted),
                      const SizedBox(height: 16),
                      const Text(
                        'اطلاعات اشتراک از سرور دریافت نشد.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'لطفاً اتصال اینترنت خود را بررسی کرده و مجدداً تلاش کنید.',
                        style: TextStyle(color: MovieColors.muted),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final active = user['is_active'] == true;
            final admin = user['role'] == 'admin';
            final seconds = (user['subscription_expires_at'] as num?)?.toInt();
            final expiry = seconds == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
            final remaining = expiry?.difference(DateTime.now());
            final valid = active && (admin || (remaining != null && !remaining.isNegative));

            final statusTitle = !active
                ? 'حساب غیرفعال شده'
                : admin
                    ? 'دسترسی نامحدود مدیر'
                    : valid
                        ? 'اشتراک ویژه طلایی'
                        : 'اشتراک پایان یافته';

            final remainingLabel = admin
                ? 'دسترسی همیشگی بدون محدودیت زمانی'
                : remaining == null || remaining.isNegative
                    ? 'مهلت استفاده از اشتراک به پایان رسیده است'
                    : remaining.inDays > 0
                        ? '${_digits(remaining.inDays)} روز و ${_digits(remaining.inHours % 24)} ساعت باقی‌مانده'
                        : remaining.inHours > 0
                            ? '${_digits(remaining.inHours)} ساعت و ${_digits(remaining.inMinutes % 60)} دقیقه باقی‌مانده'
                            : '${_digits(remaining.inMinutes.clamp(0, 59))} دقیقه باقی‌مانده';

            final jalaliExpiry = expiry != null ? JalaliDate.fromDateTime(expiry) : null;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  children: [
                    // Hero Subscription Card
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: valid
                              ? [
                                  const Color(0xFF1E2846),
                                  const Color(0xFF111728),
                                  MovieColors.surfaceHigh,
                                ]
                              : [
                                  const Color(0xFF38151D),
                                  const Color(0xFF1D1016),
                                  MovieColors.surfaceHigh,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: valid
                              ? MovieColors.cyan.withValues(alpha: .35)
                              : Colors.redAccent.withValues(alpha: .35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (valid ? MovieColors.cyan : Colors.redAccent)
                                .withValues(alpha: .12),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (valid ? MovieColors.cyan : Colors.redAccent)
                                      .withValues(alpha: .16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  admin
                                      ? Icons.verified_user_rounded
                                      : valid
                                          ? Icons.workspace_premium_rounded
                                          : Icons.schedule_rounded,
                                  color: valid ? MovieColors.cyan : Colors.redAccent,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      statusTitle,
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      remainingLabel,
                                      style: TextStyle(
                                        color: valid ? Colors.white70 : Colors.redAccent.shade100,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (valid ? MovieColors.cyan : Colors.redAccent)
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: (valid ? MovieColors.cyan : Colors.redAccent)
                                        .withValues(alpha: .3),
                                  ),
                                ),
                                child: Text(
                                  admin ? 'مدیر سیستم' : valid ? 'VIP فعال' : 'منقضی شده',
                                  style: TextStyle(
                                    color: valid ? MovieColors.cyan : Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.event_available_rounded, size: 18, color: Colors.white60),
                                  const SizedBox(width: 8),
                                  Text(
                                    admin
                                        ? 'اعتبار اشتراک: نامحدود'
                                        : jalaliExpiry != null
                                            ? 'تاریخ انقضا: ${_digits(jalaliExpiry.formatFull())}'
                                            : 'تاریخ انقضا: مشخص نیست',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                              if (!admin && valid)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .06),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.bolt_rounded, size: 16, color: MovieColors.orange),
                                      const SizedBox(width: 4),
                                      Text(
                                        'حداکثر سرعت',
                                        style: TextStyle(color: MovieColors.orange, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Subscription Benefits Section
                    Text(
                      'امکانات و مزایای اشتراک شما',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        final features = [
                          (Icons.hd_rounded, 'کیفیت بالا 4K و Full HD', 'پخش بلادرنگ با بالاترین نرخ فریم و بیت‌ریت اختصاصی'),
                          (Icons.offline_bolt_rounded, 'دانلود پرسرعت نیم‌بها', 'سرعت حداکثری دانلود روی تمام اپراتورهای اینترنت'),
                          (Icons.block_rounded, 'کاملاً بدون تبلیغات', 'تماشای پیوسته و بدون وقفه تمامی فیلم‌ها و سریال‌ها'),
                          (Icons.cloud_sync_rounded, 'همگام‌سازی ابری جامع', 'سینک خودکار وضعیت تماشا، لیست‌ها و تنظیمات پلیر'),
                        ];

                        if (isWide) {
                          return GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 3.4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            children: features.map((f) => _featureTile(f.$1, f.$2, f.$3)).toList(),
                          );
                        } else {
                          return Column(
                            children: features.map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _featureTile(f.$1, f.$2, f.$3),
                            )).toList(),
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 24),

                    // User Profile Details Card
                    Text(
                      'مشخصات حساب کاربری',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: MovieColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          _userTile(
                            icon: Icons.person_rounded,
                            title: 'نام کاربر',
                            value: (user['name']?.toString().isNotEmpty ?? false)
                                ? user['name'].toString()
                                : 'ثبت نشده',
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          _userTile(
                            icon: Icons.alternate_email_rounded,
                            title: 'ایمیل',
                            value: user['email']?.toString() ?? 'ثبت نشده',
                            canCopy: user['email']?.toString().isNotEmpty ?? false,
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          _userTile(
                            icon: Icons.badge_rounded,
                            title: 'نام کاربری',
                            value: user['username']?.toString() ?? 'ثبت نشده',
                            canCopy: user['username']?.toString().isNotEmpty ?? false,
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          _userTile(
                            icon: Icons.phone_android_rounded,
                            title: 'شماره تماس',
                            value: (user['mobile']?.toString().isNotEmpty ?? false)
                                ? _digits(user['mobile'].toString())
                                : 'ثبت نشده',
                            canCopy: user['mobile']?.toString().isNotEmpty ?? false,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Support & Renewal CTA
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: MovieColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: MovieColors.cyan.withValues(alpha: .2)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: MovieColors.cyan,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _openSupport,
                              icon: const Icon(Icons.support_agent_rounded, size: 24),
                              label: const Text(
                                'ارتباط با پشتیبانی و تمدید اشتراک',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: () => _copyToClipboard('@mbnproo', 'شناسه تلگرام'),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.send_rounded, size: 16, color: MovieColors.cyan),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'پشتیبانی تلگرام: @mbnproo',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.copy_rounded, size: 14, color: MovieColors.cyan.withValues(alpha: .7)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _featureTile(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MovieColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MovieColors.cyan.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: MovieColors.cyan, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: MovieColors.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userTile({
    required IconData icon,
    required String title,
    required String value,
    bool canCopy = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: MovieColors.cyan, size: 22),
          const SizedBox(width: 14),
          Text(title, style: const TextStyle(color: MovieColors.muted, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (canCopy) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16, color: MovieColors.muted),
              tooltip: 'کپی $title',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyToClipboard(value, title),
            ),
          ],
        ],
      ),
    );
  }
}
