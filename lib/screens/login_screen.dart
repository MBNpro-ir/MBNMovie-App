import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../services/mbn_auth.dart';
import '../widgets/ambient_background.dart';
import '../widgets/brand_mark.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onLogin,
    required this.onAuthenticated,
    this.onUseOtherApp,
  });

  final MbnAuth auth;
  final Future<void> Function(String identifier, String password) onLogin;
  final Future<void> Function(Map<String, dynamic> data, String identifier)
  onAuthenticated;
  final Future<void> Function()? onUseOtherApp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _telegramUrl = 'https://t.me/mbnproo';

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _registrationEmail = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _registering = false;
  bool _recovering = false;
  String? _challengeId;
  int _recoverStep = 1;

  @override
  void dispose() {
    _email.dispose();
    _registrationEmail.dispose();
    _username.dispose();
    _password.dispose();
    _name.dispose();
    _mobile.dispose();
    _confirmPassword.dispose();
    _code.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Single-flight guard shared by button + keyboard (Enter) submissions:
    // without it, repeated Enter presses while a request is pending fire
    // parallel authentication callbacks.
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_challengeId != null) {
        final data = await widget.auth.postJson('/api/auth/delfan/verify', {
          'challenge_id': _challengeId,
          'code': _code.text.trim(),
        });
        if (data['token'] != null) {
          await widget.onAuthenticated(data, _mobile.text.trim());
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message']?.toString() ?? 'شماره تأیید شد.'),
          ));
          setState(() {
            _challengeId = null;
            _registering = false;
          });
        }
      } else if (_recovering) {
        await widget.auth.postJson('/api/auth/delfan/recover', {
          'mobile': _mobile.text.trim(),
          'step': _recoverStep,
          'code': _code.text.trim(),
          'new_password': _newPassword.text,
        });
        if (mounted) {
          if (_recoverStep == 3) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('رمز تغییر کرد؛ با شماره و رمز جدید وارد شو.'),
            ));
            setState(() { _recovering = false; _recoverStep = 1; });
          } else {
            setState(() => _recoverStep++);
          }
        }
      } else if (_registering) {
        final mobile = _mobile.text.trim();
        final data = await widget.auth.postJson(
            mobile.isEmpty ? '/api/auth/register' : '/api/auth/delfan/signup', {
          'name': _name.text.trim(),
          'email': _registrationEmail.text.trim(),
          'username': _username.text.trim(),
          'mobile': mobile,
          'password': _password.text,
          'app': 'movie',
        });
        if (data['token'] != null) {
          await widget.onAuthenticated(data,
              _registrationEmail.text.trim().isNotEmpty
                  ? _registrationEmail.text.trim()
                  : _username.text.trim());
        } else if (mounted) {
          setState(() => _challengeId = data['challenge_id']?.toString());
        }
      } else {
        await widget.onLogin(_email.text, _password.text);
      }
    } on MbnAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ورود انجام نشد؛ دوباره تلاش کن.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_loading || _challengeId == null) return;
    setState(() => _loading = true);
    try {
      await widget.auth.postJson('/api/auth/delfan/resend', {
        'challenge_id': _challengeId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کد دوباره ارسال شد.')),
        );
      }
    } on MbnAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useOtherApp() async {
    if (_loading || widget.onUseOtherApp == null) return;
    setState(() => _loading = true);
    try {
      await widget.onUseOtherApp!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ورود مشترک آغاز نشد؛ دوباره تلاش کن.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTelegram() async {
    HapticFeedback.lightImpact();
    try {
      await launchUrl(
        Uri.parse(_telegramUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تلگرام باز نشد.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final registering = _registering && _challengeId == null;
    final verifying = _challengeId != null;
    final recovering = _recovering;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 24, end: 0),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.translate(
                    offset: Offset(0, value),
                    child: child,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerRight,
                          child: BrandMark(size: 62),
                        ),
                        const SizedBox(height: 44),
                        Text(
                          verifying ? 'تأیید شماره' : recovering
                              ? 'بازیابی رمز' : registering
                              ? 'ساخت حساب' : 'خوش برگشتی',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          verifying
                              ? 'کد ارسال شده به ${_mobile.text} را وارد کن.'
                              : registering
                              ? 'نام نمایشی، شماره موبایل و رمز را وارد کن. حساب پس از تأیید پیامکی ساخته می‌شود.'
                              : recovering
                              ? 'برای بازیابی رمز شمارهٔ تأییدشده، کد پیامک را وارد کن.'
                              : 'با ایمیل، نام کاربری یا شمارهٔ تأییدشده و رمز وارد شو.',
                          style: TextStyle(
                            color: MovieColors.muted,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!registering && !verifying && !recovering &&
                            widget.onUseOtherApp != null) ...[
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _useOtherApp,
                            icon: const Icon(Icons.account_circle_outlined),
                            label: const Text('ورود با حساب MBNime'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'می‌توانی از حساب برنامهٔ دیگر استفاده کنی یا پایین با اطلاعات متفاوت وارد شوی.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (registering) ...[
                          TextFormField(
                            controller: _name,
                            decoration: InputDecoration(
                              labelText: 'نام نمایشی',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 1
                                ? 'نام کاربری را وارد کن'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _username,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'نام کاربری (اختیاری با شماره)',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) {
                                return _registrationEmail.text.trim().isEmpty &&
                                        _mobile.text.trim().isEmpty
                                    ? 'ایمیل، نام کاربری یا شماره لازم است' : null;
                              }
                              return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,31}$')
                                      .hasMatch(text)
                                  ? null : '۳ تا ۳۲ نویسهٔ انگلیسی؛ شروع با حرف';
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _registrationEmail,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'ایمیل (اختیاری)',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              return text.isEmpty || RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(text) ? null : 'ایمیل معتبر وارد کن';
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (!registering && !verifying && !recovering)
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: 'ایمیل، نام کاربری یا موبایل',
                            hintText: 'ایمیل، نام کاربری یا 09123456789',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            final validEmail = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(text);
                            final validUsername = RegExp(
                              r'^[a-zA-Z][a-zA-Z0-9_]{2,31}$',
                            ).hasMatch(text);
                            final validMobile = RegExp(r'^09\d{9}$')
                                .hasMatch(text);
                            if (!validEmail && !validUsername && !validMobile) {
                              return 'ایمیل، نام کاربری یا شماره معتبر وارد کن';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        if (registering || (recovering && _recoverStep == 1)) ...[
                          TextFormField(
                            controller: _mobile,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: registering
                                  ? 'شماره موبایل (اختیاری؛ برای تأیید پیامکی)'
                                  : 'شماره موبایل',
                              prefixIcon: const Icon(Icons.phone_android_rounded),
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty && registering) return null;
                              return RegExp(r'^09\d{9}$').hasMatch(text)
                                  ? null : 'شماره را به شکل 09123456789 وارد کن';
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (verifying || (recovering && _recoverStep >= 2)) ...[
                          TextFormField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'کد پیامک',
                              prefixIcon: Icon(Icons.sms_outlined),
                            ),
                            validator: (value) => RegExp(r'^\d{4,8}$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null : 'کد ۴ تا ۸ رقمی را وارد کن',
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (recovering && _recoverStep == 3) ...[
                          TextFormField(
                            controller: _newPassword,
                            obscureText: _obscure,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'رمز جدید',
                              prefixIcon: Icon(Icons.lock_reset_rounded),
                            ),
                            validator: (value) => (value?.length ?? 0) < 6
                                ? 'حداقل ۶ نویسه وارد کن' : null,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (!verifying && !recovering)
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'رمز عبور',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  _obscure
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  key: ValueKey(_obscure),
                                ),
                              ),
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) <
                                  (registering ? 6 : 1)
                              ? 'رمز عبور را کامل وارد کن'
                              : null,
                        ),
                        if (registering) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPassword,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'تکرار رمز عبور',
                              prefixIcon: Icon(Icons.lock_reset_rounded),
                            ),
                            validator: (value) => value != _password.text
                                ? 'تکرار رمز عبور یکسان نیست'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _loading
                                ? const SizedBox(
                                    key: ValueKey('loading'),
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : Row(
                                    key: ValueKey('label'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        verifying ? 'تأیید کد' : recovering
                                            ? 'ادامه بازیابی' : registering
                                            ? 'ساخت حساب / ارسال کد'
                                            : 'ورود به MBNMovie',
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        registering
                                            ? Icons.person_add_alt_1_rounded
                                            : Icons.arrow_back_rounded,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        if (verifying)
                          TextButton(
                            onPressed: _loading ? null : _resend,
                            child: const Text('ارسال دوباره کد'),
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _openTelegram,
                          icon: const Icon(Icons.send_rounded),
                          label: const Text(
                            'پشتیبانی تلگرام',
                          ),
                        ),
                        if (!recovering && !verifying) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                    _registering = !_registering;
                                    _formKey.currentState?.reset();
                                  }),
                            child: Text(
                              registering
                                  ? 'حساب دارم؛ ورود'
                                  : 'حساب ندارم؛ ثبت‌نام',
                            ),
                          ),
                        ],
                        if (!registering && !verifying && !recovering)
                          TextButton(
                            onPressed: _loading ? null : () => setState(() {
                              _recovering = true;
                              _recoverStep = 1;
                            }),
                            child: const Text('رمز حساب شماره‌دار را فراموش کرده‌ام'),
                          ),
                        if (recovering || verifying)
                          TextButton(
                            onPressed: _loading ? null : () => setState(() {
                              _recovering = false;
                              _recoverStep = 1;
                              _challengeId = null;
                              _registering = false;
                            }),
                            child: const Text('بازگشت به ورود'),
                          ),
                        const SizedBox(height: 18),
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: MovieColors.cyan,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ورود یعنی اشتراک فعال؛ علاقه‌مندی‌ها و پلی‌لیست‌هایت در همه دستگاه‌ها همراهت است.',
                                style: TextStyle(
                                  color: MovieColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
