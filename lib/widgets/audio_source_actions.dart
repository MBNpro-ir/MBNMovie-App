import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

Uri? externalAudioUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
          {'https', 'http'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class AudioSourceActions extends StatefulWidget {
  const AudioSourceActions({
    super.key,
    required this.onSelected,
    this.pickFile,
  });
  final Future<void> Function(AudioTrack) onSelected;
  final Future<XFile?> Function()? pickFile;
  @override
  State<AudioSourceActions> createState() => _AudioSourceActionsState();
}

class _AudioSourceActionsState extends State<AudioSourceActions> {
  bool _busy = false;
  bool _loading = false;
  String? _error;

  Future<void> _load(bool fromFile) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      AudioTrack? track;
      if (fromFile) {
        final file =
            await (widget.pickFile?.call() ??
                openFile(
                  acceptedTypeGroups: const [
                    XTypeGroup(
                      label: 'صدا',
                      extensions: [
                        'mp3',
                        'm4a',
                        'aac',
                        'ac3',
                        'eac3',
                        'dts',
                        'flac',
                        'wav',
                        'ogg',
                        'opus',
                        'mka',
                        'wma',
                        'aiff',
                      ],
                      mimeTypes: ['audio/*'],
                    ),
                  ],
                ));
        if (file != null) {
          track = AudioTrack.uri(
            file.path,
            title: file.name.replaceAll('\\', '/').split('/').last,
          );
        }
      } else {
        final url = await showDialog<String>(
          context: context,
          builder: (_) => const _AudioUrlDialog(),
        );
        if (url != null) track = AudioTrack.uri(url, title: 'صدای اینترنتی');
      }
      if (track != null && mounted) {
        setState(() => _loading = true);
        await widget.onSelected(track);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'صدا اضافه نشد؛ فایل یا لینک مستقیم صدا و اتصال اینترنت را بررسی کن.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) Text(_error!, textAlign: TextAlign.center),
        if (_loading) const LinearProgressIndicator(),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _load(true),
              icon: const Icon(Icons.audio_file_rounded),
              label: const Text('فایل صدا'),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _load(false),
              icon: const Icon(Icons.link_rounded),
              label: const Text('لینک صدا'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'صدا برای همین ویدئو اضافه می‌شود؛ فایل یا لینک مستقیم صوت را انتخاب کن.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}

class _AudioUrlDialog extends StatefulWidget {
  const _AudioUrlDialog();
  @override
  State<_AudioUrlDialog> createState() => _AudioUrlDialogState();
}

class _AudioUrlDialogState extends State<_AudioUrlDialog> {
  final _controller = TextEditingController();
  String? _error;
  void _submit() {
    final uri = externalAudioUrl(_controller.text);
    if (uri == null) {
      setState(() => _error = 'یک لینک مستقیم معتبر با http یا https وارد کن.');
    } else {
      Navigator.pop(context, uri.toString());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('افزودن لینک صدا'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textDirection: TextDirection.ltr,
      keyboardType: TextInputType.url,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: 'https://example.com/audio.m4a',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('بازگشت'),
      ),
      FilledButton(onPressed: _submit, child: const Text('افزودن')),
    ],
  );
}
