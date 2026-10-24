import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client.dart';
import 'watch_controller.dart';

const _mint = Color(0xFF83E9C5),
    _violet = Color(0xFFA79BFF),
    _ink = Color(0xFF0D1422),
    _panel = Color(0xFF172235);
bool _yes(Object? value) => value == true || value == 1;
List<PartyJson> _rows(Object? value) => value is List
    ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];
String _name(PartyJson user) =>
    user['name']?.toString().trim().isNotEmpty == true
    ? user['name'].toString()
    : user['username']?.toString().isNotEmpty == true
    ? user['username'].toString()
    : 'دوست';
String _roomName(PartyJson room, int uid) {
  if (room['kind'] == 'group') return room['title']?.toString() ?? 'گروه';
  for (final m in _rows(room['members'])) {
    if (partyInt(m['user_id']) != uid) {
      return _name(Map<String, dynamic>.from(m['user'] as Map));
    }
  }
  return 'گفت‌وگوی خصوصی';
}

void _notice(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

Future<bool> _confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأیید'),
          ),
        ],
      ),
    ) ??
    false;

class PartyButton extends StatefulWidget {
  const PartyButton({super.key, this.onPressed, this.compact = true});
  final VoidCallback? onPressed;
  final bool compact;
  @override
  State<PartyButton> createState() => _PartyButtonState();
}

class _PartyButtonState extends State<PartyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    PartyHub.instance.addListener(_update);
    _update();
  }

  void _update() {
    final hub = PartyHub.instance;
    if (hub.client?.hasActiveParty == true && !hub.reduceMotion) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    PartyHub.instance.removeListener(_update);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: Listenable.merge([PartyHub.instance, _pulse]),
      builder: (context, _) {
        final client = PartyHub.instance.client,
            active = client?.hasActiveParty == true;
        return Tooltip(
          message: active
              ? 'پارتی در جریان است؛ پیوستن دوباره'
              : 'پارتی · دوستان و تماشای گروهی',
          child: Semantics(
            label: 'پارتی',
            button: true,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: active
                    ? LinearGradient(
                        colors: [
                          Color.lerp(
                            _mint,
                            _violet,
                            _pulse.value,
                          )!.withValues(alpha: .3),
                          _violet.withValues(alpha: .2),
                        ],
                      )
                    : null,
                border: active
                    ? Border.all(
                        color: _mint.withValues(alpha: .35 + .3 * _pulse.value),
                      )
                    : null,
              ),
              child: Badge(
                isLabelVisible: (client?.unread ?? 0) > 0,
                label: Text('${(client?.unread ?? 0).clamp(0, 99)}'),
                child: IconButton(
                  key: const Key('party-open'),
                  tooltip: 'پارتی',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onPressed ?? () => openParty(context),
                  icon: Icon(
                    Icons.diversity_2_rounded,
                    color: active ? _mint : null,
                    size: widget.compact ? 23 : 27,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> openParty(BuildContext context, {String? roomId}) async {
  final client = PartyHub.instance.client;
  if (client == null) {
    _notice(context, 'برای استفاده از پارتی به حساب و سرور متصل شو.');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PartyScreen(client: client, initialRoomId: roomId),
    ),
  );
}

class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key, required this.client, this.initialRoomId});
  final PartyClient client;
  final String? initialRoomId;
  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  final _draft = TextEditingController(), _scroll = ScrollController();
  late final VoidCallback _release;
  PartyJson? _room, _reply;
  List<PartyJson> _messages = [];
  bool _loading = false, _sending = false, _more = false;
  String? _failure, _lastAttempt, _attemptNonce;
  int _tab = 0, _generation = 0, _event = 0;
  PartyClient get client => widget.client;

  @override
  void initState() {
    super.initState();
    _release = client.watch();
    client.addListener(_changed);
    if (widget.initialRoomId != null) unawaited(_select(widget.initialRoomId!));
  }

  @override
  void dispose() {
    client.removeListener(_changed);
    _release();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final current = _room;
    for (final event in client.events) {
      final id = partyInt(event['id']);
      if (id <= _event) continue;
      _event = id;
      if (event['kind'] == 'message' && current != null) {
        unawaited(_refreshMessage(partyInt(event['entity_id'])));
      }
      if (['room_removed', 'room_deleted'].contains(event['kind']) &&
          event['entity_id'] == current?['id']) {
        _generation++;
        _room = null;
        _messages = [];
        _notice(context, 'این گفت‌وگو دیگر در دسترس نیست.');
      }
    }
    if (current != null) {
      final updated = client.rooms
          .where((r) => r['id'] == current['id'])
          .firstOrNull;
      if (updated != null) _room = {...current, ...updated};
    }
    setState(() {});
  }

  Future<void> _refreshMessage(int id) async {
    final generation = _generation;
    try {
      final message = await client.message(id);
      if (!mounted ||
          generation != _generation ||
          message['room_id'] != _room?['id']) {
        return;
      }
      setState(() {
        _messages = [..._messages.where((m) => m['id'] != id), message]
          ..sort((a, b) => partyInt(a['id']).compareTo(partyInt(b['id'])));
        if (_messages.length > 300) {
          _messages = _messages.sublist(_messages.length - 300);
          _more = true;
        }
      });
      unawaited(
        client.read(_room!['id'].toString(), id).catchError((Object _) {}),
      );
    } catch (_) {}
  }

  Future<void> _select(String id) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
      _reply = null;
      _draft.clear();
    });
    try {
      final room = await client.room(id), page = await client.messages(id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _room = room;
        _messages = _rows(page['messages']);
        _more = page['has_more'] == true;
        _loading = false;
      });
      if (_messages.isNotEmpty) {
        unawaited(
          client
              .read(id, partyInt(_messages.last['id']))
              .catchError((Object _) {}),
        );
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failure = '$e';
        });
      }
    }
  }

  Future<void> _older() async {
    if (_loading || _room == null || _messages.isEmpty) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await client.messages(
        _room!['id'].toString(),
        before: partyInt(_messages.first['id']),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages = [..._rows(page['messages']), ..._messages];
        _more = page['has_more'] == true;
      });
    } catch (e) {
      if (mounted) _notice(context, e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _send() async {
    final text = _draft.text.trim(), room = _room;
    final generation = _generation;
    if (text.isEmpty || room == null || _sending) return;
    setState(() => _sending = true);
    try {
      final attempt = '${room['id']}|${_reply?['id']}|$text';
      if (_lastAttempt != attempt) {
        _lastAttempt = attempt;
        _attemptNonce = partyNonce();
      }
      await client.sendText(
        room['id'].toString(),
        text,
        replyTo: partyInt(_reply?['id']) == 0 ? null : partyInt(_reply?['id']),
        messageNonce: _attemptNonce,
      );
      if (!mounted || generation != _generation) return;
      if (_draft.text.trim() == text) _draft.clear();
      _reply = null;
      _lastAttempt = null;
      _attemptNonce = null;
      final page = await client.messages(room['id'].toString());
      if (mounted && _room?['id'] == room['id']) {
        setState(() {
          _messages = _rows(page['messages']);
          _more = page['has_more'] == true;
        });
      }
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      if (mounted) _notice(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _search() async {
    final value = await _input(
      context,
      'پیداکردن دوست',
      'آیدی MBN یا نام کاربری کامل',
      ltr: true,
    );
    if (value == null || !mounted) return;
    try {
      final user = await client.find(value);
      if (!mounted) return;
      if (user == null) {
        _notice(context, 'کاربری با این آیدی پیدا نشد.');
        return;
      }
      if (await _confirm(
        context,
        _name(user),
        'درخواست دوستی برای این حساب ارسال شود؟',
      )) {
        await client.addFriend(partyInt(user['id']));
      }
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Future<void> _newGroup() async {
    final selected = await _chooseFriends(
      context,
      client,
      title: 'ساخت گروه',
      withTitle: true,
    );
    if (selected == null) return;
    try {
      final room = await client.createRoom(
        members: List<int>.from(selected['ids'] as List),
        group: true,
        title: selected['title'].toString(),
      );
      if (mounted) await _select(room['id'].toString());
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Future<void> _contact(PartyJson user) async {
    try {
      final room = await client.createRoom(members: [partyInt(user['id'])]);
      if (mounted) await _select(room['id'].toString());
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _ink,
        appBar: AppBar(
          backgroundColor: _ink,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.diversity_2_rounded, color: _mint),
              SizedBox(width: 10),
              Text('پارتی', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'پیداکردن دوست',
              onPressed: _search,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            IconButton(
              tooltip: 'گروه جدید',
              onPressed: client.friends.isEmpty ? null : _newGroup,
              icon: const Icon(Icons.group_add_rounded),
            ),
            IconButton(
              tooltip: 'تازه‌سازی',
              onPressed: client.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            if (client.error != null)
              MaterialBanner(
                content: Text(client.error!),
                leading: const Icon(Icons.cloud_off_rounded),
                actions: [
                  TextButton(
                    onPressed: client.refresh,
                    child: const Text('تلاش دوباره'),
                  ),
                ],
              ),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        SizedBox(width: 330, child: _inbox()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _chat()),
                      ],
                    )
                  : AnimatedSwitcher(
                      duration: Duration(
                        milliseconds: PartyHub.instance.reduceMotion ? 0 : 220,
                      ),
                      child: _room != null || _loading
                          ? KeyedSubtree(
                              key: const ValueKey('chat'),
                              child: _chat(),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('inbox'),
                              child: _inbox(),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inbox() => Column(
    children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF23344B), Color(0xFF25233E)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _violet.withValues(alpha: .2)),
        ),
        child: Row(
          children: [
            const _Avatar(label: 'من', self: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(client.me),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    client.publicId,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: _mint, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'کپی آیدی من',
              onPressed: client.loaded
                  ? () async {
                      await Clipboard.setData(
                        ClipboardData(text: client.publicId),
                      );
                      if (mounted) _notice(context, 'آیدی کپی شد.');
                    }
                  : null,
              icon: const Icon(Icons.copy_rounded, size: 19),
            ),
          ],
        ),
      ),
      if (client.hasActiveParty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: client.sessions
                .take(4)
                .map((s) => _sessionCard(s))
                .toList(),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<int>(
          segments: [
            const ButtonSegment(
              value: 0,
              label: Text('چت‌ها'),
              icon: Icon(Icons.chat_bubble_outline_rounded),
            ),
            ButtonSegment(
              value: 1,
              label: Text('دوستان ${client.friends.length}'),
              icon: const Icon(Icons.people_outline_rounded),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: !client.loaded && client.error == null
            ? const Center(child: CircularProgressIndicator())
            : _tab == 1
            ? _friends()
            : _rooms(),
      ),
    ],
  );

  Widget _rooms() => client.rooms.isEmpty
      ? _empty(
          Icons.forum_outlined,
          'جای دوستانت اینجا خالی است',
          'با آیدی دوستت شروع کن و یک گفت‌وگو بساز.',
          action: _search,
          label: 'افزودن دوست',
        )
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
          itemCount: client.rooms.length + (client.hasMoreRooms ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (ctx, i) {
            if (i == client.rooms.length) {
              return TextButton(
                onPressed: client.loadingRooms
                    ? null
                    : () async {
                        try {
                          await client.moreRooms();
                        } catch (e) {
                          if (mounted) _notice(context, e);
                        }
                      },
                child: Text(
                  client.loadingRooms ? 'در حال دریافت…' : 'گفت‌وگوهای بیشتر',
                ),
              );
            }
            final room = client.rooms[i],
                name = _roomName(room, client.userId),
                last = room['last_message'] as Map?;
            final preview = last == null
                ? 'گفت‌وگو را شروع کن'
                : last['deleted_at'] != null
                ? 'پیام حذف شده'
                : last['kind'] == 'media'
                ? '🎬 فیلم یا دعوت تماشا'
                : last['body']?.toString() ?? '';
            return Material(
              color: _room?['id'] == room['id'] ? _panel : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onTap: () => _select(room['id'].toString()),
                leading: _Avatar(label: name, group: room['kind'] == 'group'),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: partyInt(room['unread']) > 0
                    ? CircleAvatar(
                        radius: 12,
                        backgroundColor: _mint,
                        child: Text(
                          '${partyInt(room['unread']).clamp(0, 99)}',
                          style: const TextStyle(fontSize: 10, color: _ink),
                        ),
                      )
                    : const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white30,
                      ),
              ),
            );
          },
        );

  Widget _friends() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
    children: [
      for (final r in client.requests)
        Card(
          color: _panel,
          child: ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded, color: _mint),
            title: Text(_name(Map<String, dynamic>.from(r['user'] as Map))),
            subtitle: Text(
              partyInt(r['recipient_id']) == client.userId
                  ? 'درخواست دوستی تازه'
                  : 'درخواست ارسال شد',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (partyInt(r['recipient_id']) == client.userId)
                  IconButton(
                    tooltip: 'قبول درخواست',
                    icon: const Icon(Icons.check_circle_rounded, color: _mint),
                    onPressed: () => _friendReply(r, 'accept'),
                  ),
                IconButton(
                  tooltip: 'رد یا لغو درخواست',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _friendReply(
                    r,
                    partyInt(r['recipient_id']) == client.userId
                        ? 'decline'
                        : 'cancel',
                  ),
                ),
              ],
            ),
          ),
        ),
      if (client.friends.isEmpty)
        _empty(
          Icons.people_outline_rounded,
          'دوستان در هر دو اپ مشترک‌اند',
          'آیدی‌ات را برای دوستت بفرست یا آیدی او را پیدا کن.',
          action: _search,
          label: 'پیداکردن دوست',
        ),
      for (final user in client.friends)
        ListTile(
          leading: _Avatar(label: _name(user)),
          title: Text(_name(user)),
          subtitle: Text(
            user['public_id']?.toString() ?? '',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          onTap: () => _contact(user),
          trailing: PopupMenuButton<String>(
            onSelected: (action) => _friendAction(user, action),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'remove', child: Text('حذف از دوستان')),
              PopupMenuItem(value: 'block', child: Text('مسدودکردن')),
            ],
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _blocked,
        icon: const Icon(Icons.block_rounded),
        label: const Text('کاربران مسدودشده'),
      ),
    ],
  );

  Future<void> _friendReply(PartyJson r, String action) async {
    try {
      await client.replyFriend(partyInt(r['id']), action);
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Future<void> _friendAction(PartyJson user, String action) async {
    if (!await _confirm(
      context,
      action == 'block' ? 'مسدودکردن دوست' : 'حذف دوست',
      'ارتباط خصوصی با ${_name(user)} غیرفعال می‌شود.',
    )) {
      return;
    }
    try {
      if (action == 'block') {
        await client.block(partyInt(user['id']));
      } else {
        await client.removeFriend(partyInt(user['id']));
      }
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Future<void> _blocked() async {
    try {
      final data = await client.call('GET', '/api/party/blocks');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('کاربران مسدودشده')),
              if (_rows(data['users']).isEmpty)
                const ListTile(title: Text('کسی مسدود نشده است.')),
              for (final user in _rows(data['users']))
                ListTile(
                  title: Text(_name(user)),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await client.block(partyInt(user['id']), value: false);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) _notice(ctx, e);
                      }
                    },
                    child: const Text('رفع مسدودی'),
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Widget _chat() {
    final room = _room;
    if (room == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _empty(
        Icons.movie_filter_outlined,
        _failure ?? 'از یک گفت‌وگو شروع کن',
        'دوستان، فیلم‌ها و لحظه‌های مشترک، اینجا کنار هم‌اند.',
      );
    }
    final permissions = Map<String, dynamic>.from(
      room['permissions'] as Map? ?? {},
    );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _panel.withValues(alpha: .6),
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'بازگشت به چت‌ها',
                onPressed: () {
                  _generation++;
                  setState(() {
                    _room = null;
                    _messages = [];
                  });
                },
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              _Avatar(
                label: _roomName(room, client.userId),
                group: room['kind'] == 'group',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _manage(room),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _roomName(room, client.userId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        room['kind'] == 'group'
                            ? '${_rows(room['members']).length} عضو · اطلاعات گروه'
                            : 'گفت‌وگوی خصوصی',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (room['kind'] == 'group')
                IconButton(
                  tooltip: 'مدیریت گروه',
                  onPressed: () => _manage(room),
                  icon: const Icon(Icons.tune_rounded),
                ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_failure != null)
          TextButton(
            onPressed: () => _select(room['id'].toString()),
            child: Text('$_failure · تلاش دوباره'),
          ),
        Expanded(
          child: _messages.isEmpty
              ? _empty(
                  Icons.chat_bubble_outline_rounded,
                  'اولین پیام را تو بفرست',
                  'فارسی، ایموجی و دعوت تماشا؛ همگی اینجا هستند.',
                )
              : ListView.builder(
                  key: ValueKey(room['id']),
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_more ? 1 : 0),
                  itemBuilder: (ctx, i) => i == _messages.length
                      ? TextButton(
                          onPressed: _loading ? null : _older,
                          child: const Text('پیام‌های قدیمی‌تر'),
                        )
                      : _bubble(_messages[_messages.length - 1 - i]),
                ),
        ),
        if (_reply != null)
          Container(
            color: _panel,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.reply_rounded, color: _mint, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _reply!['body']?.toString() ?? 'فیلم',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _reply = null),
                  tooltip: 'لغو پاسخ',
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('party-message-input'),
                    controller: _draft,
                    enabled: _yes(permissions['can_message']),
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: _yes(permissions['can_message'])
                          ? 'پیام بنویس…'
                          : 'اجازهٔ ارسال پیام نداری',
                      filled: true,
                      fillColor: _panel,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('party-message-send'),
                  tooltip: 'ارسال پیام',
                  onPressed: _sending || !_yes(permissions['can_message'])
                      ? null
                      : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(PartyJson message) {
    final mine = partyInt(message['sender_id']) == client.userId,
        deleted = message['deleted_at'] != null;
    final sender = message['sender'] is Map
        ? Map<String, dynamic>.from(message['sender'] as Map)
        : <String, dynamic>{};
    final text = message['body']?.toString() ?? '';
    final first = RegExp(r'[A-Za-z\u0600-\u06ff]').firstMatch(text)?.group(0);
    final direction = first != null && RegExp(r'[A-Za-z]').hasMatch(first)
        ? TextDirection.ltr
        : TextDirection.rtl;
    final reply = _messages
        .where((m) => m['id'] == message['reply_to'])
        .firstOrNull;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: 10,
            left: mine ? 28 : 0,
            right: mine ? 0 : 28,
          ),
          child: GestureDetector(
            onLongPress: deleted ? null : () => _messageMenu(message),
            onSecondaryTap: deleted ? null : () => _messageMenu(message),
            child: AnimatedContainer(
              duration: Duration(
                milliseconds: PartyHub.instance.reduceMotion ? 0 : 180,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF253D46) : _panel,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(19),
                  topRight: const Radius.circular(19),
                  bottomLeft: Radius.circular(mine ? 19 : 5),
                  bottomRight: Radius.circular(mine ? 5 : 19),
                ),
                border: Border.all(
                  color: mine
                      ? _mint.withValues(alpha: .12)
                      : Colors.white.withValues(alpha: .04),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine && _room?['kind'] == 'group')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        _name(sender),
                        style: const TextStyle(
                          fontSize: 11,
                          color: _mint,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (message['reply_to'] != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          right: BorderSide(color: _violet, width: 2),
                        ),
                      ),
                      child: Text(
                        reply?['body']?.toString().isNotEmpty == true
                            ? reply!['body'].toString()
                            : 'پاسخ به پیام قبلی',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (deleted)
                    const Text(
                      'این پیام حذف شده است.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (message['kind'] == 'media')
                    _mediaCard(message)
                  else
                    SelectableText(
                      text,
                      textDirection: direction,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: message['kind'] == 'restricted'
                            ? Colors.white38
                            : Colors.white,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _clockLabel(partyInt(message['created_at'])),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                      ),
                      if (message['edited_at'] != null)
                        const Text(
                          ' · ویرایش‌شده',
                          style: TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                      if (!deleted) ...[
                        const SizedBox(width: 6),
                        InkResponse(
                          onTap: () => _messageMenu(message),
                          radius: 18,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.add_reaction_outlined,
                              size: 15,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_rows(message['reactions']).isNotEmpty)
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: _rows(message['reactions'])
                          .map(
                            (r) => ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${r['emoji']} ${r['count']}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: _yes(r['mine'])
                                  ? _violet.withValues(alpha: .25)
                                  : Colors.white10,
                              onPressed: () => _react(
                                message,
                                r['emoji'].toString(),
                                !_yes(r['mine']),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaCard(PartyJson message) {
    final media = Map<String, dynamic>.from(message['payload'] as Map? ?? {}),
        session = message['session'] as Map?;
    final closed = session?['state'] == 'closed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 74,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: Colors.black26,
              ),
              child: media['poster']?.toString().isNotEmpty == true
                  ? Image.network(
                      media['poster'].toString(),
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.movie_outlined, color: _violet),
                    )
                  : const Icon(Icons.movie_outlined, color: _violet),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (media['episode_title']?.toString().isNotEmpty == true)
                    Text(
                      media['episode_title'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    session == null
                        ? 'یک پیشنهاد برای تماشا'
                        : closed
                        ? 'این پارتی بسته شده است'
                        : 'دعوت به تماشای هم‌زمان',
                    style: TextStyle(
                      fontSize: 11,
                      color: closed ? Colors.white38 : _mint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (session != null && !closed)
              FilledButton.icon(
                onPressed: () => _openMedia(media, session['id'].toString()),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('پیوستن به پارتی'),
              ),
            OutlinedButton.icon(
              onPressed: () => _openMedia(media, null),
              icon: const Icon(Icons.movie_outlined, size: 18),
              label: Text(session == null ? 'دیدن عنوان' : 'تماشای مستقل'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openMedia(PartyJson media, String? sid) async {
    try {
      final open = PartyHub.instance.openMedia;
      if (open == null) throw const PartyException('مسیر پخش هنوز آماده نیست.');
      await open(context, media, sid);
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Widget _sessionCard(PartyJson s) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: _mint.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.sensors_rounded, color: _mint),
        title: Text(
          (s['payload'] as Map?)?['title']?.toString() ?? 'پارتی فعال',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          s['state'] == 'waiting' ? 'منتظر همراه' : 'تماشا در جریان است',
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
        trailing: partyInt(s['host_id']) == client.userId
            ? IconButton(
                tooltip: 'بستن پارتی',
                icon: const Icon(Icons.close_rounded, size: 18, color: _mint),
                onPressed: () async {
                  if (await _confirm(
                    context,
                    'پایان پارتی',
                    'این دعوت برای همه بسته شود؟',
                  )) {
                    try {
                      await client.command(
                        s['id'].toString(),
                        'end',
                        clientId: partyNonce(),
                      );
                      await client.refresh();
                    } catch (e) {
                      if (mounted) _notice(context, e);
                    }
                  }
                },
              )
            : const Icon(Icons.arrow_outward_rounded, size: 18, color: _mint),
        onTap: () => _openMedia(
          Map<String, dynamic>.from(s['payload'] as Map),
          s['id'].toString(),
        ),
      ),
    ),
  );

  Future<void> _react(PartyJson message, String emoji, bool active) async {
    try {
      await client.reaction(partyInt(message['id']), emoji, active: active);
      await _refreshMessage(partyInt(message['id']));
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Future<void> _messageMenu(PartyJson message) async {
    final mine = partyInt(message['sender_id']) == client.userId,
        manage = _yes((_room?['permissions'] as Map?)?['can_manage']);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      [
                            '❤️',
                            '👍',
                            '😂',
                            '😍',
                            '😮',
                            '😢',
                            '🔥',
                            '🎉',
                            '👏',
                            '🤝',
                            '💯',
                            '👎',
                          ]
                          .map(
                            (e) => TextButton(
                              onPressed: () => Navigator.pop(ctx, 'emoji:$e'),
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 23),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('پاسخ'),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              if (message['kind'] == 'text')
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('کپی متن'),
                  onTap: () => Navigator.pop(ctx, 'copy'),
                ),
              if (mine && message['kind'] == 'text')
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('ویرایش پیام'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              if (mine || manage)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('حذف پیام'),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action.startsWith('emoji:')) {
      final emoji = action.substring(6),
          reaction = _rows(
            message['reactions'],
          ).where((r) => r['emoji'] == emoji).firstOrNull;
      await _react(message, emoji, !_yes(reaction?['mine']));
      return;
    }
    try {
      if (action == 'reply') {
        setState(() => _reply = message);
        return;
      }
      if (action == 'copy') {
        await Clipboard.setData(
          ClipboardData(text: message['body'].toString()),
        );
        return;
      }
      if (action == 'edit') {
        final text = await _input(
          context,
          'ویرایش پیام',
          'پیام',
          initial: message['body'].toString(),
          maxLength: 4000,
        );
        if (text != null) {
          await client.editMessage(partyInt(message['id']), text);
        }
      }
      if (!mounted) return;
      if (action == 'delete' &&
          await _confirm(
            context,
            'حذف پیام',
            'این پیام برای اعضای گفت‌وگو حذف شود؟',
          )) {
        await client.deleteMessage(partyInt(message['id']));
      }
      await _refreshMessage(partyInt(message['id']));
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }

  Future<void> _manage(PartyJson original) async {
    try {
      final room = await client.room(original['id'].toString());
      if (!mounted) return;
      final permissions = Map<String, dynamic>.from(room['permissions'] as Map),
          owner = room['my_role'] == 'owner';
      final members = _rows(room['members']);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _roomName(room, client.userId),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_yes(permissions['can_manage']) && room['kind'] == 'group')
                  ListTile(
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('تغییر نام گروه'),
                    onTap: () async {
                      final title = await _input(
                        ctx,
                        'نام گروه',
                        'نام',
                        initial: room['title'].toString(),
                        maxLength: 80,
                      );
                      if (title != null) {
                        try {
                          await client.renameRoom(room['id'].toString(), title);
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) _notice(ctx, e);
                        }
                      }
                    },
                  ),
                if (_yes(permissions['can_invite']) && room['kind'] == 'group')
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: const Text('افزودن دوست به گروه'),
                    onTap: () async {
                      final selection = await _chooseFriends(
                        ctx,
                        client,
                        title: 'دعوت به گروه',
                        exclude: members
                            .map((m) => partyInt(m['user_id']))
                            .toSet(),
                      );
                      if (selection != null) {
                        try {
                          for (final uid in selection['ids'] as List) {
                            await client.member(
                              room['id'].toString(),
                              uid as int,
                              {},
                              method: 'PUT',
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) _notice(ctx, e);
                        }
                      }
                    },
                  ),
                for (final member in members)
                  ListTile(
                    leading: _Avatar(
                      label: _name(
                        Map<String, dynamic>.from(member['user'] as Map),
                      ),
                    ),
                    title: Text(
                      _name(Map<String, dynamic>.from(member['user'] as Map)),
                    ),
                    subtitle: Text(
                      member['role'] == 'owner'
                          ? 'مالک گروه'
                          : member['role'] == 'admin'
                          ? 'مدیر گروه'
                          : 'عضو',
                    ),
                    trailing:
                        room['kind'] == 'group' &&
                            _yes(permissions['can_manage']) &&
                            member['role'] != 'owner'
                        ? PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'permissions') {
                                await _memberPermissions(
                                  ctx,
                                  client,
                                  room,
                                  member,
                                  owner: owner,
                                );
                              }
                              if (!ctx.mounted) return;
                              if (action == 'remove' &&
                                  await _confirm(
                                    ctx,
                                    'حذف عضو',
                                    'این عضو از گروه حذف شود؟',
                                  )) {
                                try {
                                  await client.member(
                                    room['id'].toString(),
                                    partyInt(member['user_id']),
                                    {},
                                    method: 'DELETE',
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) _notice(ctx, e);
                                }
                              }
                              if (!ctx.mounted) return;
                              if (action == 'owner' &&
                                  await _confirm(
                                    ctx,
                                    'انتقال مالکیت',
                                    'مدیریت اصلی گروه به این عضو منتقل شود؟',
                                  )) {
                                try {
                                  await client.member(
                                    room['id'].toString(),
                                    partyInt(member['user_id']),
                                    {'role': 'owner'},
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) _notice(ctx, e);
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'permissions',
                                child: Text('نقش و دسترسی‌ها'),
                              ),
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('حذف از گروه'),
                              ),
                              if (owner)
                                const PopupMenuItem(
                                  value: 'owner',
                                  child: Text('انتقال مالکیت'),
                                ),
                            ],
                          )
                        : null,
                  ),
                if (room['kind'] == 'group') ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('خروج از گروه'),
                    onTap: () async {
                      if (owner) {
                        _notice(
                          ctx,
                          'ابتدا مالکیت گروه را به عضو دیگری منتقل کن.',
                        );
                        return;
                      }
                      try {
                        await client.member(
                          room['id'].toString(),
                          client.userId,
                          {},
                          method: 'DELETE',
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() => _room = null);
                      } catch (e) {
                        if (ctx.mounted) _notice(ctx, e);
                      }
                    },
                  ),
                  if (owner)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.redAccent,
                      ),
                      title: const Text('حذف کامل گروه'),
                      onTap: () async {
                        if (!await _confirm(
                          ctx,
                          'حذف گروه',
                          'تمام پیام‌ها و پارتی‌های این گروه حذف می‌شوند.',
                        )) {
                          return;
                        }
                        try {
                          await client.deleteRoom(room['id'].toString());
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) setState(() => _room = null);
                        } catch (e) {
                          if (ctx.mounted) _notice(ctx, e);
                        }
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      );
      if (mounted && _room?['id'] == room['id']) {
        await _select(room['id'].toString());
      }
    } catch (e) {
      if (mounted) _notice(context, e);
    }
  }
}

Future<void> _memberPermissions(
  BuildContext context,
  PartyClient client,
  PartyJson room,
  PartyJson member, {
  required bool owner,
}) async {
  final values = {
    for (final key in _permissionNames.keys) key: _yes(member[key]),
  };
  var role = member['role']?.toString() ?? 'member';
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('نقش و دسترسی‌های عضو'),
        content: SizedBox(
          width: 390,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (owner)
                  SwitchListTile(
                    title: const Text('مدیر گروه'),
                    value: role == 'admin',
                    onChanged: busy
                        ? null
                        : (v) => set(() => role = v ? 'admin' : 'member'),
                  ),
                for (final item in _permissionNames.entries)
                  SwitchListTile(
                    title: Text(item.value),
                    value: values[item.key]!,
                    onChanged: busy
                        ? null
                        : (v) => set(() => values[item.key] = v),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    set(() => busy = true);
                    try {
                      await client.member(
                        room['id'].toString(),
                        partyInt(member['user_id']),
                        {...values, if (owner) 'role': role},
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        set(() {
                          busy = false;
                          error = '$e';
                        });
                      }
                    }
                  },
            child: Text(busy ? 'ذخیره…' : 'ذخیره'),
          ),
        ],
      ),
    ),
  );
}

const _permissionNames = {
  'can_message': 'ارسال پیام و واکنش',
  'can_share': 'ارسال فیلم و دعوت تماشا',
  'can_invite': 'افزودن اعضا',
  'can_manage': 'مدیریت اعضا و پیام‌ها',
  'can_control': 'کنترل پخش پارتی',
};

Future<String?> _input(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
  bool ltr = false,
  int maxLength = 80,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        maxLines: maxLength > 100 ? 5 : 1,
        textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(ctx, v);
          },
          child: const Text('تأیید'),
        ),
      ],
    ),
  );
  // Route animations may still reference the controller during dismissal.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

Future<PartyJson?> _chooseFriends(
  BuildContext context,
  PartyClient client, {
  required String title,
  bool withTitle = false,
  Set<int> exclude = const {},
}) async {
  final selected = <int>{}, controller = TextEditingController();
  String? error;
  final result = await showDialog<PartyJson>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (withTitle)
                  TextField(
                    controller: controller,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'نام گروه'),
                  ),
                if (client.friends
                    .where((f) => !exclude.contains(partyInt(f['id'])))
                    .isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('دوست قابل افزودن وجود ندارد.'),
                  ),
                for (final user in client.friends.where(
                  (f) => !exclude.contains(partyInt(f['id'])),
                ))
                  CheckboxListTile(
                    title: Text(_name(user)),
                    value: selected.contains(partyInt(user['id'])),
                    onChanged: (v) => set(() {
                      if (v == true) {
                        selected.add(partyInt(user['id']));
                      } else {
                        selected.remove(partyInt(user['id']));
                      }
                    }),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              if (selected.isEmpty ||
                  selected.length > 49 ||
                  (withTitle && controller.text.trim().isEmpty)) {
                set(() => error = 'نام گروه و ۱ تا ۴۹ دوست را انتخاب کن.');
                return;
              }
              Navigator.pop(ctx, {
                'ids': selected.toList(),
                'title': controller.text.trim(),
              });
            },
            child: const Text('ادامه'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

Widget _empty(
  IconData icon,
  String title,
  String text, {
  VoidCallback? action,
  String label = '',
}) => Center(
  child: SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _violet.withValues(alpha: .08),
            ),
            child: Icon(icon, color: _violet, size: 42),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.6),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: action, child: Text(label)),
          ],
        ],
      ),
    ),
  ),
);

String _clockLabel(int value) {
  final d = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, this.group = false, this.self = false});
  final String label;
  final bool group, self;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      gradient: LinearGradient(
        colors: self
            ? const [Color(0xFF426F69), Color(0xFF4D497D)]
            : const [Color(0xFF33445A), Color(0xFF30324D)],
      ),
    ),
    alignment: Alignment.center,
    child: group
        ? const Icon(Icons.groups_rounded, color: _violet)
        : self
        ? const Icon(Icons.person_rounded, color: _mint)
        : Text(
            label.characters.take(1).toString(),
            style: const TextStyle(
              color: _mint,
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
  );
}

/// Called after the app resolves an actual logical episode. No playback URL is
/// included in the message; recipients resolve their own authorized stream.
Future<void> sendPartyMedia(
  BuildContext context,
  PartyJson media, {
  int currentPositionMs = 0,
  int? durationMs,
  PartyOpenMedia? openMedia,
}) async {
  final client = PartyHub.instance.client;
  if (client == null) {
    _notice(context, 'برای ارسال به دوستان وارد حساب شو.');
    return;
  }
  await client.refresh();
  if (!context.mounted) return;
  if (client.friends.isEmpty && client.rooms.isEmpty) {
    await openParty(context);
    return;
  }
  final h = TextEditingController(
        text: currentPositionMs > 0 ? '${currentPositionMs ~/ 3600000}' : '',
      ),
      m = TextEditingController(
        text: currentPositionMs > 0
            ? '${(currentPositionMs % 3600000) ~/ 60000}'
            : '',
      ),
      s = TextEditingController(
        text: currentPositionMs > 0
            ? '${(currentPositionMs % 60000) ~/ 1000}'
            : '',
      );
  var mode = 2;
  String? target, error;
  PartyJson? selected;
  bool friend = false;
  final result = await showDialog<PartyJson>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('ارسال برای دوستان'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media['title']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (media['episode_title'] != null)
                  Text(
                    media['episode_title'].toString(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'برای چه کسی؟'),
                  items: [
                    for (final user in client.friends)
                      DropdownMenuItem(
                        value: 'f:${user['id']}',
                        child: Text(
                          _name(user),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final room in client.rooms.where(
                      (r) => r['kind'] == 'group',
                    ))
                      DropdownMenuItem(
                        value: 'r:${room['id']}',
                        child: Text(
                          'گروه · ${_roomName(room, client.userId)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => set(() {
                    target = v;
                    friend = v?.startsWith('f:') == true;
                    selected = friend
                        ? client.friends.firstWhere((f) => 'f:${f['id']}' == v)
                        : client.rooms.firstWhere((r) => 'r:${r['id']}' == v);
                  }),
                ),
                const SizedBox(height: 16),
                for (final choice in [
                  (0, 'شروع تماشا با دوست از اول زمان'),
                  (1, 'شروع تماشا با دوست از زمان دلخواه'),
                  (2, 'بدون زمان و فقط ارسال عنوان'),
                ])
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: choice.$1,
                    groupValue: mode,
                    onChanged: (v) => set(() => mode = v!),
                    title: Text(
                      choice.$2,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                if (mode == 1)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        for (final input in [
                          (h, 'ساعت'),
                          (m, 'دقیقه'),
                          (s, 'ثانیه'),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: TextField(
                                controller: input.$1,
                                keyboardType: TextInputType.number,
                                maxLength: input.$2 == 'ساعت' ? 3 : 2,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9۰-۹٠-٩]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: input.$2,
                                  counterText: '',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (mode != 2)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'پلیر تو باز می‌شود و تا آماده‌شدن دوستت منتظر می‌ماند.',
                      style: TextStyle(fontSize: 12, color: _mint, height: 1.6),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (selected == null) {
                set(() => error = 'یک دوست یا گروه را انتخاب کن.');
                return;
              }
              try {
                final time = mode == 1
                    ? parsePartyTime(
                        h.text,
                        m.text,
                        s.text,
                        durationMs: durationMs,
                      )
                    : 0;
                Navigator.pop(ctx, {
                  'target': selected,
                  'friend': friend,
                  'mode': mode,
                  'position': time,
                });
              } on FormatException catch (e) {
                set(() => error = e.message);
              }
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('ارسال'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  h.dispose();
  m.dispose();
  s.dispose();
  if (result == null || !context.mounted) return;
  try {
    final targetData = Map<String, dynamic>.from(result['target'] as Map);
    final room = result['friend'] == true
        ? await client.createRoom(members: [partyInt(targetData['id'])])
        : targetData;
    final roomId = room['id'].toString();
    if (result['mode'] == 2) {
      await client.sendMedia(roomId, media);
      if (context.mounted) _notice(context, 'عنوان برای دوستت ارسال شد.');
    } else {
      final session = await client.createSession(
        roomId,
        media,
        partyInt(result['position']),
      );
      if (!context.mounted) return;
      final open = openMedia ?? PartyHub.instance.openMedia;
      if (open == null) {
        throw const PartyException(
          'مسیر پلیر آماده نیست؛ دعوت در چت ذخیره شد.',
        );
      }
      await open(context, media, session['id'].toString());
    }
  } catch (e) {
    if (context.mounted) _notice(context, e);
  }
}

class WatchPartyBanner extends StatelessWidget {
  const WatchPartyBanner({super.key, required this.controller});
  final WatchPartyController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Material(
      color: _ink.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showWatchPartyPanel(context, controller),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                controller.connected
                    ? Icons.sensors_rounded
                    : Icons.cloud_off_rounded,
                size: 17,
                color: controller.connected ? _mint : Colors.amber,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  controller.status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showWatchPartyPanel(
  BuildContext context,
  WatchPartyController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (ctx, _) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'با هم تماشا می‌کنیم',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(controller.status, style: const TextStyle(color: _mint)),
                const SizedBox(height: 10),
                for (final member in _rows(controller.snapshot['participants']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _Avatar(
                      label: _name(
                        Map<String, dynamic>.from(member['user'] as Map),
                      ),
                    ),
                    title: Text(
                      _name(Map<String, dynamic>.from(member['user'] as Map)),
                    ),
                    subtitle: Text(
                      !_yes(member['online'])
                          ? 'اتصال قطع شده؛ امکان پیوستن دوباره'
                          : _yes(member['ready'])
                          ? 'پلیر آماده است'
                          : 'در حال آماده‌کردن ویدیو',
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await openParty(
                          context,
                          roomId: controller.snapshot['room_id']?.toString(),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('بازکردن چت'),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.closed
                          ? null
                          : () async {
                              try {
                                await controller.leave();
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (ctx.mounted) _notice(ctx, e);
                              }
                            },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('خروج از پارتی'),
                    ),
                    if (partyInt(controller.snapshot['host_id']) ==
                        controller.client.userId)
                      TextButton(
                        onPressed: controller.closed
                            ? null
                            : () async {
                                try {
                                  await controller.leave(end: true);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) _notice(ctx, e);
                                }
                              },
                        child: const Text('پایان پارتی برای همه'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
