import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/movie_content.dart';
import '../services/movie_api.dart';
import '../widgets/ambient_background.dart';
import '../widgets/content_art.dart';
import '../widgets/pressable.dart';

class CastSearchScreen extends StatefulWidget {
  const CastSearchScreen({super.key, required this.api, required this.onOpen});
  final MovieApi api;
  final Future<void> Function(MovieContent item, String tag) onOpen;

  @override
  State<CastSearchScreen> createState() => _CastSearchScreenState();
}

class _CastSearchScreenState extends State<CastSearchScreen> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final people = <MoviePerson>[];
  Timer? debounce;
  int page = 0;
  int generation = 0;
  bool loading = false;
  bool more = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  /// اگر همه موارد در صفحه جا شوند و اسکرولی وجود نداشته باشد، صفحه‌های
  /// بعدی خودکار خوانده می‌شوند تا فهرست نصفه نماند.
  void _fillIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || loading || !more) return;
      if (!scroll.hasClients) return;
      final position = scroll.position;
      if (position.maxScrollExtent <= position.viewportDimension + 50) {
        _load();
      }
    });
  }

  void _changed(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 420), () {
      generation++;
      setState(() {
        page = 0;
        people.clear();
        more = true;
        error = null;
        loading = false;
      });
      _load();
    });
  }

  Future<void> _load() async {
    if (loading || !more) return;
    final query = controller.text.trim();
    if (query.isNotEmpty && query.length < 2) return;
    final ticket = generation;
    setState(() { loading = true; error = null; });
    try {
      final result = query.isEmpty
          ? await widget.api.actors(page: page + 1)
          : await widget.api.searchActors(query, page: page + 1);
      if (!mounted || generation != ticket) return;
      setState(() {
        page++;
        final before = people.length;
        final seen = {for (final person in people) person.id};
        for (final person in result) {
          if (seen.add(person.id)) people.add(person);
        }
        // صفحه‌ای که هیچ مورد تازه‌ای ندهد یعنی انتهای فهرست.
        more = result.isNotEmpty && people.length > before;
      });
      _fillIfNeeded();
    } on MovieApiException catch (e) {
      if (mounted && generation == ticket) setState(() => error = e.message);
    } finally {
      if (mounted && generation == ticket) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('بازیگران')),
    body: AmbientBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: controller,
              hintText: 'جست‌وجوی بازیگران',
              leading: const Icon(Icons.search_rounded),
              onChanged: _changed,
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notice) {
                if (notice.metrics.extentAfter < 400) _load();
                return false;
              },
              child: GridView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170, mainAxisExtent: 188,
                  crossAxisSpacing: 12, mainAxisSpacing: 12,
                ),
                itemCount: people.length + (loading || error != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == people.length) {
                    return Center(child: error == null
                        ? const CircularProgressIndicator()
                        : TextButton(onPressed: _load, child: Text(error!)));
                  }
                  final person = people[index];
                  return Pressable(
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                      builder: (_) => CastTitlesScreen(
                        person: person, api: widget.api, onOpen: widget.onOpen),
                    )),
                    child: Card(
                      color: MovieColors.surfaceHigh,
                      child: Column(children: [
                        const SizedBox(height: 10),
                        CircleAvatar(
                          radius: 57,
                          backgroundColor: MovieColors.surface,
                          foregroundImage: person.imageUrl == null ||
                                  person.imageUrl!.isEmpty
                              ? null : NetworkImage(person.imageUrl!),
                          child: const Icon(Icons.person_rounded, size: 48),
                        ),
                        const SizedBox(height: 10),
                        Text(person.name, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class CastTitlesScreen extends StatefulWidget {
  const CastTitlesScreen({super.key, required this.person,
    required this.api, required this.onOpen});
  final MoviePerson person;
  final MovieApi api;
  final Future<void> Function(MovieContent item, String tag) onOpen;
  @override
  State<CastTitlesScreen> createState() => _CastTitlesScreenState();
}

class _CastTitlesScreenState extends State<CastTitlesScreen> {
  final titles = <MovieContent>[];
  final scroll = ScrollController();
  int page = 0;
  bool loading = false;
  bool more = true;
  String? error;
  String bio = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _fillIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || loading || !more) return;
      if (!scroll.hasClients) return;
      final position = scroll.position;
      if (position.maxScrollExtent <= position.viewportDimension + 50) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    if (loading || !more) return;
    setState(() { loading = true; error = null; });
    try {
      final details =
          await widget.api.actorDetails(widget.person, page: page + 1);
      if (!mounted) return;
      setState(() {
        page++;
        final before = titles.length;
        final seen = {for (final item in titles) item.id};
        for (final item in details.titles) {
          if (seen.add(item.id)) titles.add(item);
        }
        if (details.bio.isNotEmpty) bio = details.bio;
        more = details.titles.isNotEmpty && titles.length > before;
      });
      _fillIfNeeded();
    } on MovieApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _showBio() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.person.name),
        content: SingleChildScrollView(child: Text(bio)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('باشه'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.person.name)),
    body: AmbientBackground(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notice) {
          if (notice.metrics.extentAfter < 400) _load();
          return false;
        },
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 36,
                      foregroundImage: widget.person.imageUrl == null ||
                              widget.person.imageUrl!.isEmpty
                          ? null : NetworkImage(widget.person.imageUrl!),
                      child: const Icon(Icons.person_rounded),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.person.name,
                          style: Theme.of(context).textTheme.titleLarge),
                        if (widget.person.role.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(widget.person.role,
                              style: const TextStyle(
                                color: MovieColors.muted,
                                fontSize: 12,
                              )),
                          ),
                      ],
                    )),
                  ]),
                  if (bio.length > 15) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _showBio,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('مشاهده بیوگرافی'),
                    ),
                  ],
                ],
              ),
            )),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180, childAspectRatio: .57,
                  crossAxisSpacing: 12, mainAxisSpacing: 12,
                ),
                itemCount: titles.length,
                itemBuilder: (context, index) {
                  final item = titles[index];
                  final tag = 'cast-${widget.person.id}-${item.id}';
                  return Pressable(
                    onTap: () => widget.onOpen(item, tag),
                    child: Hero(tag: tag, child: ContentArt(content: item)),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(child: Center(child: loading
                ? const CircularProgressIndicator()
                : error != null
                    ? TextButton(onPressed: _load, child: Text(error!))
                    : titles.isEmpty ? const Text('اثری پیدا نشد')
                        : const SizedBox.shrink())),
          ],
        ),
      ),
    ),
  );
}
