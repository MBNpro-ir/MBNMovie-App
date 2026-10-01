import 'package:flutter/material.dart';

typedef SessionPost = Future<Map<String, dynamic>> Function(String, Map<String, dynamic>);

Future<Map<String, dynamic>?> showSessionDevicesDialog(BuildContext context,
    Map<String, dynamic> challenge, SessionPost post) => showDialog<Map<String, dynamic>>(
      context: context, barrierDismissible: false,
      builder: (_) => _SessionDevicesDialog(challenge: challenge, post: post));

class _SessionDevicesDialog extends StatefulWidget {
  const _SessionDevicesDialog({required this.challenge, required this.post});
  final Map<String, dynamic> challenge;
  final SessionPost post;
  @override
  State<_SessionDevicesDialog> createState() => _SessionDevicesDialogState();
}
class _SessionDevicesDialogState extends State<_SessionDevicesDialog> {
  late List<dynamic> _sessions = List.from(widget.challenge['sessions'] as List? ?? []);
  late int _limit = (widget.challenge['session_limit'] as num?)?.toInt() ?? 5;
  late final String _ticket = widget.challenge['management_token'].toString();
  bool _busy = false;
  String? _error;
  Future<void> _act(String action, [String? id]) async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.post('/api/auth/sessions/manage', {
        'management_token': _ticket, 'action': action, 'session_id': ?id,
      });
      if (!mounted) return;
      if (result['token'] != null) { Navigator.pop(context, result); return; }
      setState(() { _sessions = result['sessions'] as List; _limit = (result['session_limit'] as num).toInt(); });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ظرفیت دستگاه‌ها تکمیل شده'),
    content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('حداکثر $_limit نشست هم‌زمان برای این حساب فعال است. برای ورود یک دستگاه را خارج کن.'),
      const SizedBox(height: 12),
      Flexible(child: SingleChildScrollView(child: Column(children: [for (final session in _sessions)
        ListTile(leading: const Icon(Icons.devices),
          title: Text(session['device_info']?.toString() ?? 'دستگاه'),
          subtitle: Text('${session['app'] == 'anime' ? 'MBNime' : 'MBNMovie'} · ${session['ip_address']}\nآخرین فعالیت: ${DateTime.fromMillisecondsSinceEpoch(((session['last_active_at'] as num?)?.toInt() ?? 0) * 1000).toLocal()}'),
          isThreeLine: true,
          trailing: IconButton(tooltip: 'خروج این دستگاه', icon: const Icon(Icons.logout),
            onPressed: _busy ? null : () => _act('revoke', session['id'].toString()))),
      ]))),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_busy) const LinearProgressIndicator(),
    ])),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('انصراف')),
      TextButton(onPressed: _busy || _sessions.isEmpty ? null : () => _act('revoke_all'), child: const Text('خروج همه دستگاه‌ها')),
      FilledButton(onPressed: _busy || _sessions.length >= _limit ? null : () => _act('continue'), child: const Text('ادامه ورود')),
    ],
  );
}
