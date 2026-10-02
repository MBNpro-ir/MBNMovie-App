import '../core/title_language.dart';
import '../widgets/responsive_web_layout.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/app_platform.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/episode_catalog.dart';
import '../core/theme.dart';
import '../core/watch_progress.dart';
import '../core/player_preferences.dart';
import '../models/movie_content.dart';
import '../services/external_apps.dart';
import '../widgets/ambient_background.dart';
import '../widgets/smart_cast_sheet.dart';
import '../widgets/download_choice.dart';
import '../widgets/default_preference_prompt.dart';
import '../widgets/wireless_display_sheet.dart';

/// Clean season/episode picker opened from «شروع تماشا».
///
/// Shows seasons as chips and the selected season's files as a tidy list
/// with per-episode saved positions. Tapping an episode asks whether to
/// resume or restart when a previous position exists.
class EpisodePickerScreen extends StatefulWidget {
  const EpisodePickerScreen({
    super.key,
    required this.content,
    required this.onPlay,
    this.deferInitialContent = false,
  });

  final MovieContent content;

  /// Plays [episode] from [startAt]. Completes when the player closes.
  final Future<void> Function(MovieEpisode episode, Duration startAt) onPlay;
  final bool deferInitialContent;

  @override
  State<EpisodePickerScreen> createState() => _EpisodePickerScreenState();
}

class _EpisodePickerScreenState extends State<EpisodePickerScreen> {
  final _progress = WatchProgressStore();
  final _saved = <String, SavedWatchProgress>{};
  late final EpisodeCatalog _catalog;
  int _seasonIndex = 0;
  String _selectedQuality = unknownQualityLabel;
  final _resetting = <String>{};
  Timer? _initialContentTimer;
  late bool _contentReady;

  static int _defaultSeason(List<EpisodeSeasonGroup> seasons) {
    for (var i = 0; i < seasons.length; i++) {
      if (!seasons[i].isTrailerSeason) return i;
      final hasRegular = seasons[i].episodes.any(
        (episode) => !episode.isTrailer && !isTrailerLabel(episode.name),
      );
      if (hasRegular) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _catalog = EpisodeCatalog.from(widget.content);
    if (_catalog.seasons.isEmpty) {
      // Guard the public empty-state contract: quality/season lookup below
      // indexes seasons[0] and would crash before build() shows its empty UI.
      _seasonIndex = 0;
      _selectedQuality = unknownQualityLabel;
      _contentReady = true;
      return;
    }
    _seasonIndex = _defaultSeason(_catalog.seasons);
    _selectedQuality = recommendedEpisodeQuality(
      _catalog.seasons[_seasonIndex].displayQualities,
    );
    _contentReady = !widget.deferInitialContent;
    if (_contentReady) {
      unawaited(_loadSaved());
      unawaited(_loadQualityPreference());
    } else {
      // Keep the container-transform frames light on phones. The episode grid
      // and preference I/O start as soon as the short opening animation ends.
      _initialContentTimer = Timer(const Duration(milliseconds: 310), () {
        if (!mounted) return;
        setState(() => _contentReady = true);
        unawaited(_loadSaved());
        unawaited(_loadQualityPreference());
      });
    }
  }

  @override
  void dispose() {
    _initialContentTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final entries = <String, SavedWatchProgress>{};
    for (final group in _catalog.episodes) {
      // Canonical group record is authoritative once present; legacy
      // per-variant positions only seed it on first migration and are then
      // retired so a stale 20-minute legacy value can never overwrite a
      // newer 2-minute canonical rewind.
      final canonical = await _progress.load(
        contentId: widget.content.id,
        episodeId: group.id,
      );
      SavedWatchProgress? legacyBest;
      var legacyWatched = false;
      for (final variant in group.variants) {
        if (variant.episode.id == group.id) continue;
        final legacy = await _progress.load(
          contentId: widget.content.id,
          episodeId: variant.episode.id,
        );
        if (legacy == null) continue;
        if (legacy.watched) legacyWatched = true;
        legacyBest = _newerProgress(legacyBest, legacy);
      }
      if (canonical != null) {
        var merged = canonical;
        if (legacyWatched && !canonical.watched) {
          merged = SavedWatchProgress(
            positionMs: canonical.positionMs,
            durationMs: canonical.durationMs,
            watched: true,
          );
          await _progress.save(
            contentId: widget.content.id,
            episodeId: group.id,
            position: merged.position,
            duration: merged.duration,
            markWatched: true,
          );
        }
        entries[group.id] = merged;
        // Retire legacy keys now that the canonical record rules.
        for (final variant in group.variants) {
          if (variant.episode.id == group.id) continue;
          await _progress.clear(
            contentId: widget.content.id,
            episodeId: variant.episode.id,
          );
        }
        continue;
      }
      if (legacyBest != null) {
        entries[group.id] = legacyBest;
        await _progress.save(
          contentId: widget.content.id,
          episodeId: group.id,
          position: legacyBest.position,
          duration: legacyBest.duration,
          markWatched: legacyBest.watched,
        );
        for (final variant in group.variants) {
          if (variant.episode.id == group.id) continue;
          await _progress.clear(
            contentId: widget.content.id,
            episodeId: variant.episode.id,
          );
        }
      }
    }
    if (mounted) {
      setState(() {
        _saved
          ..clear()
          ..addAll(entries);
      });
    }
  }

  SavedWatchProgress? _newerProgress(
    SavedWatchProgress? current,
    SavedWatchProgress? candidate,
  ) {
    if (candidate == null) return current;
    if (current == null || candidate.watched && !current.watched) {
      return candidate;
    }
    return candidate.positionMs > current.positionMs ? candidate : current;
  }

  Future<void> _loadQualityPreference() async {
    if (_catalog.seasons.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final quality = prefs.getString('preferred_stream_quality');
    final available = _catalog.seasons[_seasonIndex].displayQualities;
    if (!mounted || quality == null || !available.contains(quality)) {
      return;
    }
    setState(() => _selectedQuality = quality);
  }

  Future<void> _setQuality(String quality) async {
    setState(() => _selectedQuality = quality);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_stream_quality', quality);
  }

  void _selectSeason(int index) {
    final qualities = _catalog.seasons[index].displayQualities;
    setState(() {
      _seasonIndex = index;
      if (!qualities.contains(_selectedQuality)) {
        _selectedQuality = recommendedEpisodeQuality(qualities);
      }
    });
  }

  Future<void> _tapEpisode(EpisodeGroup group, EpisodeVariant variant) async {
    final saved = _saved[group.id];
    var startAt = Duration.zero;
    if (saved != null && saved.isResumable && mounted) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Text(
            'آخرین بار تا ${_fmt(saved.position)} دیده‌ای. ادامه می‌دهی یا از اول؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('از اول'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('ادامه از ${_fmt(saved.position)}'),
            ),
          ],
        ),
      );
      if (resume == null) return;
      startAt = resume ? saved.position : Duration.zero;
    }
    await widget.onPlay(variant.episode, startAt);
    await _loadSaved();
  }

  Future<void> _showPlayback(EpisodeGroup group) async {
    if (kIsWeb) {
      await _tapEpisode(group, group.variantFor(_selectedQuality));
      return;
    }
    final variant = group.variantFor(_selectedQuality);
    final allowedPlayers = <String>{
      PlaybackPreferenceStore.internalPlayer,
      ExternalVideoPlayer.vlc.name,
      if (Platform.isAndroid) ExternalVideoPlayer.mxPlayer.name,
      if (Platform.isAndroid) ExternalVideoPlayer.mxPlayerPro.name,
    };
    String? choice = await PlaybackPreferenceStore.defaultPlayer();
    var selectedManually = false;
    if (!allowedPlayers.contains(choice)) {
      if (!mounted) return;
      choice =
          await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'کجا پخش شود؟',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.play_circle_fill),
                      title: const Text('پلیر داخلی (پیشنهادی)'),
                      onTap: () => Navigator.pop(context, 'internal'),
                    ),
                    ExpansionTile(
                      leading: const Icon(Icons.open_in_new),
                      title: const Text('پلیرهای خارجی'),
                      children: [
                        for (final player in ExternalVideoPlayer.values)
                          if (Platform.isAndroid ||
                              player == ExternalVideoPlayer.vlc)
                            ListTile(
                              title: Text(ExternalApps.playerName(player)),
                              onTap: () => Navigator.pop(context, player.name),
                            ),
                      ],
                    ),
                    ListTile(
                      leading: const Icon(Icons.cast),
                      title: const Text('تلویزیون یا مانیتور بدون سیم'),
                      onTap: () async {
                        // Keep this menu underneath its child: Back pops one level.
                        final destination = await showWirelessDisplaySheet(
                          context,
                          onCast: (initialDestination) => showSmartCastSheet(
                            context,
                            content: widget.content,
                            episode: variant.episode,
                            initialDestination: initialDestination,
                          ),
                        );
                        if (destination != null && context.mounted) {
                          Navigator.pop(context, destination);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          '';
      selectedManually = choice.isNotEmpty;
    }
    if (!mounted || choice.isEmpty) return;
    if (selectedManually && allowedPlayers.contains(choice)) {
      final label = choice == PlaybackPreferenceStore.internalPlayer
          ? 'پلیر داخلی'
          : ExternalApps.playerName(ExternalVideoPlayer.values.byName(choice));
      await maybeSuggestDefaultPlayer(context, value: choice, label: label);
      if (!mounted) return;
    }
    if (choice == 'internal') {
      await _tapEpisode(group, variant);
    } else if (choice == 'wireless') {
      await _tapEpisode(group, variant);
    } else if (choice != 'cast') {
      await _playExternal(
        variant.episode,
        ExternalVideoPlayer.values.byName(choice),
      );
    }
  }

  Future<void> _playExternal(
    MovieEpisode episode,
    ExternalVideoPlayer player,
  ) async {
    final result = await ExternalApps.playVideo(
      player: player,
      url: episode.fileUrl,
      title: '${TitleLanguage.title(widget.content)} · ${episode.name}',
    );
    if (!mounted || result == ExternalLaunchResult.launched) return;
    if (result == ExternalLaunchResult.missing) {
      await _showMissingApp(
        ExternalApps.playerName(player),
        ExternalApps.playerInstallUrl(player),
      );
      return;
    }
    _showFailure('این روش پخش در دستگاه فعلی اجرا نشد.');
  }

  Future<void> _downloadEpisode(EpisodeGroup group) async {
    final variant = await _chooseDownloadVariant(group);
    if (variant == null || !mounted) return;
    await showDownloadChoice(
      context,
      content: widget.content,
      season: variant.season,
      episodes: [variant.episode],
    );
  }

  Future<EpisodeVariant?> _chooseDownloadVariant(EpisodeGroup group) async {
    if (group.variants.length == 1) return group.variants.single;
    return showModalBottomSheet<EpisodeVariant>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.download_rounded),
              title: Text('کیفیت دانلود را انتخاب کن'),
            ),
            for (final variant in group.variants)
              ListTile(
                leading: const Icon(Icons.high_quality_rounded),
                title: Text(qualityDisplayLabel(variant.quality)),
                subtitle: Text(_variantMeta(variant)),
                trailing: variant.quality == _selectedQuality
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: () => Navigator.pop(context, variant),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMissingApp(String name, String installUrl) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$name نصب نیست'),
          content: Text('برای انجام این کار باید $name روی دستگاه نصب باشد.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                ExternalApps.openOfficialDownload(installUrl);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('دانلود رسمی'),
            ),
          ],
        ),
      );

  void _showFailure(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _selectorRow({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: MovieColors.orange),
          const SizedBox(width: 7),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: children),
    ],
  );

  Future<void> _resetEpisode(EpisodeGroup group) async {
    if (!_resetting.add(group.id)) return;
    setState(() {});
    try {
      final synced = await _progress.resetEpisode(
        contentId: widget.content.id,
        episodeIds: {group.id, ...group.variants.map((v) => v.episode.id)},
        fileUrls: {for (final v in group.variants) v.episode.fileUrl},
        hentai: false,
      );
      if (!mounted) return;
      setState(() => _saved.remove(group.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'سابقهٔ این قسمت پاک شد.'
                : 'سابقهٔ این قسمت پاک شد؛ حذف از سرور با اتصال بعدی انجام می‌شود.',
          ),
        ),
      );
    } finally {
      _resetting.remove(group.id);
      if (mounted) setState(() {});
    }
  }

  Widget _episodeCard(EpisodeGroup group) {
    final variant = group.variantFor(_selectedQuality);
    final showQualityBadge =
        widget.content.kind == ContentKind.movie &&
        !isUnknownQuality(variant.quality);
    final title = group.name;
    final saved = _saved[group.id];
    final resumable = saved?.isResumable ?? false;
    final watched = saved?.watched ?? false;
    final almostWatched = saved?.almostWatched ?? false;
    final ratio = (saved != null && saved.durationMs > 0)
        ? (saved.positionMs / saved.durationMs).clamp(0.0, 1.0)
        : null;
    final statusColor = watched
        ? MovieColors.cyan
        : almostWatched
        ? const Color(0xFFFFD600)
        : MovieColors.orange;
    final statusIcon = watched
        ? Icons.check_circle_rounded
        : almostWatched
        ? Icons.timelapse_rounded
        : resumable
        ? Icons.play_circle_fill_rounded
        : Icons.radio_button_unchecked_rounded;
    final status = watched
        ? 'تماشا کردی'
        : almostWatched
        ? 'تقریباً تماشا کردی'
        : resumable
        ? 'ادامه از ${_fmt(saved!.position)}'
        : 'تماشا نشده';
    return Material(
      key: Key('episode-card-${group.id}'),
      color: watched
          ? MovieColors.cyan.withValues(alpha: .10)
          : almostWatched
          ? const Color(0xFFFFD600).withValues(alpha: .10)
          : MovieColors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _showPlayback(group),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (showQualityBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        variant.quality,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: watched || almostWatched || resumable ? .16 : .07,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(
                      alpha: watched || almostWatched || resumable ? .45 : .18,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (saved != null &&
                        (saved.positionMs > 15000 || saved.watched))
                      IconButton(
                        key: Key('reset-episode-${group.id}'),
                        tooltip: 'پاک کردن سابقهٔ این قسمت',
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        iconSize: 17,
                        color: const Color(0xFFFF5252),
                        onPressed: _resetting.contains(group.id)
                            ? null
                            : () => _resetEpisode(group),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    Icon(statusIcon, size: 20, color: statusColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              if (ratio != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _variantMeta(variant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MovieColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  // برای تیزر شمارش «N کیفیت» معنایی ندارد و مخفی می‌شود.
                  if (!group.isTrailer)
                    Text(
                      '${group.variants.length} کیفیت',
                      style: const TextStyle(
                        color: MovieColors.muted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showPlayback(group),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('پخش'),
                    ),
                  ),
                  const SizedBox(width: 7),
                  IconButton.outlined(
                    tooltip: 'دانلود با انتخاب کیفیت',
                    onPressed: () => _downloadEpisode(group),
                    color: MovieColors.cyan,
                    icon: const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasons = _catalog.seasons;
    if (seasons.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('انتخاب قسمت')),
        body: const Center(child: Text('هنوز قسمتی موجود نیست.')),
      );
    }
    final season = seasons[_seasonIndex.clamp(0, seasons.length - 1)];
    final episodes = season.episodes;
    // تیزرها معمولاً تگ کیفیت ندارند؛ به‌جای نمایش «بدون برچسب کیفیت»،
    // کل ردیف کیفیت مخفی می‌شود.
    final displayQualities = season.displayQualities;
    return Scaffold(
      appBar: AppBar(title: const Text('انتخاب قسمت')),
      body: ResponsiveContentFrame(
        enabled: kIsWeb,
        child: AmbientBackground(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  TitleLanguage.title(widget.content),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '${widget.content.year} · ${widget.content.kindLabel}',
                  style: const TextStyle(color: MovieColors.muted),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MovieColors.surface.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    if (seasons.length > 1) ...[
                      _selectorRow(
                        title: widget.content.kind == ContentKind.movie
                            ? 'دسته‌بندی'
                            : 'فصل',
                        icon: widget.content.kind == ContentKind.movie
                            ? Icons.category_rounded
                            : Icons.video_library_rounded,
                        children: [
                          for (var i = 0; i < seasons.length; i++)
                            ChoiceChip(
                              label: Text(seasons[i].name),
                              selected: i == _seasonIndex,
                              onSelected: (_) => _selectSeason(i),
                            ),
                        ],
                      ),
                      if (displayQualities.isNotEmpty)
                        const SizedBox(height: 10),
                    ],
                    if (displayQualities.isNotEmpty)
                      _selectorRow(
                        title: 'کیفیت',
                        icon: Icons.high_quality_rounded,
                        children: [
                          for (final quality in displayQualities)
                            ChoiceChip(
                              key: Key('quality-$quality'),
                              label: Text(quality),
                              selected: quality == _selectedQuality,
                              onSelected: (_) => _setQuality(quality),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: !_contentReady
                    ? const SizedBox.expand()
                    : LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: episodes.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    MediaQuery.textScalerOf(context).scale(14) >
                                        22
                                    ? 1
                                    : (constraints.maxWidth / 245)
                                          .floor()
                                          .clamp(2, 5),
                                mainAxisExtent:
                                    210 +
                                    (MediaQuery.textScalerOf(
                                              context,
                                            ).scale(14) -
                                            14) *
                                        4,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemBuilder: (_, i) {
                            return _episodeCard(episodes[i]);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _variantMeta(EpisodeVariant variant) {
  final size = formatFileSize(variant.episode.fileSize);
  final values = [
    if (size.isNotEmpty) size,
    if (variant.episode.fileType.isNotEmpty)
      variant.episode.fileType.toUpperCase(),
  ];
  return values.isEmpty ? 'پخش آنلاین' : values.join(' · ');
}
