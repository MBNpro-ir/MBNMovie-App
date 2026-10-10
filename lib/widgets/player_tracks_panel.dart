import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Two independently scrolling columns on wide screens; one tab on phones.
/// The footer is pinned, so importing a track never requires list scrolling.
class PlayerTracksPanel extends StatelessWidget {
  const PlayerTracksPanel({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.audioActions,
    required this.subtitleActions,
    required this.trackCount,
  });
  final Widget audio, subtitles, audioActions, subtitleActions;
  final int trackCount;

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    Widget list,
    Widget actions, {
    required bool heading,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (heading)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      Expanded(child: list),
      const SizedBox(height: 8),
      actions,
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final media = MediaQuery.of(context);
      final wide = bounds.maxWidth >= 640;
      final available = math.max(
        0.0,
        math.min(
          bounds.maxHeight,
          media.size.height -
              media.padding.vertical -
              media.viewInsets.bottom -
              64,
        ),
      );
      final desired = (210 + trackCount * 78.0).clamp(330.0, 550.0);
      final short = available < 350;
      final primary = Theme.of(context).colorScheme.primary;
      return DefaultTabController(
        length: 2,
        child: SizedBox(
          key: const Key('player-tracks-panel'),
          height: math.min(desired, available),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: primary, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'صدا و زیرنویس',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'بستن پنل',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                  ],
                ),
                if (!short)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'زبان دلخواه را انتخاب کن یا فایل جداگانه اضافه کن.',
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ),
                if (!wide) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1E29),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: primary.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primary.withValues(alpha: .6),
                        ),
                      ),
                      labelColor: primary,
                      unselectedLabelColor: Colors.white60,
                      tabs: const [
                        Tab(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.graphic_eq_rounded, size: 18),
                              SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'صدا',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.closed_caption_rounded, size: 18),
                              SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'زیرنویس',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: short ? 8 : 12),
                ],
                Expanded(
                  child: wide
                      ? Row(
                          key: const Key('track-columns'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _section(
                                context,
                                'صدا',
                                Icons.graphic_eq_rounded,
                                audio,
                                audioActions,
                                heading: true,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: VerticalDivider(
                                width: 1,
                                color: Colors.white12,
                              ),
                            ),
                            Expanded(
                              child: _section(
                                context,
                                'زیرنویس',
                                Icons.closed_caption_rounded,
                                subtitles,
                                subtitleActions,
                                heading: true,
                              ),
                            ),
                          ],
                        )
                      : TabBarView(
                          children: [
                            _section(
                              context,
                              'صدا',
                              Icons.graphic_eq_rounded,
                              audio,
                              audioActions,
                              heading: false,
                            ),
                            _section(
                              context,
                              'زیرنویس',
                              Icons.closed_caption_rounded,
                              subtitles,
                              subtitleActions,
                              heading: false,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
