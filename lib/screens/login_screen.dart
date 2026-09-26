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
    required this.onLogin,
    this.onRegister,
    this.allowRegister = false,
  });

  final Future<void> Function(String identifier, String password) onLogin;

  /// Kept for a future public signup; the UI stays hidden while
  /// [allowRegister] is false.
  final Future<void> Function(
    String name,
    String email,
    String mobile,
    String password,
  )?
  onRegister;
  final bool allowRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _telegramUrl = 'https://t.me/mbnproo';

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _registering = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _mobile.dispose();
    _confirmPassword.dispose();
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
      if (_registering && widget.onRegister != null) {
        await widget.onRegister!(
          _name.text,
          _email.text,
          _mobile.text,
          _password.text,
        );
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
    final registering = _registering && widget.allowRegister;
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
                          registering ? 'ساخت حساب' : 'خوش برگشتی',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'برای ورود به آرشیو کامل فیلم‌ها و سریال‌ها، وارد حساب خودت شو. رمز ۱۰ دقیقه‌ای موقت هم قبول است.',
                          style: TextStyle(
                            color: MovieColors.muted,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (registering) ...[
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'نام کاربری',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? 'نام کاربری را وارد کن'
                                : null,
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: registering
                                ? 'ایمیل'
                                : 'ایمیل یا نام کاربری',
                            hintText: registering
                                ? 'name@example.com'
                                : 'ایمیل یا نام کاربری',
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
                            if (!validEmail &&
                                (registering || !validUsername)) {
                              return registering
                                  ? 'ایمیل معتبر وارد کن'
                                  : 'ایمیل یا نام کاربری معتبر وارد کن';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        if (registering) ...[
                          TextFormField(
                            controller: _mobile,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'شماره همراه (اختیاری)',
                              prefixIcon: Icon(Icons.phone_android_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
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
                          validator: (value) => (value?.length ?? 0) < 4
                              ? 'رمز عبور باید حداقل ۴ نویسه باشد'
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
                                        registering
                                            ? 'ثبت‌نام و ورود'
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
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _openTelegram,
                          icon: const Icon(Icons.send_rounded),
                          label: const Text(
                            'برای دریافت اطلاعات ورود از تلگرام کمک بگیر',
                          ),
                        ),
                        if (widget.allowRegister) ...[
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
