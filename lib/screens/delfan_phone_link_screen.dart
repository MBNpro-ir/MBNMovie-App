import 'package:flutter/material.dart';

import '../services/mbn_auth.dart';

/// Finishes the SMS activation for an account created by an administrator.
class DelfanPhoneLinkScreen extends StatefulWidget {
  const DelfanPhoneLinkScreen({super.key, required this.auth});
  final MbnAuth auth;

  @override
  State<DelfanPhoneLinkScreen> createState() => _DelfanPhoneLinkScreenState();
}

class _DelfanPhoneLinkScreenState extends State<DelfanPhoneLinkScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _challengeId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action,
      void Function(Map<String, dynamic>) onSuccess) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final data = await action();
      if (mounted) onSuccess(data);
    } on MbnAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'ارتباط برقرار نشد؛ دوباره تلاش کن.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _start() {
    if (!RegExp(r'^09\d{9}$').hasMatch(_phone.text.trim())) {
      setState(() => _error = 'شماره را به شکل 09123456789 وارد کن.');
      return;
    }
    _run(
      () => widget.auth.postJson('/api/me/delfan/signup', {
        'mobile': _phone.text.trim(),
        if (widget.auth.profile?.name.isEmpty ?? true)
          'name': _name.text.trim(),
        if (widget.auth.profile?.hasDelfanPassword != true)
          'password': _password.text,
      }),
      (data) => setState(() => _challengeId = data['challenge_id']?.toString()),
    );
  }

  void _verify() {
    if (!RegExp(r'^\d{4,8}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'کد ۴ تا ۸ رقمی را وارد کن.');
      return;
    }
    _run(
      () => widget.auth.postJson('/api/auth/delfan/verify', {
        'challenge_id': _challengeId,
        'code': _code.text.trim(),
      }),
      (_) => Navigator.pop(context, true),
    );
  }

  void _resend() => _run(
    () => widget.auth.postJson('/api/auth/delfan/resend', {
      'challenge_id': _challengeId,
    }),
    (_) => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کد دوباره ارسال شد.')),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تأیید شماره موبایل')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.phonelink_lock_rounded,
                  size: 62, color: Colors.redAccent),
              const SizedBox(height: 18),
              Text(_challengeId == null ? 'تکمیل حساب مهمان' : 'کد تأیید',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(_challengeId == null
                  ? 'این حساب بدون شمارهٔ تأییدشده ساخته شده است. '
                    'تا زمان تأیید شماره، برخی امکانات حساب در دسترس نیستند. '
                    'نام نمایشی و رمز ثبت شده در پنل استفاده می‌شود؛ فقط شماره را وارد کن.'
                  : 'کد پیامک شده به ${_phone.text} را وارد کن.'),
              const SizedBox(height: 20),
              if (_challengeId == null)
                Column(children: [
                  if (widget.auth.profile?.name.isEmpty ?? true)
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'نام نمایشی'),
                    ),
                  if (widget.auth.profile?.hasDelfanPassword != true)
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'رمز اتصال'),
                    ),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'شماره موبایل',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                    ),
                  ),
                ])
              else
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'کد پیامک',
                    prefixIcon: Icon(Icons.sms_outlined),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _challengeId == null ? _start : _verify,
                child: _busy ? const CircularProgressIndicator()
                    : Text(_challengeId == null ? 'ارسال کد' : 'تأیید شماره'),
              ),
              if (_challengeId != null)
                TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('ارسال دوبارهٔ کد'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
