import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform_ui.dart';
import '../core/episode_catalog.dart';
import '../core/player_preferences.dart';
import '../core/subtitle_layout.dart';
import '../core/theme.dart';
import '../core/title_language.dart';
import '../core/watch_progress.dart';
import '../models/movie_content.dart';
import '../services/movie_api.dart';
import '../services/device_bridge.dart';
import '../services/mbn_sync.dart';
import '../services/picture_in_picture.dart';
import '../widgets/content_art.dart';
import '../widgets/movie_image.dart';
import '../widgets/pressable.dart';
import '../widgets/download_choice.dart';
import '../widgets/player_keyboard.dart';
import '../widgets/player_timeline.dart';
import '../widgets/player_feedback.dart';
import '../widgets/audio_source_actions.dart';
import 'episode_picker_screen.dart';
import 'cast_screen.dart';
import 'playlist_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.content,
    required this.api,
    required this.isFavorite,
    required this.onFavoriteChanged,
    required this.heroTag,
  });

  final MovieContent content;
  final ContentApi api;
  final bool isFavorite;
  final ValueChanged<bool> onFavoriteChanged;

  /// Must match the source card's Hero tag for the shared-element flight.
  final String heroTag;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  static const _downloadsChannel = MethodChannel('com.mbn.movie/downloads');
  late bool _favorite = widget.isFavorite;
  int _detailSection = 0;
  int _detailSectionDirection = 1;
  late Future<MovieContent> _details = _loadDetails(initial: true);
  late Future<List<MovieComment>> _comments = widget.api.comments(
    widget.content.id,
  );

  Future<MovieContent> _loadDetails({bool initial = false}) async {
    // Start the network request immediately, but do not rebuild the app bar or
    // Hero while its 520 ms flight is active. A response landing mid-flight
    // used to cause a visible hitch and briefly put the artwork over controls.
    final request = widget.api.details(widget.content);
    // Observe immediately: without this, a failure inside the flight delay
    // (or while another tab is selected for comments) has no error listener
    // yet and surfaces as an uncaught async error before the FutureBuilder
    // ever subscribes. The no-op branch only marks the error as observed;
    // `return request` still delivers it to the UI.
    unawaited(request.then<void>((_) {}, onError: (_) {}));
    if (initial) {
      await Future<void>.delayed(const Duration(milliseconds: 540));
    }
    return request;
  }

  @override
  void initState() {
    super.initState();
    // Comments are preloaded for instant tab switches, but their FutureBuilder
    // only exists on the comments tab. Guard eagerly so an early failure
    // cannot report as unhandled while another tab is selected.
    unawaited(_comments.then<void>((_) {}, onError: (_) {}));
  }

  void _retry() => setState(() {
    _details = _loadDetails();
    _comments = widget.api.comments(widget.content.id);
    unawaited(_comments.then<void>((_) {}, onError: (_) {}));
  });

  void _toggleFavorite() {
    setState(() => _favorite = !_favorite);
    widget.onFavoriteChanged(_favorite);
  }

  void _selectDetailSection(int value) {
    final max = 2;
    final next = value.clamp(0, max).toInt();
    if (next == _detailSection) return;
    // The tab row is laid out right-to-left, so a higher index sits to the
    // LEFT. A newer page must enter from the left and an older page from
    // the right; otherwise the motion runs against the finger / tapped tab.
    final rtl = Directionality.of(context) != TextDirection.ltr;
    final forward = next > _detailSection;
    setState(() {
      _detailSectionDirection = (forward == rtl) ? -1 : 1;
      _detailSection = next;
    });
  }

  void _swipeDetailSection(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 220) return;
    // Mirror the scroll direction: in RTL dragging right advances to the
    // next (left-side) section, dragging left goes back — content follows
    // the finger like a native RTL pager.
    final rtl = Directionality.of(context) != TextDirection.ltr;
    final forward = rtl ? velocity > 0 : velocity < 0;
    _selectDetailSection(forward ? _detailSection + 1 : _detailSection - 1);
  }

  Future<void> _share(MovieContent item) async {
    final imdbUrl = item.imdbId == null
        ? ''
        : '\nhttps://www.imdb.com/title/${item.imdbId}/';
    await SharePlus.instance.share(
      ShareParams(text: '${item.title}\nدر MBNMovie ببین$imdbUrl'),
    );
  }

  String? _coverImageUrl(MovieContent item) =>
      widget.content.backdropUrl ??
      item.backdropUrl ??
      widget.content.imageUrl ??
      item.imageUrl;

  Future<void> _showCover(
    MovieContent item, {
    String? requestedImageUrl,
    required Object heroTag,
  }) async {
    final imageUrl = requestedImageUrl ?? _coverImageUrl(item);
    if (imageUrl == null) return;
    // پیش‌بارگذاری با همان پروایدر نمایش تا فریم اول بزرگ‌نمایی
    // تصویر آماده باشد و کاور یک لحظه نپرد (چشمک).
    final provider = imageProviderForUrl(imageUrl);
    try {
      await precacheImage(
        provider,
        context,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // بدون پیش‌بار هم باز می‌شود؛ صفحه خطا را خودش نشان می‌دهد.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (routeContext, _, _) => Scaffold(
          backgroundColor: Colors.black.withValues(alpha: .96),
          appBar: AppBar(
            title: const Text('کاور'),
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'ذخیره کاور',
                onPressed: () =>
                    _saveCover(routeContext, item, imageUrl: imageUrl),
                icon: const Icon(Icons.download_rounded),
              ),
              IconButton(
                tooltip: 'اشتراک‌گذاری فایل کاور',
                onPressed: () =>
                    _shareCover(routeContext, item, imageUrl: imageUrl),
                icon: const Icon(Icons.share_rounded),
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: .8,
            maxScale: 5,
            child: Center(
              child: Hero(
                tag: heroTag,
                createRectTween: smoothHeroRectTween,
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          child: child,
                        );
                      },
                  errorBuilder: (_, _, _) => const Text('کاور قابل نمایش نیست'),
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: .97, end: 1.0).animate(animation),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<({Uint8List bytes, String fileName, String mimeType})> _coverFile(
    MovieContent item, {
    String? imageUrl,
  }) async {
    final resolvedImageUrl = imageUrl ?? _coverImageUrl(item);
    if (resolvedImageUrl == null) {
      throw const HttpException('Cover unavailable');
    }
    final http.Response response = await http
        .get(Uri.parse(resolvedImageUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final extension = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
        ? 'webp'
        : 'jpg';
    final mimeType = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final safeTitle = item.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .trim();
    return (
      bytes: response.bodyBytes,
      fileName: 'MBNMovie-$safeTitle-cover.$extension',
      mimeType: mimeType,
    );
  }

  Future<void> _saveCover(
    BuildContext pageContext,
    MovieContent item, {
    String? imageUrl,
  }) async {
    final messenger = ScaffoldMessenger.of(pageContext);
    try {
      final cover = await _coverFile(item, imageUrl: imageUrl);
      String? savedPath;
      if (Platform.isAndroid) {
        savedPath = await _downloadsChannel.invokeMethod<String>('saveImage', {
          'bytes': cover.bytes,
          'fileName': cover.fileName,
          'mimeType': cover.mimeType,
        });
      } else if (Platform.isWindows) {
        final downloads = await getDownloadsDirectory();
        if (downloads == null) throw const FileSystemException('Downloads');
        final directory = Directory('${downloads.path}\\MBNMovie');
        await directory.create(recursive: true);
        final file = await _uniqueCoverFile(directory, cover.fileName);
        await file.writeAsBytes(cover.bytes, flush: true);
        savedPath = file.path;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'کاور ذخیره شد${savedPath == null ? '' : ': $savedPath'}',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ذخیره کاور انجام نشد. دوباره تلاش کن.')),
      );
    }
  }

  Future<File> _uniqueCoverFile(Directory directory, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var file = File('${directory.path}\\$fileName');
    var index = 2;
    while (await file.exists()) {
      file = File('${directory.path}\\$base ($index)$extension');
      index++;
    }
    return file;
  }

  Future<void> _shareCover(
    BuildContext pageContext,
    MovieContent item, {
    String? imageUrl,
  }) async {
    final messenger = ScaffoldMessenger.of(pageContext);
    try {
      final cover = await _coverFile(item, imageUrl: imageUrl);
      await SharePlus.instance.share(
        ShareParams(
          title: '${item.title} · MBNMovie',
          text: item.title,
          files: [
            XFile.fromData(
              cover.bytes,
              mimeType: cover.mimeType,
              name: cover.fileName,
            ),
          ],
          fileNameOverrides: [cover.fileName],
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('اشتراک‌گذاری کاور انجام نشد.')),
      );
    }
  }

  Future<void> _downloadSeason(MovieContent item, MovieSeason season) async {
    await showDownloadChoice(
      context,
      content: item,
      season: season,
      episodes: season.episodes,
    );
  }

  /// دانلود کاتالوگ‌محور محتوای عادی: یک کیفیتِ یک فصل/فیلم، یکجا.
  Future<void> _downloadSelection(
    MovieContent item,
    MovieSeason season,
    List<MovieEpisode> episodes,
  ) async {
    if (episodes.isEmpty) return;
    await showDownloadChoice(
      context,
      content: item,
      season: season,
      episodes: episodes,
    );
  }

  Future<void> _downloadSeasonByQuality(
    MovieContent item,
    MovieSeason season,
    String quality,
  ) async {
    final filtered = season.episodes
        .where((ep) {
          final epQuality = episodeQuality(ep.name, ep.name);
          return epQuality == quality;
        })
        .toList(growable: false);
    if (filtered.isEmpty) return;
    final qualitySeason = MovieSeason(
      id: '${season.id}-$quality',
      name: '${season.name} · $quality',
      episodes: filtered,
    );
    await showDownloadChoice(
      context,
      content: item,
      season: qualitySeason,
      episodes: filtered,
    );
  }

  Future<void> _play(
    MovieContent content,
    MovieEpisode episode, {
    Duration startAt = Duration.zero,
  }) async {
    await Navigator.of(context).push(
      slideUpRoute(
        PlayerScreen(
          content: content,
          episode: episode,
          initialPosition: startAt,
        ),
        durationMs: 520,
      ),
    );
  }

  Future<void> _openRelated(MovieContent item) async {
    final tag = 'related-${widget.content.id}-${item.id}';
    await Navigator.of(context).push(
      slideUpRoute(
        DetailScreen(
          content: item,
          api: widget.api,
          isFavorite: false,
          onFavoriteChanged: (_) {},
          heroTag: tag,
        ),
        durationMs: 520,
      ),
    );
  }

  Future<void> _openActor(MoviePerson person) async {
    final source = widget.api;
    if (source is! MovieApi) return;
    await Navigator.of(context).push(
      slideUpRoute(
        CastTitlesScreen(
          person: person,
          api: source,
          onOpen: (item, _) => _openRelated(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MovieContent>(
    future: _details,
    builder: (context, snapshot) {
      final item = snapshot.data ?? widget.content;
      final loading = snapshot.connectionState != ConnectionState.done;
      final viewportHeight = MediaQuery.sizeOf(context).height;
      final headerHeight = isLargeScreenDevice
          ? (viewportHeight * .42).clamp(260.0, 380.0)
          : 430.0;
      final hasPlayable = item.seasons.any(
        (season) => season.episodes.isNotEmpty,
      );
      // آدرس‌های پین‌شدهٔ کاور: بندانگشتی و بزرگ‌نمایی دقیقاً یکی باشند تا
      // کاور بزرگ به کوچک تبدیل نشود و هنگام باز شدن نپرد (چشمک).
      final backdropUrl =
          widget.content.backdropUrl ??
          item.backdropUrl ??
          widget.content.imageUrl ??
          item.imageUrl;
      final posterUrl =
          widget.content.imageUrl ??
          item.imageUrl ??
          widget.content.backdropUrl ??
          item.backdropUrl;
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              expandedHeight: headerHeight,
              toolbarHeight: 70,
              pinned: true,
              stretch: true,
              backgroundColor: Colors.black,
              surfaceTintColor: Colors.black,
              leading: Padding(
                padding: const EdgeInsets.all(7),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: IconButton.filledTonal(
                    tooltip: 'اشتراک‌گذاری',
                    onPressed: () => _share(item),
                    icon: const Icon(Icons.share_rounded),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: IconButton.filledTonal(
                    tooltip: 'افزودن به پلی‌لیست',
                    onPressed: () => showAddToPlaylistSheet(context, item),
                    icon: const Icon(Icons.queue_music_rounded),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: IconButton.filledTonal(
                    onPressed: _toggleFavorite,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Icon(
                        _favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        key: ValueKey(_favorite),
                      ),
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: isDesktopWindow
                    ? const [StretchMode.zoomBackground]
                    : const [
                        StretchMode.zoomBackground,
                        StretchMode.blurBackground,
                      ],
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The backdrop remains independent from the catalog's
                    // portrait Hero, but gets its own tag for cover preview.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showCover(
                        item,
                        requestedImageUrl: backdropUrl,
                        heroTag: 'detail-backdrop-${widget.heroTag}',
                      ),
                      child: Hero(
                        tag: 'detail-backdrop-${widget.heroTag}',
                        createRectTween: smoothHeroRectTween,
                        child: _AnimatedDetailBackdrop(
                          key: ValueKey(widget.heroTag),
                          child: ContentArt(
                            content: item,
                            imageUrl: backdropUrl,
                            orientation: ArtworkOrientation.landscape,
                            borderRadius: 0,
                            showTitle: false,
                            lockToImageUrl: true,
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 0,
                      right: 0,
                      left: 0,
                      height: 150,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xB3000000), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
              sliver: SliverList.list(
                children: [
                  if (snapshot.hasError) _InlineError(onRetry: _retry),
                  _DetailSummaryCard(
                    item: item,
                    heroTag: widget.heroTag,
                    portraitImageUrl: posterUrl,
                    loading: loading,
                    hasPlayable: hasPlayable,
                    onPlay: (content, episode, startAt) =>
                        _play(content, episode, startAt: startAt),
                    onCoverTap: () => _showCover(
                      item,
                      requestedImageUrl: posterUrl,
                      heroTag: widget.heroTag.startsWith('featured-')
                          ? 'detail-poster-${widget.heroTag}'
                          : widget.heroTag,
                    ),
                    pickerBuilder: (_) => EpisodePickerScreen(
                      content: item,
                      deferInitialContent: !isDesktopWindow,
                      onPlay: (episode, startAt) =>
                          _play(item, episode, startAt: startAt),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DetailSectionTabs(
                    selected: _detailSection,
                    onSelected: _selectDetailSection,
                    hideComments: false,
                  ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: _swipeDetailSection,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(_detailSectionDirection * .055, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previousChildren, ?currentChild],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_detailSection),
                        child: _AboutSection(
                          item: item,
                          api: widget.api,
                          comments: _comments,
                          section: _detailSection,
                          onRelated: _openRelated,
                          onPerson: _openActor,
                          onDownloadSeason: (season) =>
                              _downloadSeason(item, season),
                          onDownloadQuality: (season, quality) =>
                              _downloadSeasonByQuality(item, season, quality),
                          onDownloadSelection: (season, episodes) =>
                              _downloadSelection(item, season, episodes),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AnimatedDetailBackdrop extends StatelessWidget {
  const _AnimatedDetailBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (routeAnimation == null) return child;
    return ClipRect(
      child: AnimatedBuilder(
        animation: routeAnimation,
        child: child,
        builder: (context, child) {
          final progress = routeAnimation.status == AnimationStatus.reverse
              ? Curves.easeInOutCubic.transform(routeAnimation.value)
              : Curves.easeOutCubic.transform(routeAnimation.value);
          return Opacity(
            opacity: progress.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 30 * (1 - progress)),
              child: Transform.scale(
                alignment: Alignment.bottomCenter,
                scale: .97 + (.03 * progress),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

String _fmtWatchPosition(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Shows the «بریم ادامه‌شو ببینیم؟» confirmation popup for [last] (title +
/// exact minute) and, on confirmation, plays it from that position.
/// Shared by the detail-page button and the home «ادامه تماشا» shelf.
Future<void> askAndResumeLastWatch(BuildContext context, LastWatch last) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.history_rounded),
      title: Text(last.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Text(
        last.episodeName.isNotEmpty
            ? '${episodeDisplayName(last.episodeName)}\nدقیقه ${_fmtWatchPosition(last.position)}'
                  ' از ${_fmtWatchPosition(last.duration)} مانده.\nبریم ادامه‌شو ببینیم؟'
            : 'دقیقه ${_fmtWatchPosition(last.position)}'
                  ' از ${_fmtWatchPosition(last.duration)}.\nبریم ادامه‌شو ببینیم؟',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('بریم ادامه‌شو ببینیم'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  await Navigator.of(context).push(
    slideUpRoute(
      PlayerScreen(
        content: MovieContent(
          id: last.contentId,
          title: last.title,
          subtitle: last.episodeName,
          description: '',
          year: 0,
          rating: 0,
          kind: ContentKind.movie,
          colors: const [],
          genres: const [],
        ),
        episode: MovieEpisode(
          id: last.episodeId.isNotEmpty ? last.episodeId : last.contentId,
          name: last.episodeName.isNotEmpty ? last.episodeName : last.title,
          fileUrl: last.fileUrl,
        ),
        initialPosition: last.position,
        progressEpisodeId: last.episodeId.isNotEmpty ? last.episodeId : null,
      ),
      durationMs: 520,
    ),
  );
}

class _ResumeTarget {
  const _ResumeTarget({
    required this.position,
    required this.duration,
    required this.episode,
  });
  final Duration position;
  final Duration duration;
  final MovieEpisode episode;
}

/// Same-title «ادامه تماشا» button shown under the play button. It NEVER leaves this title: when this
/// section's last exit belongs here its exact point is used, otherwise the
/// most-recently watched resumable episode of this title. A confirmation
/// popup (title + minute) precedes playback. Hidden when this title has no
/// resumable progress.
class _ContinueWatchButton extends StatefulWidget {
  const _ContinueWatchButton({required this.item, required this.onPlay});

  final MovieContent item;
  final Future<void> Function(
    MovieContent content,
    MovieEpisode episode,
    Duration startAt,
  )
  onPlay;

  @override
  State<_ContinueWatchButton> createState() => _ContinueWatchButtonState();
}

class _ContinueWatchButtonState extends State<_ContinueWatchButton> {
  final _progress = WatchProgressStore();
  _ResumeTarget? _target;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _ContinueWatchButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final catalog = EpisodeCatalog.from(widget.item);
    // 1) Exact exit point when this section's last watch is this title.
    try {
      final last = await const LastWatchStore().load();
      if (last != null && last.contentId == widget.item.id) {
        if (!mounted || generation != _generation) return;
        setState(
          () => _target = _ResumeTarget(
            position: last.position,
            duration: last.duration,
            episode: MovieEpisode(
              id: last.episodeId.isNotEmpty ? last.episodeId : widget.item.id,
              name: last.episodeName.isNotEmpty
                  ? last.episodeName
                  : widget.item.title,
              fileUrl: last.fileUrl,
            ),
          ),
        );
        return;
      }
    } catch (_) {}
    // 2) Most-recently watched resumable episode of this title.
    String? preferred;
    try {
      preferred = (await SharedPreferences.getInstance()).getString(
        'preferred_stream_quality',
      );
    } catch (_) {}
    SavedWatchProgress? best;
    EpisodeGroup? bestGroup;
    for (final group in catalog.episodes) {
      late final SavedWatchProgress? saved;
      try {
        saved = await _progress.load(
          contentId: widget.item.id,
          episodeId: group.id,
        );
      } catch (_) {
        continue;
      }
      if (saved == null || !saved.isResumable) continue;
      if (best == null || saved.updatedAtMs >= best.updatedAtMs) {
        best = saved;
        bestGroup = group;
      }
    }
    if (!mounted || generation != _generation) return;
    if (best == null || bestGroup == null) {
      setState(() => _target = null);
      return;
    }
    setState(
      () => _target = _ResumeTarget(
        position: best!.position,
        duration: best.duration,
        episode: bestGroup!.variantFor(preferred).episode,
      ),
    );
  }

  Future<void> _askAndResume() async {
    final target = _target;
    if (target == null || _busy) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.history_rounded),
        title: Text(
          widget.item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: Text(
          '${episodeDisplayName(target.episode.name)}\nدقیقه ${_fmtWatchPosition(target.position)}'
          ' از ${_fmtWatchPosition(target.duration)} مانده.\nبریم ادامه‌شو ببینیم؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('بریم ادامه‌شو ببینیم'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onPlay(widget.item, target.episode, target.position);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) return const SizedBox.shrink();
    // Full width like the «شروع تماشا» button above it.
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: _busy ? null : _askAndResume,
        icon: const Icon(Icons.play_circle_fill_rounded),
        label: Text(
          'ادامه تماشا · ${_fmtWatchPosition(target.position)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Material(
      color: MovieColors.coral.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        leading: const Icon(Icons.error_outline_rounded),
        title: const Text('جزئیات کامل دریافت نشد'),
        trailing: TextButton(
          onPressed: onRetry,
          child: const Text('تلاش دوباره'),
        ),
      ),
    ),
  );
}

class _DetailSummaryCard extends StatelessWidget {
  const _DetailSummaryCard({
    required this.item,
    required this.heroTag,
    required this.portraitImageUrl,
    required this.loading,
    required this.hasPlayable,
    required this.onCoverTap,
    required this.pickerBuilder,
    required this.onPlay,
  });

  final MovieContent item;
  final String heroTag;
  final String? portraitImageUrl;
  final bool loading;
  final bool hasPlayable;
  final VoidCallback onCoverTap;
  final WidgetBuilder pickerBuilder;

  /// Direct playback for the same-title «ادامه تماشا» button.
  final Future<void> Function(
    MovieContent content,
    MovieEpisode episode,
    Duration startAt,
  )
  onPlay;

  @override
  Widget build(BuildContext context) =>
      isLargeScreenDevice && MediaQuery.sizeOf(context).width >= 800
      ? _desktopCard(context)
      : _mobileCard(context);

  Widget _desktopCard(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: MovieColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white10),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 124, height: 176, child: _portraitArt()),
          const SizedBox(width: 20),
          Expanded(
            child: SizedBox(
              height: 176,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TitleLanguage.title(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MovieColors.muted),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _metadata(includeRuntime: false),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.runtime.isNotEmpty
                        ? 'مدت زمان: ${item.runtime}'
                        : 'برای انتخاب فصل، قسمت و کیفیت آماده است',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MovieColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 210,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _animatedWatchButton(context, desktop: true),
                const SizedBox(height: 8),
                _ContinueWatchButton(item: item, onPlay: onPlay),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _animatedWatchButton(BuildContext context, {required bool desktop}) {
    final enabled = !loading && hasPlayable;
    return OpenContainer<void>(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: Duration(milliseconds: desktop ? 500 : 300),
      closedColor: Colors.transparent,
      middleColor: MovieColors.surfaceHigh,
      openColor: MovieColors.background,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(desktop ? 18 : 40),
      ),
      openShape: const RoundedRectangleBorder(),
      tappable: false,
      openBuilder: (context, _) => pickerBuilder(context),
      closedBuilder: (context, openContainer) => SizedBox(
        width: double.infinity,
        height: desktop ? 176 : null,
        child: FilledButton(
          onPressed: enabled ? openContainer : null,
          style: FilledButton.styleFrom(
            minimumSize: desktop ? const Size(210, 176) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(desktop ? 18 : 40),
            ),
          ),
          child: desktop
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(
                        color: Colors.black12,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 40),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      loading ? 'در حال دریافت…' : 'شروع تماشا',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!loading) ...[
                      const SizedBox(height: 5),
                      const Text(
                        'انتخاب فصل و قسمت',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded),
                    const SizedBox(width: 8),
                    Text(loading ? 'در حال دریافت لینک پخش…' : 'شروع تماشا'),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _mobileCard(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: MovieColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white10),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, height: 156, child: _portraitArt()),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TitleLanguage.title(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MovieColors.muted),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 7, runSpacing: 7, children: _metadata()),
                const SizedBox(height: 12),
                _animatedWatchButton(context, desktop: false),
                const SizedBox(height: 8),
                _ContinueWatchButton(item: item, onPlay: onPlay),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _metadata({bool includeRuntime = true}) => [
    if (item.rating > 0)
      _MetaPill(
        icon: Icons.star,
        label: 'IMDb ${item.ratingLabel}',
        color: const Color(0xFFFFC857),
      ),
    _MetaPill(icon: Icons.calendar_month_rounded, label: '${item.year}'),
    _MetaPill(icon: Icons.movie_filter_rounded, label: item.kindLabel),
    if (includeRuntime && item.runtime.isNotEmpty)
      _MetaPill(icon: Icons.schedule_rounded, label: item.runtime),
  ];

  Widget _portraitArt() {
    final art = ContentArt(
      content: item,
      imageUrl: portraitImageUrl,
      borderRadius: 16,
      showTitle: false,
      // اسلات ثابت جزئیات: همان پوستر بماند و به بک‌دراپ سوییچ نکند.
      lockToImageUrl: true,
    );
    // Featured cards use the landscape artwork, so they must not morph into
    // this portrait slot. Every regular portrait card shares this Hero,
    // including on desktop where detail opens as a modal popup.
    final coverHeroTag = heroTag.startsWith('featured-')
        ? 'detail-poster-$heroTag'
        : heroTag;
    return Semantics(
      button: true,
      label: 'نمایش کاور ${item.title}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Pressable(
          onTap: onCoverTap,
          child: Hero(
            tag: coverHeroTag,
            transitionOnUserGestures: true,
            createRectTween: smoothHeroRectTween,
            flightShuttleBuilder: portraitHeroFlightShuttle,
            child: art,
          ),
        ),
      ),
    );
  }
}

class _DetailSectionTabs extends StatelessWidget {
  const _DetailSectionTabs({
    required this.selected,
    required this.onSelected,
    this.hideComments = false,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final bool hideComments;

  static const _items = [
    (Icons.info_outline_rounded, 'درباره', 'درباره'),
    (Icons.video_library_outlined, 'قسمت‌ها و دانلود', 'قسمت‌ها'),
    // (Icons.movie_filter_outlined, 'عناوین مشابه', 'مشابه'),
    (Icons.forum_outlined, 'نظرات', 'نظرات'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = hideComments ? _items.sublist(0, 2) : _items;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return SizedBox(
          height: compact ? 62 : 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MovieColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                for (var index = 0; index < items.length; index++)
                  Expanded(
                    child: InkWell(
                      onTap: () => onSelected(index),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected == index
                              ? MovieColors.orange.withValues(alpha: .16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border(
                            bottom: BorderSide(
                              color: selected == index
                                  ? MovieColors.orange
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: compact
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    items[index].$1,
                                    size: 19,
                                    color: selected == index
                                        ? MovieColors.orange
                                        : MovieColors.muted,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    items[index].$3,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: selected == index
                                          ? MovieColors.orange
                                          : MovieColors.muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    items[index].$1,
                                    size: 19,
                                    color: selected == index
                                        ? MovieColors.orange
                                        : MovieColors.muted,
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      items[index].$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected == index
                                            ? MovieColors.orange
                                            : MovieColors.muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: MovieColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color ?? MovieColors.muted),
        const SizedBox(width: 6),
        Text(label),
      ],
    ),
  );
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.item,
    required this.api,
    required this.comments,
    required this.section,
    required this.onRelated,
    required this.onPerson,
    required this.onDownloadSeason,
    required this.onDownloadQuality,
    required this.onDownloadSelection,
  });
  final MovieContent item;
  final ContentApi api;
  final Future<List<MovieComment>> comments;
  final int section;
  final ValueChanged<MovieContent> onRelated;
  final ValueChanged<MoviePerson> onPerson;
  final ValueChanged<MovieSeason> onDownloadSeason;
  final void Function(MovieSeason season, String quality) onDownloadQuality;
  final void Function(MovieSeason season, List<MovieEpisode> episodes)
  onDownloadSelection;

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// باز کردن آرشیو درون‌برنامه‌ای یک ژانر از روی چیپ ژانر.
  Future<void> _openNormalGenre(BuildContext context, String name) async {
    final normalApi = api is MovieApi ? api as MovieApi : null;
    if (normalApi == null) return;
    CatalogGroup? group;
    try {
      final groups = await normalApi.genres();
      group = matchCatalogGroupByName(groups, name);
    } catch (_) {
      group = null;
    }
    if (!context.mounted) return;
    if (group == null) {
      // ژانر در فهرست سرور نیست؛ با جست‌وجوی متنی همان نام را نشان بده تا
      // چیپ هیچ‌وقت به بن‌بست نرسد.
      await Navigator.of(context).push(
        slideUpRoute(
          _GenreSearchResultsPage(
            api: normalApi,
            title: name,
            onOpen: onRelated,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      slideUpRoute(
        _NormalGenreResultsPage(
          api: normalApi,
          group: group,
          onOpen: onRelated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (section == 0) ...[
        Text('اطلاعات و داستان', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(
          item.description.isEmpty
              ? 'خلاصه‌ای ثبت نشده است.'
              : item.description,
          style: const TextStyle(color: MovieColors.muted, height: 1.9),
        ),
        if (item.isDubbed || (item.trailerUrl?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.isDubbed)
                const Chip(
                  avatar: Icon(Icons.record_voice_over_rounded, size: 16),
                  label: Text('دوبله فارسی'),
                ),
              if (item.trailerUrl?.isNotEmpty ?? false)
                ActionChip(
                  avatar: const Icon(
                    Icons.play_circle_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('پیش‌نمایش'),
                  onPressed: () => _launch(item.trailerUrl!),
                ),
            ],
          ),
        ],
      ],
      if (section == 0 && item.alternateTitles.isNotEmpty) ...[
        const SizedBox(height: 18),
        _InfoRow(
          icon: Icons.translate_rounded,
          title: 'نام اصلی',
          value: item.alternateTitles.join('، '),
        ),
      ],
      if (section == 0 && (item.countries.isNotEmpty || item.year > 0)) ...[
        const SizedBox(height: 18),
        _InfoRow(
          icon: Icons.public_rounded,
          title: 'محصول',
          value: [
            if (item.countries.isNotEmpty) item.countries.join('، '),
            if (item.year > 0) '${item.year}',
          ].join(' • '),
        ),
      ],
      if (section == 0 &&
          (item.imdbId != null || item.directors.isNotEmpty)) ...[
        const SizedBox(height: 22),
        DecoratedBox(
          decoration: BoxDecoration(
            color: MovieColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (item.directors.isNotEmpty)
                  _InfoRow(
                    icon: Icons.movie_creation_outlined,
                    title: 'کارگردان',
                    value: item.directors
                        .map((person) => person.name)
                        .join('، '),
                  ),
                if (item.imdbId != null) ...[
                  if (item.directors.isNotEmpty) const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _launch('https://www.imdb.com/title/${item.imdbId}/'),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(
                        item.rating > 0
                            ? 'مشاهده در IMDb · ${item.ratingLabel}'
                            : 'مشاهده در IMDb',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      if (section == 0 && item.genres.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text('ژانرها', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final genre in item.genres)
              ActionChip(
                label: Text(genre),
                onPressed: () => _openNormalGenre(context, genre),
              ),
          ],
        ),
      ],
      if (section == 0 && item.cast.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('بازیگران', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 142,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: item.cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _PersonCard(
              person: item.cast[index],
              onTap: () => onPerson(item.cast[index]),
            ),
          ),
        ),
      ],
      if (section == 1 &&
          item.seasons.any((season) => season.episodes.isNotEmpty)) ...[
        Text(
          item.seasons.length == 1 && item.seasons.first.id == 'movie'
              ? 'دانلود همه کیفیت‌ها'
              : 'دانلود فصل‌ها بر اساس کیفیت',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          'دانلود با دانلودر داخلی یا خارجی؛ روش دانلود را خودت انتخاب کن.',
          style: const TextStyle(color: MovieColors.muted),
        ),
        const SizedBox(height: 10),
        _NormalDownloadButtons(
          item: item,
          onDownloadSeason: onDownloadSeason,
          onDownloadSelection: onDownloadSelection,
        ),
      ],
      // Section 2 (similar content) temporarily hidden per request
      /*
      if (section == 2 && item.related.isNotEmpty) ...[
        Text(
          'ممکن است برای شما جذاب باشد',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: item.related.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final related = item.related[index];
              final tag = 'related-${item.id}-${related.id}';
              return SizedBox(
                width: 150,
                child: InkWell(
                  onTap: () => onRelated(related),
                  borderRadius: BorderRadius.circular(18),
                  child: Hero(
                    tag: tag,
                    transitionOnUserGestures: true,
                    createRectTween: smoothHeroRectTween,
                    flightShuttleBuilder: portraitHeroFlightShuttle,
                    child: ContentArt(
                      content: related,
                      borderRadius: 18,
                      showTitle: true,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
      if (section == 2 && item.related.isEmpty)
        const _EmptyDetailSection(
          icon: Icons.movie_filter_outlined,
          message: 'عنوان مشابهی برای این محتوا ثبت نشده است.',
        ),
      */
      if (section == 1 &&
          !item.seasons.any((season) => season.episodes.isNotEmpty))
        const _EmptyDetailSection(
          icon: Icons.video_library_outlined,
          message: 'قسمت یا فایل پخشی برای این عنوان ثبت نشده است.',
        ),
      if (section == 2) ...[
        Text('نظرات کاربران', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        TextField(
          enabled: false,
          maxLines: 2,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.lock_outline_rounded),
            hintText: 'ثبت نظر فعلاً غیرفعال است',
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<MovieComment>>(
          future: comments,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Text(
                'دریافت نظرات انجام نشد.',
                style: TextStyle(color: MovieColors.muted),
              );
            }
            final rows = snapshot.data ?? const <MovieComment>[];
            if (rows.isEmpty) {
              return const Text(
                'هنوز نظری برای این عنوان ثبت نشده است.',
                style: TextStyle(color: MovieColors.muted),
              );
            }
            return Column(
              children: [
                for (final comment in rows.take(30))
                  _CommentCard(comment: comment),
              ],
            );
          },
        ),
      ],
    ],
  );
}

/// تطبیق نام ژانر کارت جزئیات با فهرست دسته‌های سرور (دقیق، بعد شامل).
/// top-level تا واحدتست‌پذیر باشد.
CatalogGroup? matchCatalogGroupByName(List<CatalogGroup> groups, String name) {
  final needle = _normalizeFa(name);
  if (needle.isEmpty) return null;
  for (final group in groups) {
    if (_normalizeFa(group.name) == needle) return group;
  }
  for (final group in groups) {
    final candidate = _normalizeFa(group.name);
    if (candidate.contains(needle) || needle.contains(candidate)) {
      return group;
    }
  }
  return null;
}

/// یکدست‌سازی رسم‌الخط فارسی برای مقایسه نام‌ها (ي/ک عربی، نیم‌فاصله).
String _normalizeFa(String value) => value
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('‌', '')
    .replaceAll(RegExp(r'\s+'), '')
    .toLowerCase();

/// نتایج متنی یک ژانر (وقتی نام ژانر در فهرست دسته‌های سرور نیست).
/// با همان جست‌وجوی سرور کار می‌کند تا چیپ هیچ‌وقت خالی نماند.
class _GenreSearchResultsPage extends StatefulWidget {
  const _GenreSearchResultsPage({
    required this.api,
    required this.title,
    required this.onOpen,
  });
  final MovieApi api;
  final String title;
  final ValueChanged<MovieContent> onOpen;
  @override
  State<_GenreSearchResultsPage> createState() =>
      _GenreSearchResultsPageState();
}

class _GenreSearchResultsPageState extends State<_GenreSearchResultsPage> {
  final _items = <MovieContent>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _fillIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || !_more) return;
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.maxScrollExtent <= position.viewportDimension + 50) {
        _loadMore();
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.search(widget.title, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        final seen = {for (final item in _items) item.id};
        for (final item in next) {
          if (seen.add(item.id)) _items.add(item);
        }
        _more = next.isNotEmpty;
      });
      _fillIfNeeded();
    } on MovieApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: _items.isEmpty && _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty && _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadMore,
                  child: const Text('تلاش دوباره'),
                ),
              ],
            ),
          )
        : CustomScrollView(
            controller: _scroll,
            slivers: [
              if (_items.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('عنوانی در این بخش ثبت نشده است.')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: .57,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final tag = 'genre-${widget.title}-${_items[i].id}';
                      return Pressable(
                        onTap: () => widget.onOpen(_items[i]),
                        child: Hero(
                          tag: tag,
                          transitionOnUserGestures: true,
                          child: ContentArt(content: _items[i]),
                        ),
                      );
                    },
                  ),
                ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
  );
}

/// نتایج یک ژانر انیمهٔ معمولی (از چیپ‌های ژانر صفحه جزئیات) با صفحه‌بندی.
class _NormalGenreResultsPage extends StatefulWidget {
  const _NormalGenreResultsPage({
    required this.api,
    required this.group,
    required this.onOpen,
  });

  final MovieApi api;
  final CatalogGroup group;
  final ValueChanged<MovieContent> onOpen;

  @override
  State<_NormalGenreResultsPage> createState() =>
      _NormalGenreResultsPageState();
}

class _NormalGenreResultsPageState extends State<_NormalGenreResultsPage> {
  final _items = <MovieContent>[];
  final _scroll = ScrollController();
  final _seenIds = <String>{};
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _more = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final rows = await widget.api.catalogByGroup(
        group: widget.group,
        country: false,
        page: next,
      );
      if (!mounted) return;
      setState(() {
        _page = next;
        _loading = false;
        _loadingMore = false;
        if (rows.isEmpty) {
          _more = false;
        } else {
          for (final row in rows) {
            if (_seenIds.add(row.id)) _items.add(row);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = 'دریافت این ژانر انجام نشد.';
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _seenIds.clear();
      _error = null;
      _loading = true;
      _more = true;
      _page = 0;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.group.name)),
    body: Builder(
      builder: (context) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null && _items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: const TextStyle(color: MovieColors.muted)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('تلاش دوباره'),
                ),
              ],
            ),
          );
        }
        if (_items.isEmpty) {
          return const Center(
            child: Text(
              'محتوایی در این ژانر پیدا نشد.',
              style: TextStyle(color: MovieColors.muted),
            ),
          );
        }
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            childAspectRatio: .68,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _items.length + (_more ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final content = _items[index];
            final tag = 'genre-${widget.group.id}-${content.id}';
            return InkWell(
              onTap: () => widget.onOpen(content),
              borderRadius: BorderRadius.circular(18),
              child: Hero(
                tag: tag,
                transitionOnUserGestures: true,
                createRectTween: smoothHeroRectTween,
                flightShuttleBuilder: portraitHeroFlightShuttle,
                child: ContentArt(
                  content: content,
                  borderRadius: 18,
                  showTitle: true,
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

/// دکمه‌های دانلود محتوای عادی: فیلم «همه کیفیت‌ها» + تک‌تک کیفیت‌ها،
/// سریال هر فصل «همه قسمت‌های یک کیفیت» جداگانه (بدون قاطی کردن کیفیت‌ها).
class _NormalDownloadButtons extends StatelessWidget {
  const _NormalDownloadButtons({
    required this.item,
    required this.onDownloadSeason,
    required this.onDownloadSelection,
  });

  final MovieContent item;
  final ValueChanged<MovieSeason> onDownloadSeason;
  final void Function(MovieSeason season, List<MovieEpisode> episodes)
  onDownloadSelection;

  @override
  Widget build(BuildContext context) {
    final plan = normalDownloadPlan(item);
    final hasPlan =
        plan.movieAll != null ||
        plan.batches.any((batch) => batch.episodes.isNotEmpty);
    if (!hasPlan) {
      // حالت مرزی (مثلاً فقط تیزر): رفتار قبلی حفظ می‌شود.
      return Column(
        children: [
          for (final season in item.seasons)
            if (season.episodes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => onDownloadSeason(season),
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: Text(
                      season.id == 'movie'
                          ? 'دانلود همه ${season.episodes.length} کیفیت'
                          : '${season.name} · دانلود همه ${season.episodes.length} قسمت',
                    ),
                  ),
                ),
              ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.movieAll != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => onDownloadSelection(
                  plan.movieAll!.season,
                  plan.movieAll!.episodes,
                ),
                icon: const Icon(Icons.download_for_offline_rounded),
                label: Text(plan.movieAll!.label),
              ),
            ),
          ),
        for (final batch in plan.batches)
          if (batch.episodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: plan.isMovie
                    ? OutlinedButton.icon(
                        onPressed: () =>
                            onDownloadSelection(batch.season, batch.episodes),
                        icon: const Icon(Icons.high_quality_rounded),
                        label: Text(batch.label),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: () =>
                            onDownloadSelection(batch.season, batch.episodes),
                        icon: const Icon(Icons.download_for_offline_rounded),
                        label: Text(
                          batch.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ),
      ],
    );
  }
}

class _EmptyDetailSection extends StatelessWidget {
  const _EmptyDetailSection({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: MovieColors.muted),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: MovieColors.muted)),
        ],
      ),
    ),
  );
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment});
  final MovieComment comment;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NetworkAvatar(
            radius: 20,
            imageUrl: comment.userImageUrl,
            iconSize: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.userName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(comment.text, style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: MovieColors.orange),
      const SizedBox(width: 10),
      Text('$title: ', style: const TextStyle(fontWeight: FontWeight.w800)),
      Expanded(
        child: Text(value, style: const TextStyle(color: MovieColors.muted)),
      ),
    ],
  );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, this.onTap});
  final MoviePerson person;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      width: 94,
      child: Column(
        children: [
          _NetworkAvatar(radius: 42, imageUrl: person.imageUrl, iconSize: 38),
          const SizedBox(height: 8),
          Text(
            person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          if (person.role.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                person.role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: MovieColors.muted),
              ),
            ),
        ],
      ),
    ),
  );
}

class _NetworkAvatar extends StatelessWidget {
  const _NetworkAvatar({
    required this.radius,
    required this.imageUrl,
    required this.iconSize,
  });

  final double radius;
  final String? imageUrl;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: MovieColors.surfaceHigh,
      child: Center(child: Icon(Icons.person_rounded, size: iconSize)),
    );
    final source = imageUrl?.trim();
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: source == null || source.isEmpty
            ? fallback
            : Image(
                image: imageProviderForUrl(
                  source.replaceFirst('http://', 'https://'),
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.content,
    required this.episode,
    this.initialPosition = Duration.zero,
    this.progressEpisodeId,
  });
  final MovieContent content;
  final MovieEpisode episode;
  final Duration initialPosition;

  /// Canonical progress identity override (download metadata's logical
  /// group id). When set, progress is read/written under this id so offline
  /// playback shares the streaming record instead of forking a raw id.
  final String? progressEpisodeId;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  late final Player _player;
  late final VideoController _video;
  late final EpisodeCatalog _episodeCatalog;
  final PictureInPictureController _pip = PictureInPictureController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _progressStore = WatchProgressStore();
  Timer? _hideTimer;
  Timer? _unlockButtonTimer;
  Timer? _saveTimer;
  Timer? _cursorTimer;
  Timer? _feedbackTimer;
  Timer? _brightnessHoldTimer;
  Timer? _playbackErrorTimer;
  Timer? _windowResizeTimer;
  late MovieEpisode _episode;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _controlsVisible = true;
  bool _touchLocked = false;
  bool _unlockButtonVisible = false;
  bool _fitCover = false;
  bool _isFullScreen = false;
  bool _cursorHidden = false;
  bool _nativeSubtitleRendering = false;
  bool _pipSupported = false;
  bool _isInPip = false;
  double _pipAspectRatio = 16 / 9;
  double _volume = 100;
  double _lastVolume = 100;
  double _rate = 1;
  double _screenBrightness = .5;
  double _systemMediaVolume = 1;
  bool _brightnessGesture = false;
  bool _brightnessRestored = false;
  PlayerFeedbackKind? _feedback;
  double? _feedbackValue;
  bool _nextEpisodeVisible = false;
  bool _changingEpisode = false;
  bool _switchingQuality = false;
  bool _windowResizing = false;
  bool _exitingPlayer = false;
  bool _allowPlayerPop = false;
  // Single generation for the whole playback lifecycle: every async media
  // operation captures it and aborts before touching the player/relay once
  // a newer operation started or the screen was disposed. Together with
  // [_transitioning] this serializes open/quality/episode/next as one
  // transaction so two overlapping switches cannot interleave open→seek→play.
  int _mediaGeneration = 0;
  bool _transitioning = false;
  bool _playerTornDown = false;

  bool _isCurrentMediaOp(int generation) =>
      mounted && !_playerTornDown && generation == _mediaGeneration;
  Offset? _doubleTapPosition;
  List<String> _subtitles = const [];
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  SubtitlePreferences _subtitle = const SubtitlePreferences();
  String? _error;
  Duration _positionAtLastError = Duration.zero;

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    _episodeCatalog = EpisodeCatalog.from(widget.content);
    if (isDesktopWindow) windowManager.addListener(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pip.addListener(_handlePipModeChanged);
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'MBNMovie',
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
        libass: true,
        libassAndroidFont: 'assets/fonts/Vazirmatn-Regular.ttf',
        libassAndroidFontName: 'Vazirmatn',
      ),
    );
    _video = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _listen();
    _restoreSubtitlePrefs();
    _restorePlayerPrefs();
    unawaited(_restoreAndroidDisplayPrefs());
    _armSaveTimer();
    // Own the future: an unobserved open failure must surface as player
    // error state, never as an unhandled async error.
    unawaited(
      _startInitialPlayback().catchError((Object error) {
        if (!mounted || _playerTornDown) return;
        setState(() => _error = '$error');
      }),
    );
    _armHideTimer();
    _pokeCursor();
    unawaited(_initializePictureInPicture());
  }

  Future<void> _startInitialPlayback() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _playerTornDown) return;
    if (!(prefs.getBool('player_gestures_introduced') ?? false)) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('راهنمای پخش'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: Icon(Icons.touch_app_rounded),
                title: Text('یک لمس: نمایش کنترل‌ها'),
              ),
              ListTile(
                leading: Icon(Icons.double_arrow_rounded),
                title: Text('دو لمس روی تصویر: جابه‌جایی ۱۰ ثانیه‌ای'),
              ),
              ListTile(
                leading: Icon(Icons.tune_rounded),
                title: Text('سرعت و زیرنویس: بالای پلیر'),
              ),
            ],
          ),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('شروع تماشا'),
            ),
          ],
        ),
      );
      if (!mounted || _playerTornDown) return;
      await prefs.setBool('player_gestures_introduced', true);
    }
    if (mounted && !_playerTornDown) await _openMedia();
  }

  Future<void> _initializePictureInPicture() async {
    final supported = await _pip.initialize();
    if (!mounted) return;
    setState(() {
      _pipSupported = supported;
      _isInPip = _pip.value;
    });
    await _configurePictureInPicture();
  }

  void _handlePipModeChanged() {
    if (!mounted) return;
    final isInPip = _pip.value;
    setState(() {
      _isInPip = isInPip;
      _controlsVisible = !isInPip;
    });
    if (isInPip) {
      _hideTimer?.cancel();
      _unlockButtonTimer?.cancel();
    } else {
      _armHideTimer();
    }
  }

  Future<void> _configurePictureInPicture() => _pip.configure(
    autoEnter: _playing,
    aspectRatio: _pipAspectRatio,
    title: widget.content.title,
    subtitle: _episode.name,
  );

  Future<void> _enterPictureInPicture() async {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
    final entered = await _pip.enter(
      aspectRatio: _pipAspectRatio,
      title: widget.content.title,
      subtitle: _episode.name,
    );
    if (!mounted || entered) return;
    setState(() => _controlsVisible = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('نمایش تصویر در تصویر در دسترس نیست.')),
    );
    _armHideTimer();
  }

  /// Best-effort clear of mpv's own proxy slot.
  Future<void> _clearMpvProxy() async {
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('http-proxy', '');
      }
    } catch (_) {}
  }

  /// Picks the mpv URL for [fileUrl]. Never throws.
  Future<String> _resolvePlaybackUrl(String fileUrl, {int? generation}) async {
    await _clearMpvProxy();
    return fileUrl;
  }

  /// Opens [fileUrl] in mpv.
  /// Throws [StateError] when this operation was superseded or the player
  /// was torn down, so stale continuations never touch native resources.
  Future<void> _openRoutedMedia(
    String fileUrl, {
    required bool play,
    required int generation,
  }) async {
    void requireCurrent() {
      if (!_isCurrentMediaOp(generation)) {
        throw StateError('superseded playback operation');
      }
    }

    const headers = {'User-Agent': 'MBNMovie/1.0 Android'};
    final routed = await _resolvePlaybackUrl(fileUrl, generation: generation);
    requireCurrent();
    try {
      await _player.open(Media(routed, httpHeaders: headers), play: play);
    } catch (_) {
      requireCurrent();
      rethrow;
    }
    requireCurrent();
    // `Player.open` only issues load commands; transport/decoder failures
    // arrive later over `stream.error`. Wait for a readiness signal scoped
    // to this operation so route fallback/rollback sees real load failures.
    await _awaitLoadReady(generation: generation);
  }

  Future<void> _openMedia() async {
    final generation = ++_mediaGeneration;
    final resumeAt = widget.initialPosition;
    // Starting playback immediately can make mpv reset an early seek to
    // zero while the remote file is still being prepared.
    await _openRoutedMedia(
      _episode.fileUrl,
      play: false,
      generation: generation,
    );
    if (!_isCurrentMediaOp(generation)) return;
    if (resumeAt > Duration.zero) {
      await _waitUntilSeekable(generation: generation);
      if (!_isCurrentMediaOp(generation)) return;
      await _player.seek(_safeResumePosition(resumeAt));
      if (!_isCurrentMediaOp(generation)) return;
    }
    await _player.play();
    if (!_isCurrentMediaOp(generation)) return;

    if (resumeAt > Duration.zero) {
      // Some Android decoders recreate the media clock on the first play.
      // Verify once after startup and re-apply the requested position if it
      // was reset, instead of silently starting the episode from zero.
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!_isCurrentMediaOp(generation)) return;
      final expected = _safeResumePosition(resumeAt);
      if (_player.state.position < expected - const Duration(seconds: 4)) {
        await _player.seek(expected);
      }
    }
  }

  /// Waits until this generation's media is actually loadable: duration (or
  /// a progressing position) wins, a player error loses, otherwise a bounded
  /// timeout lets HLS-without-duration continue (today's behavior).
  Future<void> _awaitLoadReady({required int generation}) async {
    if (_player.state.duration > Duration.zero) return;
    StreamSubscription<Duration>? durationSub;
    StreamSubscription<String>? errorSub;
    Timer? timer;
    final completer = Completer<void>();
    void finish([Object? error]) {
      timer?.cancel();
      unawaited(durationSub?.cancel());
      unawaited(errorSub?.cancel());
      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete();
      }
    }

    durationSub = _player.stream.duration.listen((value) {
      if (value > Duration.zero) finish();
    });
    errorSub = _player.stream.error.listen((value) {
      finish(StateError('پخش شروع نشد: $value'));
    });
    // Some HLS servers expose a seekable timeline without a duration.
    timer = Timer(const Duration(seconds: 15), () => finish());
    try {
      await completer.future;
    } finally {
      timer.cancel();
      await durationSub.cancel();
      await errorSub.cancel();
    }
    if (!_isCurrentMediaOp(generation)) {
      throw StateError('superseded playback operation');
    }
  }

  Future<void> _waitUntilSeekable({int? generation}) async {
    if (_player.state.duration > Duration.zero) return;
    try {
      await _player.stream.duration
          .firstWhere((value) => value > Duration.zero)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      // Some HLS servers expose a seekable timeline without a duration.
      // mpv can still accept the saved absolute position in that case.
      // A quality switch intentionally keeps today's lenient behavior here;
      // real load failures are already caught by [_awaitLoadReady].
    }
    if (generation != null && !_isCurrentMediaOp(generation)) {
      throw StateError('superseded playback operation');
    }
  }

  Duration _safeResumePosition(Duration requested) {
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return requested;
    if (duration <= const Duration(seconds: 2)) return Duration.zero;
    final latest = duration - const Duration(seconds: 2);
    return requested > latest ? latest : requested;
  }

  void _armSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Suspend ordinary progress writes during a media transition so the
      // new timeline/duration cannot be attributed to the previous episode.
      if (_transitioning) return;
      _persistProgress();
    });
  }

  String get _progressEpisodeId =>
      widget.progressEpisodeId ??
      _episodeCatalog.groupFor(_episode)?.id ??
      _episode.id;

  Future<void> _persistProgress({
    bool markWatched = false,
    Duration? at,
    Duration? duration,
    String? episodeId,
  }) {
    final position = at ?? _position;
    if (position <= Duration.zero && !markWatched) return Future.value();
    return _progressStore.save(
      contentId: widget.content.id,
      episodeId: episodeId ?? _progressEpisodeId,
      position: position,
      duration: duration ?? _duration,
      markWatched: markWatched,
    );
  }

  void _listen() {
    void watch<T>(Stream<T> stream, void Function(T) update) {
      _subscriptions.add(
        stream.listen((value) {
          if (!mounted) return;
          setState(() => update(value));
        }),
      );
    }

    // High-frequency streams (position/buffer tick many times per second):
    // values are stored silently; only the isolated _SeekBar below listens
    // to them, so control buttons never rebuild on playback ticks.
    void watchQuiet<T>(Stream<T> stream, void Function(T) update) {
      _subscriptions.add(
        stream.listen((value) {
          update(value);
        }),
      );
    }

    watchQuiet(_player.stream.position, (value) {
      _position = value;
      if ((_playbackErrorTimer != null || _error != null) &&
          playbackContinuedAfterError(
            position: value,
            positionAtError: _positionAtLastError,
          )) {
        _clearPlaybackError();
      }
      final visible = shouldOfferNextEpisode(
        value,
        _duration,
        hasNext: _nextEpisode != null,
      );
      if (visible != _nextEpisodeVisible && mounted) {
        setState(() => _nextEpisodeVisible = visible);
      }
    });
    watchQuiet(_player.stream.duration, (value) => _duration = value);
    watchQuiet(_player.stream.completed, (value) {
      if (value && !_switchingQuality) unawaited(_completeCurrentEpisode());
    });
    _subscriptions.add(
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        if (value && _controlsVisible && !_touchLocked && !_isInPip) {
          _armHideTimer();
        } else if (!value) {
          _hideTimer?.cancel();
        }
        unawaited(_configurePictureInPicture());
      }),
    );
    watch(_player.stream.buffering, (value) => _buffering = value);
    watch(_player.stream.volume, (value) => _volume = value);
    watch(_player.stream.rate, (value) => _rate = value);
    watch(_player.stream.tracks, (value) => _tracks = value);
    watch(_player.stream.track, (value) {
      _track = value;
      _nativeSubtitleRendering = _requiresNativeSubtitle(value.subtitle);
      unawaited(_setNativeSubtitleVisibility(_nativeSubtitleRendering));
    });
    _subscriptions.add(_player.stream.error.listen(_handlePlaybackError));
    watch(_player.stream.subtitle, (value) => _subtitles = value);
    watchQuiet(_player.stream.videoParams, (value) {
      final aspect =
          value.aspect ??
          ((value.dw != null && value.dh != null && value.dh! > 0)
              ? value.dw! / value.dh!
              : null);
      if (aspect == null || !aspect.isFinite || aspect <= 0) return;
      if ((aspect - _pipAspectRatio).abs() < .01) return;
      _pipAspectRatio = aspect;
      unawaited(_configurePictureInPicture());
    });
  }

  void _handlePlaybackError(String value) {
    _playbackErrorTimer?.cancel();
    _positionAtLastError = _player.state.position;
    _playbackErrorTimer = Timer(playerErrorGracePeriod, () {
      _playbackErrorTimer = null;
      if (!mounted ||
          playbackContinuedAfterError(
            position: _player.state.position,
            positionAtError: _positionAtLastError,
          )) {
        return;
      }
      setState(() => _error = value);
    });
  }

  void _clearPlaybackError() {
    _playbackErrorTimer?.cancel();
    _playbackErrorTimer = null;
    if (_error != null && mounted) setState(() => _error = null);
  }

  @override
  void onWindowResize() {
    if (!isDesktopWindow || !mounted) return;
    _windowResizeTimer?.cancel();
    if (!_windowResizing) setState(() => _windowResizing = true);
    _windowResizeTimer = Timer(windowsResizeSettleDelay, _finishWindowResize);
  }

  @override
  void onWindowResized() => _finishWindowResize();

  void _finishWindowResize() {
    _windowResizeTimer?.cancel();
    _windowResizeTimer = null;
    if (mounted && _windowResizing) setState(() => _windowResizing = false);
  }

  Future<void> _restoreSubtitlePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _subtitle = SubtitlePreferences.fromStore(prefs));
    await _applySubtitleTiming(_subtitle);
  }

  bool _requiresNativeSubtitle(SubtitleTrack track) {
    final descriptor = [
      track.codec,
      track.title,
      track.id,
    ].whereType<String>().join(' ').toLowerCase();
    return const [
      'ass',
      'ssa',
      'pgs',
      'hdmv',
      'dvd_subtitle',
      'dvb_subtitle',
      'xsub',
      '.sup',
      '.idx',
    ].any(descriptor.contains);
  }

  Future<void> _setNativeSubtitleVisibility(bool visible) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-visibility', visible ? 'yes' : 'no');
    }
  }

  Future<void> _applySubtitleTiming(SubtitlePreferences prefs) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-delay', prefs.delay.toStringAsFixed(2));
      await platform.setProperty(
        'sub-speed',
        prefs.timingScale.toStringAsFixed(3),
      );
    }
  }

  /// Restores the last used speed + volume so every video starts with
  /// the user's previous settings.
  Future<void> _restorePlayerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rate = prefs.getDouble('player_rate') ?? 1.0;
    final volume = prefs.getDouble('player_volume') ?? 100.0;
    final fitCover = prefs.getBool('player_fit_cover') ?? false;
    if (!mounted) return;
    setState(() {
      _rate = rate.clamp(.5, 4.0);
      _volume = volume.clamp(0, 100);
      _fitCover = fitCover;
      if (_volume > 0) _lastVolume = _volume;
    });
    unawaited(_player.setRate(_rate));
    unawaited(_player.setVolume(_volume));
  }

  Future<void> _restoreAndroidDisplayPrefs() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('player_screen_brightness');
    final values = await Future.wait([
      DeviceBridge.mediaVolume(),
      DeviceBridge.screenBrightness(),
    ]);
    if (!mounted) return;
    _systemMediaVolume = values[0];
    _screenBrightness = saved ?? values[1];
    if (saved != null) await DeviceBridge.setScreenBrightness(saved);
  }

  EpisodeGroup? get _currentEpisodeGroup => _episodeCatalog.groupFor(_episode);

  EpisodeVariant? get _currentVariant {
    final group = _currentEpisodeGroup;
    if (group == null) return null;
    for (final variant in group.variants) {
      if (variant.episode.id == _episode.id &&
          variant.episode.fileUrl == _episode.fileUrl) {
        return variant;
      }
    }
    return null;
  }

  Future<void> _showQualityPicker() async {
    final group = _currentEpisodeGroup;
    if (group == null || group.variants.length < 2 || _switchingQuality) return;
    _hideTimer?.cancel();
    final selected = await showModalBottomSheet<EpisodeVariant>(
      context: context,
      constraints: BoxConstraints(maxWidth: panelWidth(context, large: 760)),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: MovieColors.surface,
      builder: (context) => FractionallySizedBox(
        heightFactor: .78,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.high_quality_rounded),
              title: Text(
                'کیفیت پخش',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('زمان فعلی ویدیو هنگام تغییر حفظ می‌شود.'),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: group.variants.length,
                itemBuilder: (context, index) {
                  final variant = group.variants[index];
                  final selected = variant.episode.fileUrl == _episode.fileUrl;
                  return InkWell(
                    key: Key('player-quality-${variant.quality}'),
                    onTap: () => Navigator.pop(context, variant),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: selected ? MovieColors.orange : null,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            qualityDisplayLabel(variant.quality),
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: selected ? MovieColors.orange : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _playerVariantMeta(variant),
                              style: const TextStyle(
                                color: MovieColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null && selected.episode.fileUrl != _episode.fileUrl) {
      await _switchQuality(selected);
    }
    _armHideTimer();
  }

  Future<void> _switchQuality(EpisodeVariant target) async {
    // One serialized media transaction: quality, episode and auto-next
    // share [_transitioning] and a generation so overlapping taps cannot
    // interleave open→seek→play or misattribute progress.
    if (_transitioning ||
        _switchingQuality ||
        target.episode.fileUrl == _episode.fileUrl) {
      return;
    }
    final generation = ++_mediaGeneration;
    final previous = _episode;
    final previousId = _episodeCatalog.groupFor(_episode)?.id ?? _episode.id;
    final position = _player.state.position;
    final durationAtSwitch = _duration;
    final wasPlaying = _player.state.playing;
    _transitioning = true;
    _switchingQuality = true;
    await _persistProgress(
      at: position,
      duration: durationAtSwitch,
      episodeId: previousId,
    );
    if (!_isCurrentMediaOp(generation)) {
      _switchingQuality = false;
      _transitioning = false;
      return;
    }
    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
      });
    }
    try {
      await _openRoutedMedia(
        target.episode.fileUrl,
        play: false,
        generation: generation,
      );
      if (!_isCurrentMediaOp(generation)) return;
      await _waitUntilSeekable(generation: generation);
      await _player.seek(_safeResumePosition(position));
      if (!_isCurrentMediaOp(generation)) return;
      if (wasPlaying) await _player.play();
      if (!_isCurrentMediaOp(generation)) return;
      // Commit media identity and timeline together for the current op only.
      _episode = target.episode;
      _position = position;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preferred_stream_quality', target.quality);
      await MbnSync.instance.pushPreferences();
      await _configurePictureInPicture();
      if (!mounted) return;
      if (_isCurrentMediaOp(generation)) {
        setState(() {
          _buffering = false;
          _subtitles = const [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              'کیفیت پخش روی ${qualityDisplayLabel(target.quality)} قرار گرفت.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted || !_isCurrentMediaOp(generation)) return;
      try {
        await _openRoutedMedia(
          previous.fileUrl,
          play: false,
          generation: generation,
        );
        await _player.seek(_safeResumePosition(position));
        if (wasPlaying) await _player.play();
      } catch (_) {}
      if (!mounted) return;
      if (_isCurrentMediaOp(generation)) {
        setState(() => _buffering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تغییر کیفیت انجام نشد؛ پخش قبلی بازیابی شد.'),
          ),
        );
      }
    } finally {
      if (_isCurrentMediaOp(generation) || _switchingQuality) {
        _switchingQuality = false;
        _transitioning = false;
      }
    }
  }

  Future<SavedWatchProgress?> _bestProgressForGroup(EpisodeGroup group) async {
    // Canonical record is authoritative once it exists: a stale legacy
    // per-variant position must never override a newer rewind/replay.
    // The watched marker is preserved independently across both.
    final canonical = await _progressStore.load(
      contentId: widget.content.id,
      episodeId: group.id,
    );
    var legacyWatched = false;
    SavedWatchProgress? legacyBest;
    for (final variant in group.variants) {
      if (variant.episode.id == group.id) continue;
      final legacy = await _progressStore.load(
        contentId: widget.content.id,
        episodeId: variant.episode.id,
      );
      if (legacy == null) continue;
      if (legacy.watched) legacyWatched = true;
      if (legacyBest == null ||
          (legacy.watched && !legacyBest.watched) ||
          legacy.positionMs > legacyBest.positionMs) {
        legacyBest = legacy;
      }
    }
    if (canonical != null) {
      if (legacyWatched && !canonical.watched) {
        return SavedWatchProgress(
          positionMs: canonical.positionMs,
          durationMs: canonical.durationMs,
          watched: true,
        );
      }
      return canonical;
    }
    return legacyBest;
  }

  Future<void> _showEpisodePicker() async {
    if (_transitioning ||
        _changingEpisode ||
        _switchingQuality ||
        _episodeCatalog.seasons.isEmpty) {
      return;
    }
    _hideTimer?.cancel();
    final savedEntries = <String, SavedWatchProgress>{};
    await Future.wait(
      _episodeCatalog.episodes.map((group) async {
        final saved = await _bestProgressForGroup(group);
        if (saved != null) savedEntries[group.id] = saved;
      }),
    );
    if (!mounted) return;

    final currentGroup = _currentEpisodeGroup;
    var seasonIndex = _episodeCatalog.seasons.indexWhere(
      (season) => season.episodes.any((group) => group.id == currentGroup?.id),
    );
    if (seasonIndex < 0) seasonIndex = 0;
    final selected =
        await showModalBottomSheet<
          ({EpisodeGroup group, EpisodeVariant variant})
        >(
          context: context,
          constraints: BoxConstraints(
            maxWidth: panelWidth(context, large: 1040),
          ),
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          backgroundColor: MovieColors.surface,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, updateSheet) {
              final season = _episodeCatalog.seasons[seasonIndex];
              final currentQuality = _currentVariant?.quality;
              final choices = widget.content.kind == ContentKind.movie
                  ? [
                      for (final group in season.episodes)
                        for (final variant in group.variants)
                          (group: group, variant: variant),
                    ]
                  : [
                      for (final group in season.episodes)
                        (
                          group: group,
                          variant: group.variantFor(
                            group.variants.any(
                                  (item) => item.quality == currentQuality,
                                )
                                ? currentQuality
                                : recommendedEpisodeQuality(
                                    group.variants.map((item) => item.quality),
                                  ),
                          ),
                        ),
                    ];
              return SafeArea(
                child: FractionallySizedBox(
                  heightFactor: .88,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.video_library_rounded,
                            color: MovieColors.orange,
                          ),
                          title: Text(
                            widget.content.kind == ContentKind.movie
                                ? 'انتخاب نسخهٔ فیلم'
                                : 'انتخاب قسمت',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'پخش در همین پلیر ادامه پیدا می‌کند.',
                          ),
                        ),
                        if (_episodeCatalog.seasons.length > 1) ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final (index, item)
                                    in _episodeCatalog.seasons.indexed) ...[
                                  ChoiceChip(
                                    key: Key('player-season-${item.id}'),
                                    label: Text(item.name),
                                    selected: index == seasonIndex,
                                    onSelected: (_) =>
                                        updateSheet(() => seasonIndex = index),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = playerEpisodePickerColumns(
                                constraints.maxWidth,
                              );
                              return GridView.builder(
                                key: ValueKey('player-episodes-${season.id}'),
                                itemCount: choices.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: columns >= 4
                                          ? 1.85
                                          : 1.55,
                                    ),
                                itemBuilder: (context, index) {
                                  final choice = choices[index];
                                  final group = choice.group;
                                  final variant = choice.variant;
                                  final saved = savedEntries[group.id];
                                  final isCurrent =
                                      widget.content.kind == ContentKind.movie
                                      ? variant.episode.fileUrl ==
                                            _episode.fileUrl
                                      : group.id == currentGroup?.id;
                                  final status = saved?.watched == true
                                      ? 'تماشا کردی'
                                      : saved?.almostWatched == true
                                      ? 'تقریباً تماشا کردی'
                                      : saved?.isResumable == true
                                      ? 'ادامه از ${_formatPlayerDuration(saved!.position)}'
                                      : 'پخش از ابتدا';
                                  final isTrailerVariant =
                                      group.isTrailer ||
                                      isTrailerLabel(variant.episode.name);
                                  final episodeDisplayName =
                                      widget.content.kind == ContentKind.movie
                                      ? (isTrailerVariant
                                            ? (variant.episode.name
                                                      .trim()
                                                      .isEmpty
                                                  ? group.name
                                                  : variant.episode.name)
                                            : qualityDisplayLabel(
                                                variant.quality,
                                              ))
                                      : group.name;
                                  return Material(
                                    color: isCurrent
                                        ? MovieColors.orange.withValues(
                                            alpha: .18,
                                          )
                                        : Colors.white.withValues(alpha: .045),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: isCurrent
                                            ? MovieColors.orange
                                            : Colors.white12,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: Key('player-episode-${group.id}'),
                                      onTap: () => Navigator.pop(sheetContext, (
                                        group: group,
                                        variant: variant,
                                      )),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    episodeDisplayName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                                Icon(
                                                  isCurrent
                                                      ? Icons.equalizer_rounded
                                                      : Icons
                                                            .play_circle_rounded,
                                                  color: MovieColors.orange,
                                                ),
                                              ],
                                            ),
                                            const Spacer(),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        isCurrent
                                                            ? 'در حال پخش'
                                                            : status,
                                                        maxLines: 1,
                                                        style: TextStyle(
                                                          color:
                                                              isCurrent ||
                                                                  saved?.watched ==
                                                                      true
                                                              ? MovieColors
                                                                    .orange
                                                              : Colors.white70,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (!(group.isTrailer &&
                                                    isUnknownQuality(
                                                      variant.quality,
                                                    ))) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: MovieColors.orange
                                                          .withValues(
                                                            alpha: .12,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                      border: Border.all(
                                                        color: MovieColors
                                                            .orange
                                                            .withValues(
                                                              alpha: .28,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      widget.content.kind ==
                                                              ContentKind.movie
                                                          ? _playerVariantMeta(
                                                              variant,
                                                            )
                                                          : playerEpisodeQualityBadge(
                                                              variant.quality,
                                                            ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textDirection:
                                                          TextDirection.ltr,
                                                      style: const TextStyle(
                                                        color:
                                                            MovieColors.orange,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
    if (!mounted) return;
    if (selected != null) {
      if (selected.group.id == currentGroup?.id) {
        await _switchQuality(selected.variant);
      } else {
        await _switchEpisode(selected.group, selected.variant);
      }
    }
    _showControls();
  }

  Future<void> _switchEpisode(EpisodeGroup group, EpisodeVariant target) async {
    if (_transitioning ||
        _changingEpisode ||
        target.episode.fileUrl == _episode.fileUrl) {
      return;
    }
    // Acquire the single media transaction before the first await so a
    // concurrent quality/next tap cannot interleave with this switch.
    final generation = ++_mediaGeneration;
    _transitioning = true;
    _changingEpisode = true;
    final previous = _episode;
    final previousId = _episodeCatalog.groupFor(_episode)?.id ?? _episode.id;
    final previousPosition = _player.state.position;
    final previousDuration = _duration;
    final wasPlaying = _player.state.playing;
    final saved = await _bestProgressForGroup(group);
    if (!_isCurrentMediaOp(generation)) return;
    final startAt = saved?.isResumable == true
        ? saved!.position
        : Duration.zero;
    await _persistProgress(
      at: previousPosition,
      duration: previousDuration,
      episodeId: previousId,
    );
    if (!_isCurrentMediaOp(generation)) return;
    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
        _nextEpisodeVisible = false;
      });
    }
    try {
      await _openRoutedMedia(
        target.episode.fileUrl,
        play: false,
        generation: generation,
      );
      if (!_isCurrentMediaOp(generation)) return;
      if (startAt > Duration.zero) {
        await _waitUntilSeekable(generation: generation);
        await _player.seek(_safeResumePosition(startAt));
        if (!_isCurrentMediaOp(generation)) return;
      }
      await _player.play();
      if (!mounted || !_isCurrentMediaOp(generation)) return;
      _episode = target.episode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preferred_stream_quality', target.quality);
      await MbnSync.instance.pushPreferences();
      await _configurePictureInPicture();
      if (!mounted) return;
      if (_isCurrentMediaOp(generation)) {
        setState(() {
          _position = startAt;
          _duration = _player.state.duration;
          _buffering = false;
          _subtitles = const [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              group.isTrailer && isUnknownQuality(target.quality)
                  ? 'در حال پخش ${group.name}'
                  : 'در حال پخش ${group.name} با کیفیت ${qualityDisplayLabel(target.quality)}',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted || !_isCurrentMediaOp(generation)) return;
      try {
        await _openRoutedMedia(
          previous.fileUrl,
          play: false,
          generation: generation,
        );
        await _waitUntilSeekable(generation: generation);
        await _player.seek(_safeResumePosition(previousPosition));
        if (wasPlaying) await _player.play();
      } catch (_) {}
      if (!mounted) return;
      if (_isCurrentMediaOp(generation)) {
        setState(() => _buffering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('پخش قسمت انتخاب‌شده انجام نشد؛ پخش قبلی برگشت.'),
          ),
        );
      }
    } finally {
      if (_isCurrentMediaOp(generation) || _changingEpisode) {
        _changingEpisode = false;
        _transitioning = false;
      }
    }
  }

  MovieEpisode? get _nextEpisode {
    final currentGroup = _currentEpisodeGroup;
    if (currentGroup != null) {
      final allGroups = _episodeCatalog.seasons
          .expand((s) => s.episodes)
          .toList();
      final idx = allGroups.indexWhere((g) => g.id == currentGroup.id);
      if (idx >= 0 && idx + 1 < allGroups.length) {
        final nextGroup = allGroups[idx + 1];
        final preferredQuality = _currentVariant?.quality;
        return nextGroup.variantFor(preferredQuality).episode;
      }
      return null;
    }
    return nextEpisodeFor(widget.content, _episode);
  }

  Future<void> _playNextEpisode() => _finishCurrentAndPlayNext();

  Future<void> _completeCurrentEpisode() =>
      _finishCurrentAndPlayNext(completedNaturally: true);

  Future<void> _finishCurrentAndPlayNext({
    bool completedNaturally = false,
  }) async {
    if (_transitioning || _changingEpisode) return;
    final generation = ++_mediaGeneration;
    _transitioning = true;
    _changingEpisode = true;
    try {
      final next = _nextEpisode;
      final currentId = _episodeCatalog.groupFor(_episode)?.id ?? _episode.id;
      await _persistProgress(
        markWatched: true,
        at: completedNaturally && _duration > Duration.zero
            ? _duration
            : _position,
        duration: _duration,
        episodeId: currentId,
      );
      if (!mounted || !_isCurrentMediaOp(generation)) return;
      if (next == null) {
        setState(() => _nextEpisodeVisible = false);
        return;
      }
      setState(() {
        _episode = next;
        _position = Duration.zero;
        _duration = Duration.zero;
        _subtitles = const [];
        _error = null;
        _nextEpisodeVisible = false;
        _controlsVisible = false;
      });
      await _configurePictureInPicture();
      if (!mounted || !_isCurrentMediaOp(generation)) return;
      await _openRoutedMedia(next.fileUrl, play: true, generation: generation);
    } catch (error) {
      if (!mounted) return;
      if (_isCurrentMediaOp(generation)) {
        setState(() => _error = 'پخش قسمت بعدی انجام نشد: $error');
      }
    } finally {
      if (_isCurrentMediaOp(generation) || _changingEpisode) {
        _changingEpisode = false;
        _transitioning = false;
      }
    }
  }

  Future<void> _exitPlayer() async {
    if (_exitingPlayer) return;
    _exitingPlayer = true;
    try {
      await _persistProgress();
      // Remember the exact exit point for the section-scoped «ادامه تماشا»
      // button. Only genuinely
      // partial watches are kept; a finished (or barely started) title
      // clears the slot so stale continuations are never offered.
      try {
        const store = LastWatchStore();
        final atExit = LastWatch(
          contentId: widget.content.id,
          title: widget.content.title,
          episodeId: _progressEpisodeId,
          episodeName: _episode.name,
          fileUrl: _episode.fileUrl,
          positionMs: _position.inMilliseconds,
          durationMs: _duration.inMilliseconds,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (atExit.isResumable) {
          await store.save(atExit);
        } else {
          await store.clear();
        }
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _allowPlayerPop = true);
        Navigator.pop(context);
      }
    }
  }

  void _showFeedback(PlayerFeedbackKind kind, {double? value}) {
    _feedbackTimer?.cancel();
    if (mounted) {
      setState(() {
        _feedback = kind;
        _feedbackValue = value;
      });
    }
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _feedback = null;
          _feedbackValue = null;
        });
      }
    });
  }

  void _startVerticalGesture(DragStartDetails details, double width) {
    if (!playerTouchGesturesEnabled(
      isAndroid: Platform.isAndroid,
      isLocked: _touchLocked,
      controlsVisible: _controlsVisible,
    )) {
      return;
    }
    _brightnessGesture = details.localPosition.dx < width / 2;
    _brightnessRestored = false;
    _brightnessHoldTimer?.cancel();
  }

  void _updateVerticalGesture(DragUpdateDetails details, double height) {
    if (!playerTouchGesturesEnabled(
      isAndroid: Platform.isAndroid,
      isLocked: _touchLocked,
      controlsVisible: _controlsVisible,
    )) {
      return;
    }
    if (_brightnessGesture) {
      _screenBrightness = playerGestureValue(
        _screenBrightness,
        details.primaryDelta ?? 0,
        height,
      );
      unawaited(DeviceBridge.setScreenBrightness(_screenBrightness));
      _showFeedback(PlayerFeedbackKind.brightness, value: _screenBrightness);
      _brightnessHoldTimer?.cancel();
      if (_screenBrightness <= .001) {
        _brightnessHoldTimer = Timer(
          const Duration(milliseconds: 1500),
          _restoreSystemBrightness,
        );
      }
    } else {
      _systemMediaVolume = playerGestureValue(
        _systemMediaVolume,
        details.primaryDelta ?? 0,
        height,
      );
      unawaited(DeviceBridge.setMediaVolume(_systemMediaVolume));
      _showFeedback(PlayerFeedbackKind.volume, value: _systemMediaVolume);
    }
  }

  void _endVerticalGesture(DragEndDetails _) {
    _brightnessHoldTimer?.cancel();
    if (_brightnessGesture && !_brightnessRestored && Platform.isAndroid) {
      SharedPreferences.getInstance().then(
        (prefs) =>
            prefs.setDouble('player_screen_brightness', _screenBrightness),
      );
    }
  }

  void _restoreSystemBrightness() {
    if (!shouldRestoreSystemBrightness(
      _screenBrightness,
      const Duration(milliseconds: 1500),
    )) {
      return;
    }
    unawaited(DeviceBridge.setScreenBrightness(null));
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.remove('player_screen_brightness'),
      ),
    );
    _showFeedback(PlayerFeedbackKind.systemBrightness);
    _brightnessRestored = true;
    unawaited(
      DeviceBridge.screenBrightness().then(
        (value) => _screenBrightness = value,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!isDesktopWindow || _touchLocked || event is! PointerScrollEvent) {
      return;
    }
    final next = (_volume + (event.scrollDelta.dy < 0 ? 5 : -5))
        .clamp(0, 100)
        .toDouble();
    _setVolume(next);
    _showFeedback(PlayerFeedbackKind.volume, value: next / 100);
  }

  void _setVolume(double value) {
    final clamped = value.clamp(0.0, 100.0).toDouble();
    if (clamped > 0) _lastVolume = clamped;
    unawaited(_player.setVolume(clamped));
    unawaited(_savePlayerPrefsWith(volume: clamped));
  }

  void _toggleMute() {
    final next = _volume == 0 ? _lastVolume : 0.0;
    unawaited(_player.setVolume(next));
    unawaited(_savePlayerPrefsWith(volume: next));
  }

  Future<void> _savePlayerPrefsWith({double? volume, double? rate}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_rate', rate ?? _rate);
    await prefs.setDouble('player_volume', volume ?? _volume);
    await MbnSync.instance.pushPreferences();
  }

  void _toggleFit() {
    setState(() => _fitCover = !_fitCover);
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setBool('player_fit_cover', _fitCover);
      await MbnSync.instance.pushPreferences();
    });
  }

  /// Toggles window fullscreen. Chrome state is applied synchronously from
  /// local state (no await gaps), so a back-press racing a toggle can never
  /// leave the title bar hidden: dispose() resets it the same way.
  Future<void> _toggleFullscreen() async {
    if (!isDesktopWindow) return;
    final next = !_isFullScreen;
    _isFullScreen = next;
    hideWindowChrome.value = next;
    if (mounted) setState(() {});
    try {
      await windowManager.setFullScreen(next);
    } catch (_) {
      // Best effort only.
    }
    // Reconcile with the real window state; never touch globals detached.
    try {
      final actual = await windowManager.isFullScreen();
      if (!mounted) return;
      if (actual != _isFullScreen) {
        _isFullScreen = actual;
        hideWindowChrome.value = actual;
        setState(() {});
      }
    } catch (_) {
      // Best effort only.
    }
  }

  /// Hides the mouse pointer after 3s without movement (desktop). Any
  /// movement or tap brings it back.
  void _pokeCursor() {
    if (!isDesktopWindow) return;
    _cursorTimer?.cancel();
    if (_cursorHidden && mounted) setState(() => _cursorHidden = false);
    _cursorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _cursorHidden = true);
    });
  }

  @override
  void dispose() {
    // Invalidate every in-flight media operation first so late probe/relay
    // continuations abort before creating resources or touching the player.
    _mediaGeneration++;
    _playerTornDown = true;
    _transitioning = false;
    _changingEpisode = false;
    _switchingQuality = false;
    // Restore the window chrome on the NEXT frame: writing the notifier
    // synchronously here runs inside the framework's unmount lock and
    // throws ("setState() called when widget tree was locked"), which
    // also swallows the notification and leaves the bar hidden.
    if (hideWindowChrome.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        hideWindowChrome.value = false;
      });
    }
    if (isDesktopWindow && _isFullScreen) {
      _isFullScreen = false;
      unawaited(windowManager.setFullScreen(false));
    }
    _hideTimer?.cancel();
    _unlockButtonTimer?.cancel();
    _saveTimer?.cancel();
    _cursorTimer?.cancel();
    _feedbackTimer?.cancel();
    _brightnessHoldTimer?.cancel();
    _playbackErrorTimer?.cancel();
    _windowResizeTimer?.cancel();
    if (isDesktopWindow) windowManager.removeListener(this);
    if (Platform.isAndroid) unawaited(DeviceBridge.setScreenBrightness(null));
    _pip.removeListener(_handlePipModeChanged);
    unawaited(_pip.deactivate());
    _pip.dispose();
    // Stop audio instantly, but defer the heavy native teardown until the
    // pop transition is over so back-navigation stays smooth.
    unawaited(_player.pause());
    // Final safety flush. Normal back navigation already awaits this write.
    unawaited(_persistProgress());
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    final player = _player;
    unawaited(
      Future.delayed(const Duration(milliseconds: 350), () async {
        try {
          await player.dispose();
        } catch (_) {
          // Already torn down (e.g. hot restart); safe to ignore.
        }
      }),
    );
    SystemChrome.setPreferredOrientations(
      isAndroidTv
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const [],
    );
    SystemChrome.setEnabledSystemUIMode(
      isAndroidTv ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    super.dispose();
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(playerControlsAutoHideDelay, () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (_touchLocked) {
      _showUnlockButton();
      return;
    }
    setState(() => _controlsVisible = true);
    _armHideTimer();
  }

  void _lockTouch() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _brightnessHoldTimer?.cancel();
    setState(() {
      _touchLocked = true;
      _controlsVisible = false;
      _unlockButtonVisible = true;
      _feedback = null;
      _feedbackValue = null;
    });
    _armUnlockButtonTimer();
  }

  void _showUnlockButton() {
    if (!_touchLocked) return;
    if (!_unlockButtonVisible) setState(() => _unlockButtonVisible = true);
    _armUnlockButtonTimer();
  }

  void _armUnlockButtonTimer() {
    _unlockButtonTimer?.cancel();
    _unlockButtonTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _touchLocked) {
        setState(() => _unlockButtonVisible = false);
      }
    });
  }

  void _unlockTouch() {
    _unlockButtonTimer?.cancel();
    setState(() {
      _touchLocked = false;
      _unlockButtonVisible = false;
      _controlsVisible = true;
    });
    _armHideTimer();
  }

  void _toggle({bool showControls = true}) {
    _player.playOrPause();
    if (showControls) _showControls();
  }

  void _seekBy(int seconds, {bool showControls = true}) {
    _player.seek(
      playerSeekTarget(_player.state.position, _player.state.duration, seconds),
    );
    if (showControls) _showControls();
    _showFeedback(
      seconds < 0
          ? PlayerFeedbackKind.seekBack
          : PlayerFeedbackKind.seekForward,
    );
  }

  void _keyboardCommand(PlayerCommand command) {
    if (_isInPip || _touchLocked || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    switch (command) {
      case PlayerCommand.toggle:
        _toggle(showControls: false);
      case PlayerCommand.back:
        _seekBy(-10, showControls: false);
      case PlayerCommand.forward:
        _seekBy(10, showControls: false);
      case PlayerCommand.volumeUp:
        final next = (_volume + 5).clamp(0, 100).toDouble();
        _setVolume(next);
        _showFeedback(PlayerFeedbackKind.volume, value: next / 100);
      case PlayerCommand.volumeDown:
        final next = (_volume - 5).clamp(0, 100).toDouble();
        _setVolume(next);
        _showFeedback(PlayerFeedbackKind.volume, value: next / 100);
      case PlayerCommand.mute:
        final next = _volume == 0 ? _lastVolume : 0.0;
        _toggleMute();
        _showFeedback(PlayerFeedbackKind.volume, value: next / 100);
      case PlayerCommand.fullscreen:
        unawaited(_toggleFullscreen());
      case PlayerCommand.exitFullscreen:
        if (_isFullScreen) {
          unawaited(_toggleFullscreen());
        }
      case PlayerCommand.faster:
      case PlayerCommand.slower:
        final next = (_rate + (command == PlayerCommand.faster ? .1 : -.1))
            .clamp(.5, 4.0);
        unawaited(_player.setRate(next));
        unawaited(_savePlayerPrefsWith(rate: next));
      case PlayerCommand.subtitles:
        unawaited(
          _player.setSubtitleTrack(
            _track.subtitle.id == 'no'
                ? SubtitleTrack.auto()
                : SubtitleTrack.no(),
          ),
        );
      case PlayerCommand.tracks:
        unawaited(_showTrackPicker());
      case PlayerCommand.subtitleSettings:
        unawaited(_showSubtitleSettings());
      case PlayerCommand.fit:
        _toggleFit();
      case PlayerCommand.home:
        unawaited(_player.seek(Duration.zero));
      case PlayerCommand.end:
        unawaited(_player.seek(_duration));
      case PlayerCommand.help:
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('راهنمای کیبورد پلیر'),
              content: const SingleChildScrollView(
                child: Text(PlayerKeyboard.help),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('بستن'),
                ),
              ],
            ),
          ),
        );
    }
  }

  Future<void> _showTrackPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      constraints: BoxConstraints(maxWidth: panelWidth(context, large: 820)),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MovieColors.surface,
      showDragHandle: true,
      builder: (context) => DefaultTabController(
        length: 2,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height * .76).clamp(0.0, 560.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: MovieColors.orange),
                      const SizedBox(width: 10),
                      Text(
                        'صدا و زیرنویس',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MovieColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const TabBar(
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: [
                        Tab(icon: Icon(Icons.graphic_eq_rounded), text: 'صدا'),
                        Tab(
                          icon: Icon(Icons.closed_caption_rounded),
                          text: 'زیرنویس',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: TabBarView(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: _AudioTracks(
                              player: _player,
                              tracks: _tracks.audio,
                              selected: _track.audio,
                            ),
                          ),
                          AudioSourceActions(
                            onSelected: (track) async {
                              await _player.setAudioTrack(track);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Expanded(
                            child: _SubtitleTracks(
                              tracks: _tracks.subtitle,
                              selected: _track.subtitle,
                              onSelected: (track) async {
                                await _player.setSubtitleTrack(track);
                                final native = _requiresNativeSubtitle(track);
                                await _setNativeSubtitleVisibility(native);
                                if (mounted && context.mounted) {
                                  setState(
                                    () => _nativeSubtitleRendering = native,
                                  );
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: _loadSubtitleFile,
                                    icon: const Icon(Icons.folder_open_rounded),
                                    label: const Text('فایل زیرنویس'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: _loadSubtitleUrl,
                                    icon: const Icon(Icons.link_rounded),
                                    label: const Text('لینک زیرنویس'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _showControls();
  }

  List<Widget> _playerToolControls({required bool compact}) {
    final hasMultipleEpisodes =
        _episodeCatalog.episodes.where((group) => !group.isTrailer).length > 1;
    final rawQuality = _currentVariant?.quality ?? 'کیفیت';
    final quality = isUnknownQuality(rawQuality)
        ? qualityDisplayLabel(rawQuality)
        : rawQuality;
    final hideQualityButton =
        (_currentEpisodeGroup?.isTrailer ?? false) &&
        isUnknownQuality(rawQuality);
    return [
      if ((_currentEpisodeGroup?.variants.length ?? 0) > 1 &&
          !hideQualityButton) ...[
        _PlayerToolControl(
          icon: Icons.high_quality_rounded,
          label: quality,
          compact: compact,
          compactLabel: quality,
          onTap: _showQualityPicker,
        ),
        if (hasMultipleEpisodes) const SizedBox(width: 8),
      ],
      if (hasMultipleEpisodes) ...[
        _PlayerToolControl(
          icon: Icons.video_library_rounded,
          label: 'انتخاب قسمت',
          compact: compact,
          compactLabel: 'قسمت',
          onTap: _showEpisodePicker,
        ),
      ],
    ];
  }

  Future<void> _loadSubtitleFile() async {
    const subtitleFiles = XTypeGroup(
      label: 'زیرنویس',
      extensions: [
        'srt',
        'vtt',
        'ass',
        'ssa',
        'sub',
        'idx',
        'sup',
        'smi',
        'sami',
        'lrc',
        'ttml',
        'dfxp',
        'sbv',
        'mpl2',
        'jss',
        'rt',
        'pjs',
        'aqt',
      ],
      mimeTypes: [
        'application/x-subrip',
        'text/vtt',
        'text/x-ssa',
        'text/x-ass',
      ],
    );
    final file = await openFile(acceptedTypeGroups: const [subtitleFiles]);
    if (file == null) return;
    final track = SubtitleTrack.uri(
      file.path,
      title: file.name,
      language: 'fa',
    );
    await _player.setSubtitleTrack(track);
    final native = _requiresNativeSubtitle(track);
    await _setNativeSubtitleVisibility(native);
    if (mounted) setState(() => _nativeSubtitleRendering = native);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _loadSubtitleUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('افزودن لینک زیرنویس'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/subtitle.srt',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('افزودن'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لینک زیرنویس معتبر نیست.')),
        );
      }
      return;
    }
    final track = SubtitleTrack.uri(
      url,
      title: uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
          ? 'زیرنویس اینترنتی'
          : uri.pathSegments.last,
      language: 'fa',
    );
    await _player.setSubtitleTrack(track);
    final native = _requiresNativeSubtitle(track);
    await _setNativeSubtitleVisibility(native);
    if (mounted) setState(() => _nativeSubtitleRendering = native);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showSubtitleSettings() async {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
    final result = await showGeneralDialog<SubtitlePreferences>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'بستن تنظیمات زیرنویس',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween(begin: const Offset(0, -1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
      pageBuilder: (context, animation, secondary) => SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: MovieColors.surface,
            elevation: 18,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(24),
            ),
            child: SizedBox(
              width: panelWidth(context, large: 1100),
              height: (MediaQuery.sizeOf(context).height * .82).clamp(
                0.0,
                340.0,
              ),
              child: _TopSubtitleSettings(
                initial: _subtitle,
                onChanged: (value) {
                  if (mounted) setState(() => _subtitle = value);
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() => _subtitle = result);
      final prefs = await SharedPreferences.getInstance();
      await result.save(prefs);
      await _applySubtitleTiming(result);
    }
    _armHideTimer();
  }

  Future<void> _showSpeedSettings() async {
    final result = await showModalBottomSheet<(SubtitlePreferences, double)>(
      context: context,
      constraints: BoxConstraints(maxWidth: panelWidth(context, large: 760)),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MovieColors.surface,
      showDragHandle: true,
      builder: (context) =>
          _SubtitleTiming(initial: _subtitle, initialRate: _rate),
    );
    if (result != null) {
      setState(() => _subtitle = result.$1);
      await _player.setRate(result.$2);
      await _savePlayerPrefsWith(rate: result.$2);
      await _applySubtitleTiming(result.$1);
      final prefs = await SharedPreferences.getInstance();
      await result.$1.save(prefs);
    }
    _showControls();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPlayerPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        if (isAndroidTv && _controlsVisible) {
          setState(() => _controlsVisible = false);
        } else {
          unawaited(_exitPlayer());
        }
      }
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerSignal: _handlePointerSignal,
        child: PlayerKeyboard(
          isTelevision: isAndroidTv,
          controlsVisible: _controlsVisible,
          onRemoteNavigation: _showControls,
          onCommand: _keyboardCommand,
          onSeekFraction: (fraction) {
            if (ModalRoute.of(context)?.isCurrent == true) {
              final target = Duration(
                milliseconds: (_duration.inMilliseconds * fraction).round(),
              );
              unawaited(_player.seek(target));
              _showFeedback(
                target < _position
                    ? PlayerFeedbackKind.seekBack
                    : PlayerFeedbackKind.seekForward,
              );
            }
          },
          onFocus: _pokeCursor,
          child: MouseRegion(
            cursor: _cursorHidden
                ? SystemMouseCursors.none
                : SystemMouseCursors.basic,
            onHover: (_) {
              _pokeCursor();
              if (!_touchLocked && !_controlsVisible) _showControls();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _pokeCursor();
                if (_touchLocked) {
                  _showUnlockButton();
                  return;
                }
                _controlsVisible
                    ? setState(() => _controlsVisible = false)
                    : _showControls();
              },
              onVerticalDragStart: (details) => _startVerticalGesture(
                details,
                MediaQuery.sizeOf(context).width,
              ),
              onVerticalDragUpdate: (details) => _updateVerticalGesture(
                details,
                MediaQuery.sizeOf(context).height,
              ),
              onVerticalDragEnd: _endVerticalGesture,
              onDoubleTapDown: (details) =>
                  _doubleTapPosition = details.localPosition,
              onDoubleTap: _touchLocked
                  ? null
                  : () {
                      _pokeCursor();
                      if (isDesktopWindow) {
                        _toggleFullscreen();
                      } else if (_doubleTapPosition != null) {
                        final forward =
                            _doubleTapPosition!.dx >=
                            MediaQuery.sizeOf(context).width / 2;
                        _seekBy(forward ? 10 : -10, showControls: false);
                      }
                    },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: Video(
                      controller: _video,
                      fit: _fitCover ? BoxFit.cover : BoxFit.contain,
                      controls: (_) => const SizedBox.shrink(),
                      // Native subtitles are hidden; [_AnimeSubtitles] renders them
                      // in one uniform rounded box instead (no stacked backgrounds).
                      subtitleViewConfiguration:
                          const SubtitleViewConfiguration(visible: false),
                    ),
                  ),
                  if (!_windowResizing && !_nativeSubtitleRendering)
                    _AnimeSubtitles(
                      lines: _subtitles,
                      prefs: _subtitle,
                      isPictureInPicture: _isInPip,
                    ),
                  if (!_windowResizing && _buffering && !_touchLocked)
                    const Center(child: CircularProgressIndicator()),
                  if (!_windowResizing && _error != null && !_touchLocked)
                    _PlayerError(onBack: () => unawaited(_exitPlayer())),
                  if (!_windowResizing)
                    AnimatedOpacity(
                      opacity: _controlsVisible && !_touchLocked && !_isInPip
                          ? 1
                          : 0,
                      duration: const Duration(milliseconds: 240),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible || _touchLocked || _isInPip,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xCC000000),
                                Colors.transparent,
                                Color(0xD9000000),
                              ],
                              stops: [0, .46, 1],
                            ),
                          ),
                          child: SafeArea(
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 6,
                                  right: 12,
                                  left: 12,
                                  child: Row(
                                    children: [
                                      _RoundControl(
                                        icon: Icons.arrow_forward_rounded,
                                        tooltip: 'بازگشت',
                                        onTap: () => unawaited(_exitPlayer()),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.content.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              _episode.name,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _RoundControl(
                                        icon: Icons.graphic_eq_rounded,
                                        tooltip: 'صدا و زیرنویس',
                                        onTap: _showTrackPicker,
                                      ),
                                      const SizedBox(width: 8),
                                      _RoundControl(
                                        icon: Icons.closed_caption_rounded,
                                        tooltip: 'تنظیم زیرنویس',
                                        onTap: _showSubtitleSettings,
                                      ),
                                      const SizedBox(width: 8),
                                      _RoundControl(
                                        icon: Icons.speed_rounded,
                                        tooltip: 'تنظیم سرعت',
                                        onTap: _showSpeedSettings,
                                      ),
                                      const SizedBox(width: 8),
                                      _RoundControl(
                                        icon: _fitCover
                                            ? Icons.fit_screen_rounded
                                            : Icons.aspect_ratio_rounded,
                                        tooltip: 'اندازهٔ تصویر (V)',
                                        onTap: _toggleFit,
                                      ),
                                      if (isDesktopWindow) ...[
                                        const SizedBox(width: 8),
                                        _RoundControl(
                                          icon: _isFullScreen
                                              ? Icons.fullscreen_exit_rounded
                                              : Icons.fullscreen_rounded,
                                          tooltip: 'تمام‌صفحه (F)',
                                          onTap: _toggleFullscreen,
                                        ),
                                        const SizedBox(width: 8),
                                        _RoundControl(
                                          icon: Icons.keyboard_rounded,
                                          tooltip: 'راهنمای کیبورد (F1)',
                                          onTap: () => _keyboardCommand(
                                            PlayerCommand.help,
                                          ),
                                        ),
                                      ],
                                      if (!isDesktopWindow && !isAndroidTv) ...[
                                        const SizedBox(width: 8),
                                        if (_pipSupported) ...[
                                          _RoundControl(
                                            icon: Icons
                                                .picture_in_picture_alt_rounded,
                                            tooltip: 'تصویر در تصویر',
                                            onTap: _enterPictureInPicture,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        _RoundControl(
                                          icon: Icons.lock_outline_rounded,
                                          tooltip: 'قفل لمس',
                                          onTap: _lockTouch,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Center(
                                  child: Row(
                                    textDirection: TextDirection.ltr,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _HeroControl(
                                        icon: Icons.replay_10_rounded,
                                        tooltip: '۱۰ ثانیه عقب (←)',
                                        onTap: () => _seekBy(-10),
                                        size: 32,
                                      ),
                                      const SizedBox(width: 16),
                                      _HeroControl(
                                        icon: _playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        tooltip: _playing
                                            ? 'توقف (Space)'
                                            : 'پخش (Space)',
                                        onTap: _toggle,
                                        size: 52,
                                        primary: true,
                                      ),
                                      const SizedBox(width: 16),
                                      _HeroControl(
                                        icon: Icons.forward_10_rounded,
                                        tooltip: '۱۰ ثانیه جلو (→)',
                                        onTap: () => _seekBy(10),
                                        size: 32,
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  right: 18,
                                  left: 18,
                                  bottom: 10,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact =
                                          shouldCompactPlayerControls(
                                            isDesktop: isDesktopWindow,
                                            width: constraints.maxWidth,
                                          );
                                      final volumeWidth = compact
                                          ? 150.0
                                          : 210.0;
                                      return Column(
                                        children: [
                                          GestureDetector(
                                            onDoubleTap: () {},
                                            child: _SeekBar(player: _player),
                                          ),
                                          Row(
                                            textDirection: TextDirection.ltr,
                                            children: [
                                              _BareControl(
                                                onTap: _toggleMute,
                                                tooltip: 'قطع و وصل صدا',
                                                icon: Icon(
                                                  _volume == 0
                                                      ? Icons.volume_off_rounded
                                                      : Icons.volume_up_rounded,
                                                  size: 30,
                                                ),
                                              ),
                                              if (isDesktopWindow)
                                                SizedBox(
                                                  key: const Key(
                                                    'player-volume-slider',
                                                  ),
                                                  width: volumeWidth,
                                                  child: Directionality(
                                                    textDirection:
                                                        TextDirection.ltr,
                                                    child: GestureDetector(
                                                      onDoubleTap: () {},
                                                      child: Slider(
                                                        value: _volume.clamp(
                                                          0,
                                                          100,
                                                        ),
                                                        max: 100,
                                                        onChanged: _setVolume,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              Expanded(
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: FittedBox(
                                                    key: const Key(
                                                      'player-tool-controls',
                                                    ),
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Row(
                                                      textDirection:
                                                          TextDirection.ltr,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children:
                                                          _playerToolControls(
                                                            compact: compact,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!_windowResizing)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _feedback == null
                          ? const SizedBox(key: ValueKey('no-feedback'))
                          : PlayerFeedbackOverlay(
                              key: ValueKey(_feedback),
                              kind: _feedback!,
                              value: _feedbackValue,
                            ),
                    ),
                  if (!_windowResizing &&
                      _nextEpisodeVisible &&
                      !_touchLocked &&
                      !_isInPip)
                    Positioned(
                      right: 18,
                      bottom: nextEpisodeOverlayBottom(_controlsVisible),
                      child: GestureDetector(
                        onDoubleTap: () {},
                        child: FilledButton.icon(
                          key: const Key('next-episode-overlay'),
                          onPressed: _playNextEpisode,
                          icon: const Icon(Icons.skip_next_rounded),
                          label: Text('قسمت بعدی: ${_nextEpisode!.name}'),
                        ),
                      ),
                    ),
                  if (!_windowResizing && _touchLocked)
                    // Small unlock button pinned top-left. Positioned (not Align)
                    // so it always sizes to its child instead of the full screen.
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: AnimatedSlide(
                            offset: _unlockButtonVisible
                                ? Offset.zero
                                : const Offset(-.45, 0),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: AnimatedOpacity(
                              opacity: _unlockButtonVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: IgnorePointer(
                                ignoring: !_unlockButtonVisible,
                                child: _UnlockControl(onTap: _unlockTouch),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Seek bar isolated from the player page: it listens to the position
/// stream itself, so playback ticks rebuild only this small row instead
/// of the whole player (this is what made every button feel laggy).
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});
  final Player player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.player.stream.position,
    initialData: widget.player.state.position,
    builder: (context, snapshot) {
      final position = snapshot.data ?? Duration.zero;
      final duration = widget.player.state.duration;
      final buffer = widget.player.state.buffer;
      return PlayerTimeline(
        position: position,
        duration: duration,
        buffer: buffer,
        onSeek: (target) => widget.player.seek(target),
      );
    },
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) => _InstantPlayerTap(
    onTap: onTap,
    tooltip: tooltip,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Color(0xCC252A35),
    ),
    padding: const EdgeInsets.all(11),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => RotationTransition(
        turns: Tween<double>(begin: -.08, end: 0).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(icon, key: ValueKey(icon), size: 28),
    ),
  );
}

class _UnlockControl extends StatelessWidget {
  const _UnlockControl({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _InstantPlayerTap(
    onTap: onTap,
    tooltip: 'باز کردن قفل لمس',
    decoration: BoxDecoration(
      color: const Color(0xE620232B),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white24),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 5)),
      ],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_open_rounded, color: MovieColors.orange, size: 25),
        SizedBox(width: 8),
        Text(
          'باز کردن قفل',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ],
    ),
  );
}

class _HeroControl extends StatelessWidget {
  const _HeroControl({
    required this.icon,
    required this.onTap,
    required this.size,
    required this.tooltip,
    this.primary = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool primary;
  final String tooltip;
  @override
  Widget build(BuildContext context) => _InstantPlayerTap(
    onTap: onTap,
    tooltip: tooltip,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(primary ? 28 : 20),
      color: primary ? MovieColors.orange : Colors.black54,
      border: Border.all(color: Colors.white24),
    ),
    padding: EdgeInsets.all(primary ? 18 : 13),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        icon,
        key: ValueKey(icon),
        size: size,
        color: primary ? Colors.black : Colors.white,
      ),
    ),
  );
}

String _playerVariantMeta(EpisodeVariant variant) {
  final size = formatFileSize(variant.episode.fileSize);
  final values = [
    if (size.isNotEmpty) size,
    if (variant.episode.fileType.isNotEmpty)
      variant.episode.fileType.toUpperCase(),
  ];
  return values.isEmpty ? 'سرور پخش آنلاین' : values.join(' · ');
}

String _formatPlayerDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _PlayerToolControl extends StatelessWidget {
  const _PlayerToolControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.compactLabel,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;
  final String? compactLabel;
  @override
  Widget build(BuildContext context) => _InstantPlayerTap(
    onTap: onTap,
    tooltip: label,
    decoration: BoxDecoration(
      color: const Color(0xE6262931),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white24),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10)],
    ),
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 10,
      vertical: compact ? 7 : 7,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 21, color: MovieColors.orange)],
        ),
        if (!compact || compactLabel != null) ...[
          const SizedBox(height: 2),
          Text(
            compact ? compactLabel! : label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}

class _BareControl extends StatelessWidget {
  const _BareControl({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final Widget icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => _InstantPlayerTap(
    onTap: onTap,
    tooltip: tooltip,
    padding: const EdgeInsets.all(10),
    child: icon,
  );
}

/// Player actions fire on pointer-down instead of waiting for the complete tap
/// gesture. The inner no-op gesture owns the arena so the full-screen surface
/// does not hide the controls after a button press.
class _InstantPlayerTap extends StatefulWidget {
  const _InstantPlayerTap({
    required this.child,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.decoration,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Decoration? decoration;
  final String? tooltip;

  @override
  State<_InstantPlayerTap> createState() => _InstantPlayerTapState();
}

class _InstantPlayerTapState extends State<_InstantPlayerTap> {
  bool _pressed = false;
  bool _focused = false;

  void _press(PointerDownEvent event) {
    if (_pressed || event.buttons != kPrimaryButton) return;
    setState(() => _pressed = true);
    widget.onTap();
  }

  void _release(PointerEvent _) {
    if (_pressed && mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Semantics(
      button: true,
      label: widget.tooltip,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _press,
          onPointerUp: _release,
          onPointerCancel: _release,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            // Control taps must not trigger the video's double-tap gesture.
            onDoubleTap: () {},
            child: AnimatedScale(
              scale: _pressed ? .88 : 1,
              duration: Duration(milliseconds: _pressed ? 55 : 210),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _pressed ? .72 : 1,
                duration: const Duration(milliseconds: 70),
                // NOTE: no `alignment` on this Container on purpose. A
                // non-null alignment makes it expand to fill loose
                // constraints, which turned the unlock control into a
                // full-screen button. Inner Center keeps content centered.
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 46,
                    minHeight: 46,
                  ),
                  padding: widget.padding,
                  decoration: widget.decoration,
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return FocusableActionDetector(
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? MovieColors.cyan : Colors.transparent,
            width: 2,
          ),
        ),
        child: result,
      ),
    );
  }
}

String _trackLabel(String id, String? title, String? language) {
  if (id == 'auto') return 'انتخاب خودکار';
  if (id == 'no') return 'خاموش';
  final parts = [title, language]
      .whereType<String>()
      .map(
        (value) => value.replaceAll(
          RegExp(r'anime\s*on', caseSensitive: false),
          'MBNMovie',
        ),
      )
      .where((value) => value.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? 'ترک $id' : parts.join(' · ');
}

class _AudioTracks extends StatelessWidget {
  const _AudioTracks({
    required this.player,
    required this.tracks,
    required this.selected,
  });
  final Player player;
  final List<AudioTrack> tracks;
  final AudioTrack selected;
  @override
  Widget build(BuildContext context) => tracks.isEmpty
      ? const _EmptyTrackState(
          icon: Icons.volume_off_rounded,
          text: 'ترک صدایی در این فایل پیدا نشد',
        )
      : ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: tracks
              .map(
                (track) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  selected: track == selected,
                  selectedTileColor: MovieColors.orange.withValues(alpha: .12),
                  leading: Icon(
                    track == selected
                        ? Icons.check_circle_rounded
                        : Icons.graphic_eq_rounded,
                    color: track == selected
                        ? MovieColors.orange
                        : Colors.white60,
                  ),
                  title: Text(
                    _trackLabel(track.id, track.title, track.language),
                  ),
                  subtitle: track.codec == null
                      ? null
                      : Text('${track.codec} · ${track.channels ?? ''}'),
                  onTap: () async {
                    await player.setAudioTrack(track);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        );
}

class _SubtitleTracks extends StatelessWidget {
  const _SubtitleTracks({
    required this.tracks,
    required this.selected,
    required this.onSelected,
  });
  final List<SubtitleTrack> tracks;
  final SubtitleTrack selected;
  final Future<void> Function(SubtitleTrack track) onSelected;
  @override
  Widget build(BuildContext context) => tracks.isEmpty
      ? const _EmptyTrackState(
          icon: Icons.subtitles_off_rounded,
          text: 'زیرنویس داخلی در این فایل پیدا نشد',
        )
      : ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: tracks
              .map(
                (track) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  selected: track == selected,
                  selectedTileColor: MovieColors.orange.withValues(alpha: .12),
                  leading: Icon(
                    track == selected
                        ? Icons.check_circle_rounded
                        : track.id == 'no'
                        ? Icons.subtitles_off_rounded
                        : Icons.closed_caption_rounded,
                    color: track == selected
                        ? MovieColors.orange
                        : Colors.white60,
                  ),
                  title: Text(
                    _trackLabel(track.id, track.title, track.language),
                  ),
                  subtitle: track.codec == null ? null : Text(track.codec!),
                  onTap: () => onSelected(track),
                ),
              )
              .toList(),
        );
}

class _EmptyTrackState extends StatelessWidget {
  const _EmptyTrackState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: Colors.white38),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(color: Colors.white60)),
      ],
    ),
  );
}

class _SubtitleTiming extends StatefulWidget {
  const _SubtitleTiming({required this.initial, required this.initialRate});
  final SubtitlePreferences initial;
  final double initialRate;

  @override
  State<_SubtitleTiming> createState() => _SubtitleTimingState();
}

class _SubtitleTimingState extends State<_SubtitleTiming> {
  late SubtitlePreferences value = widget.initial;
  late double rate = widget.initialRate;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_alt_rounded, color: MovieColors.orange),
              const SizedBox(width: 10),
              Text('تنظیم سرعت', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'برای زیرنویس‌های جدا از تصویر؛ زیرنویس چسبیده داخل خود ویدیو قابل تغییر نیست.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _TimingCard(
            icon: Icons.speed_rounded,
            title: 'سرعت ویدیو',
            description: 'سرعت پخش تصویر و صدا.',
            valueLabel: '${rate.toStringAsFixed(2)}×',
            min: .5,
            max: 4,
            divisions: 70,
            value: rate.clamp(.5, 4),
            onChanged: (next) => setState(() => rate = next),
            onMinus: () =>
                setState(() => rate = (rate - .05).clamp(.5, 4).toDouble()),
            onPlus: () =>
                setState(() => rate = (rate + .05).clamp(.5, 4).toDouble()),
          ),
          const SizedBox(height: 12),
          _TimingCard(
            icon: Icons.swap_horiz_rounded,
            title: 'جابه‌جایی زمان زیرنویس',
            description: 'همهٔ جمله‌ها را با هم جلو یا عقب می‌برد.',
            valueLabel:
                '${value.delay >= 0 ? '+' : ''}${value.delay.toStringAsFixed(1)} ثانیه',
            min: -30,
            max: 30,
            divisions: 600,
            value: value.delay,
            onChanged: (next) =>
                setState(() => value = value.copyWith(delay: next)),
            onMinus: () => setState(
              () => value = value.copyWith(
                delay: (value.delay - .1).clamp(-30, 30).toDouble(),
              ),
            ),
            onPlus: () => setState(
              () => value = value.copyWith(
                delay: (value.delay + .1).clamp(-30, 30).toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TimingCard(
            icon: Icons.compress_rounded,
            title: 'فاصلهٔ زمانی بین زیرنویس‌ها',
            description:
                'سرعت تایم‌کدها را تغییر می‌دهد؛ برای زیرنویسی که کم‌کم از فیلم عقب می‌افتد.',
            valueLabel: '${value.timingScale.toStringAsFixed(2)}×',
            min: .5,
            max: 2,
            divisions: 150,
            value: value.timingScale,
            onChanged: (next) =>
                setState(() => value = value.copyWith(timingScale: next)),
            onMinus: () => setState(
              () => value = value.copyWith(
                timingScale: (value.timingScale - .01).clamp(.5, 2).toDouble(),
              ),
            ),
            onPlus: () => setState(
              () => value = value.copyWith(
                timingScale: (value.timingScale + .01).clamp(.5, 2).toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    rate = 1;
                    value = value.copyWith(delay: 0, timingScale: 1);
                  }),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('بازنشانی'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, (value, rate)),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('اعمال سرعت'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TimingCard extends StatelessWidget {
  const _TimingCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    required this.onMinus,
    required this.onPlus,
  });
  final IconData icon;
  final String title;
  final String description;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: MovieColors.surfaceHigh,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: MovieColors.orange),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                valueLabel,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: MovieColors.orange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          Row(
            children: [
              _StepButton(icon: Icons.remove_rounded, onTap: onMinus),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
              _StepButton(icon: Icons.add_rounded, onTap: onPlus),
            ],
          ),
        ],
      ),
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      IconButton.filledTonal(onPressed: onTap, icon: Icon(icon));
}

class _TopSubtitleSettings extends StatefulWidget {
  const _TopSubtitleSettings({required this.initial, required this.onChanged});
  final SubtitlePreferences initial;
  final ValueChanged<SubtitlePreferences> onChanged;
  @override
  State<_TopSubtitleSettings> createState() => _TopSubtitleSettingsState();
}

class _TopSubtitleSettingsState extends State<_TopSubtitleSettings> {
  late SubtitlePreferences value = widget.initial;
  void change(SubtitlePreferences next) {
    setState(() => value = next);
    widget.onChanged(next);
  }

  Widget colors(
    String title,
    List<Color> colors,
    Color selected,
    SubtitlePreferences Function(Color) update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      const SizedBox(height: 5),
      Wrap(
        spacing: 7,
        children: [
          for (final color in colors)
            InkWell(
              onTap: () => change(update(color)),
              borderRadius: BorderRadius.circular(30),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: color,
                child: selected == color
                    ? Icon(
                        Icons.check_rounded,
                        color: color.computeLuminance() > .6
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final first = <Widget>[
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value.fontFamily,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'فونت فارسی',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'Vazirmatn', child: Text('وزیرمتن')),
                DropdownMenuItem(
                  value: 'NotoSansArabic',
                  child: Text('نوتو سنس فارسی'),
                ),
                DropdownMenuItem(
                  value: 'NotoNaskhArabic',
                  child: Text('نوتو نسخ فارسی'),
                ),
                DropdownMenuItem(value: 'MarkaziText', child: Text('مرکزی')),
                DropdownMenuItem(value: 'sans-serif', child: Text('ساده')),
                DropdownMenuItem(value: 'serif', child: Text('نسخ / سریف')),
              ],
              onChanged: (font) {
                if (font != null) change(value.copyWith(fontFamily: font));
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 98,
            child: DropdownButtonFormField<double>(
              initialValue: value.size.clamp(10, 52).roundToDouble(),
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'اندازه',
                isDense: true,
              ),
              items: [
                for (var size = 10; size <= 52; size++)
                  DropdownMenuItem(
                    value: size.toDouble(),
                    child: Text('$size'),
                  ),
              ],
              onChanged: (size) {
                if (size != null) change(value.copyWith(size: size));
              },
            ),
          ),
        ],
      ),
      _SettingSlider(
        label: 'فاصله خطوط',
        value: value.lineHeight,
        min: 1,
        max: 2,
        onChanged: (v) => change(value.copyWith(lineHeight: v)),
      ),
      _SettingSlider(
        label: 'فاصله از پایین',
        value: value.bottomPadding,
        min: 0,
        max: 1000,
        onChanged: (v) => change(value.copyWith(bottomPadding: v)),
      ),
      const SizedBox(height: 12),
      colors(
        'رنگ متن',
        const [
          Colors.white,
          Color(0xFFFFE66D),
          Color(0xFFFFD600),
          Color(0xFFFFA000),
          Color(0xFFFF6D00),
          Color(0xFFFF3D00),
          Color(0xFF8FE9FF),
          Color(0xFF00E5FF),
          Color(0xFF76FF03),
          Color(0xFFFFB3C6),
          Color(0xFFFF4081),
        ],
        value.color,
        (c) => value.copyWith(color: c),
      ),
    ];
    final second = <Widget>[
      _SettingSlider(
        label: 'تیرگی پس‌زمینه',
        value: value.backgroundOpacity,
        min: 0,
        max: 1,
        onChanged: (v) => change(value.copyWith(backgroundOpacity: v)),
      ),
      _SettingSlider(
        label: 'گردی گوشه‌ها',
        value: value.cornerRadius,
        min: 0,
        max: 24,
        onChanged: (v) => change(value.copyWith(cornerRadius: v)),
      ),
      const SizedBox(height: 12),
      colors(
        'رنگ پس‌زمینه',
        const [
          Colors.black,
          Color(0xFF3A3F4B),
          Color(0xFFFF7A1A),
          Color(0xFF8D6BFF),
          Color(0xFF0E7C7B),
        ],
        value.backgroundColor,
        (c) => value.copyWith(backgroundColor: c),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: const Text('متن ضخیم'),
        value: value.bold,
        onChanged: (v) => change(value.copyWith(bold: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: const Text('سایه و حاشیه برای خوانایی'),
        value: value.shadow,
        onChanged: (v) => change(value.copyWith(shadow: v)),
      ),
    ];
    Widget pane(List<Widget> children) => Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(children: children),
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 6),
                Text(
                  'تنظیمات ظاهر زیرنویس',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => change(
                    SubtitlePreferences(
                      delay: value.delay,
                      timingScale: value.timingScale,
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('پیش‌فرض'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, value),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('ذخیره'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 600) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        pane(first),
                        const VerticalDivider(width: 1),
                        pane(second),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(children: [...first, ...second]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Retained for compatibility with older golden/widget references.
class _SubtitleSettings extends StatefulWidget {
  const _SubtitleSettings({required this.initial});
  final SubtitlePreferences initial;
  @override
  State<_SubtitleSettings> createState() => _SubtitleSettingsState();
}

class _SubtitleSettingsState extends State<_SubtitleSettings> {
  late SubtitlePreferences value = widget.initial;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    left: false,
    right: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ظاهر حرفه‌ای زیرنویس',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'پیش‌نمایش زنده و تنظیم خوانایی برای صفحه‌های کوچک',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: value.backgroundColor.withValues(
                      alpha: value.backgroundOpacity,
                    ),
                    borderRadius: BorderRadius.circular(value.cornerRadius),
                  ),
                  child: Text(
                    'این یک نمونه زیرنویس فارسی است',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: value.fontFamily,
                      fontSize: value.size,
                      height: value.lineHeight,
                      fontWeight: value.bold
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: value.color,
                      shadows: value.shadow
                          ? const [Shadow(color: Colors.black, blurRadius: 5)]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: value.fontFamily,
              decoration: const InputDecoration(labelText: 'فونت فارسی'),
              items: const [
                DropdownMenuItem(value: 'Vazirmatn', child: Text('وزیرمتن')),
                DropdownMenuItem(
                  value: 'NotoSansArabic',
                  child: Text('نوتو سنس فارسی'),
                ),
                DropdownMenuItem(
                  value: 'NotoNaskhArabic',
                  child: Text('نوتو نسخ فارسی'),
                ),
                DropdownMenuItem(value: 'MarkaziText', child: Text('مرکزی')),
                DropdownMenuItem(
                  value: 'sans-serif',
                  child: Text('سادهٔ اندروید'),
                ),
                DropdownMenuItem(
                  value: 'serif',
                  child: Text('نسخ / سریف اندروید'),
                ),
              ],
              onChanged: (font) {
                if (font != null) {
                  setState(() => value = value.copyWith(fontFamily: font));
                }
              },
            ),
            _SettingSlider(
              label: 'اندازه',
              value: value.size,
              min: 18,
              max: 52,
              onChanged: (v) => setState(() => value = value.copyWith(size: v)),
            ),
            _SettingSlider(
              label: 'فاصله خطوط',
              value: value.lineHeight,
              min: 1,
              max: 2,
              onChanged: (v) =>
                  setState(() => value = value.copyWith(lineHeight: v)),
            ),
            _SettingSlider(
              label: 'تیرگی پس‌زمینه',
              value: value.backgroundOpacity,
              min: 0,
              max: 1,
              onChanged: (v) =>
                  setState(() => value = value.copyWith(backgroundOpacity: v)),
            ),
            _SettingSlider(
              label: 'گردی گوشه‌ها',
              value: value.cornerRadius,
              min: 0,
              max: 24,
              onChanged: (v) =>
                  setState(() => value = value.copyWith(cornerRadius: v)),
            ),
            _SettingSlider(
              label: 'فاصله از پایین',
              value: value.bottomPadding,
              min: 0,
              max: 1000,
              onChanged: (v) =>
                  setState(() => value = value.copyWith(bottomPadding: v)),
            ),
            const Text('رنگ پس‌زمینه'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children:
                  [
                        Colors.black,
                        const Color(0xFF3A3F4B),
                        const Color(0xFFFF7A1A),
                        const Color(0xFF8D6BFF),
                        const Color(0xFF0E7C7B),
                      ]
                      .map(
                        (color) => InkWell(
                          onTap: () => setState(
                            () =>
                                value = value.copyWith(backgroundColor: color),
                          ),
                          borderRadius: BorderRadius.circular(30),
                          child: CircleAvatar(
                            backgroundColor: color,
                            child: value.backgroundColor == color
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 14),
            const Text('رنگ متن'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children:
                  [
                        Colors.white,
                        const Color(0xFFFFE66D),
                        const Color(0xFFFFD600),
                        const Color(0xFFFFA000),
                        const Color(0xFFFF6D00),
                        const Color(0xFFFF3D00),
                        const Color(0xFF8FE9FF),
                        const Color(0xFF00E5FF),
                        const Color(0xFF76FF03),
                        const Color(0xFFFFB3C6),
                        const Color(0xFFFF4081),
                      ]
                      .map(
                        (color) => InkWell(
                          onTap: () => setState(
                            () => value = value.copyWith(color: color),
                          ),
                          borderRadius: BorderRadius.circular(30),
                          child: CircleAvatar(
                            backgroundColor: color,
                            child: value.color == color
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.black,
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متن ضخیم'),
              value: value.bold,
              onChanged: (v) => setState(() => value = value.copyWith(bold: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('سایه و حاشیه برای خوانایی'),
              value: value.shadow,
              onChanged: (v) =>
                  setState(() => value = value.copyWith(shadow: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(
                      () => value = SubtitlePreferences(
                        delay: value.delay,
                        timingScale: value.timingScale,
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('پیش‌فرض'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, value),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('ذخیره تنظیمات'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: MovieColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: MovieColors.orange.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    child: Text(
                      value.toStringAsFixed(1),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: MovieColors.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 30,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Custom subtitle layer: all active cues inside ONE rounded box, so the
/// background stays perfectly uniform (native per-line backgrounds stack
/// into darker bands where lines meet).
class _AnimeSubtitles extends StatelessWidget {
  const _AnimeSubtitles({
    required this.lines,
    required this.prefs,
    required this.isPictureInPicture,
  });
  final List<String> lines;
  final SubtitlePreferences prefs;
  final bool isPictureInPicture;

  @override
  Widget build(BuildContext context) {
    final text = [
      for (final line in lines)
        if (line.trim().isNotEmpty) normalizePersianSubtitle(line.trim()),
    ].join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = SubtitleLayout.resolve(
            viewport: constraints.biggest,
            isPictureInPicture: isPictureInPicture,
            preferredFontSize: prefs.size,
            preferredBottomPadding: prefs.bottomPadding,
            preferredCornerRadius: prefs.cornerRadius,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPositioned(
                duration: isDesktopWindow
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: layout.horizontalInset,
                right: layout.horizontalInset,
                bottom: layout.bottomPadding,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.horizontalPadding,
                      vertical: layout.verticalPadding,
                    ),
                    decoration: BoxDecoration(
                      color: prefs.backgroundColor.withValues(
                        alpha: prefs.backgroundOpacity,
                      ),
                      borderRadius: BorderRadius.circular(layout.cornerRadius),
                    ),
                    child: Text(
                      text,
                      maxLines: isPictureInPicture ? 3 : null,
                      overflow: isPictureInPicture
                          ? TextOverflow.ellipsis
                          : null,
                      textScaler: TextScaler.noScaling,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: prefs.fontFamily,
                        fontSize: layout.fontSize,
                        height: isPictureInPicture
                            ? prefs.lineHeight.clamp(1.0, 1.35)
                            : prefs.lineHeight,
                        fontWeight: prefs.bold
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: prefs.color,
                        shadows: prefs.shadow
                            ? const [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 5,
                                  offset: Offset(2, 2),
                                ),
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 3,
                                  offset: Offset(-1, -1),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black87,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 56),
          const SizedBox(height: 12),
          const Text('این فایل فعلاً توسط سرور پخش نشد.'),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onBack, child: const Text('بازگشت')),
        ],
      ),
    ),
  );
}
