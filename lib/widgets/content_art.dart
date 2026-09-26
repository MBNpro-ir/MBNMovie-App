import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/movie_content.dart';
import 'movie_image.dart';

enum ArtworkOrientation { portrait, landscape }

/// Scores decoded image dimensions instead of trusting the legacy API's field
/// names. Some records have their poster and thumbnail values interchanged.
@visibleForTesting
double artworkAspectScore(double aspectRatio, ArtworkOrientation orientation) {
  final ideal = orientation == ArtworkOrientation.portrait ? .68 : 16 / 9;
  return -(math.log(aspectRatio / ideal)).abs();
}

class ContentArt extends StatefulWidget {
  const ContentArt({
    super.key,
    required this.content,
    this.borderRadius = 24,
    this.showTitle = true,
    this.imageUrl,
    this.orientation = ArtworkOrientation.portrait,
    this.lockToImageUrl = false,
  });

  final MovieContent content;
  final double borderRadius;
  final bool showTitle;
  final String? imageUrl;
  final ArtworkOrientation orientation;

  /// وقتی true باشد فقط همان [imageUrl] نمایش داده می‌شود و انتخاب
  /// خودکار بین پوستر/بک‌دراپ (بر اساس ابعاد دیکدشده) انجام نمی‌شود.
  /// برای اسلات‌های ثابت صفحهٔ جزئیات تا کاور بزرگ و کوچک جابه‌جا نشوند.
  final bool lockToImageUrl;

  @override
  State<ContentArt> createState() => _ContentArtState();
}

class _ArtworkProbe {
  const _ArtworkProbe(this.provider, this.aspectRatio);
  final ImageProvider provider;
  final double aspectRatio;
}

class _ContentArtState extends State<ContentArt> {
  static const _maxProbeEntries = 500;
  static final LinkedHashMap<String, Future<_ArtworkProbe?>> _probeCache =
      LinkedHashMap<String, Future<_ArtworkProbe?>>();
  static final LinkedHashMap<String, _ArtworkProbe> _probeResults =
      LinkedHashMap<String, _ArtworkProbe>();

  ImageProvider? _provider;
  String? _selectedUrl;
  int _generation = 0;
  // Drives the load fade-in. Stays true for synchronously-restored artwork
  // so detail/hero transitions never flash; set false->true (post-frame)
  // only when a newly-resolved artwork actually replaces the visible one.
  bool _artVisible = true;
  ImageConfiguration _imageConfig = ImageConfiguration.empty;
  bool _didInitDeps = false;

  List<String> get _candidates {
    final locked = widget.imageUrl?.trim() ?? '';
    if (widget.lockToImageUrl && locked.isNotEmpty) return [locked];
    return <String?>[
      widget.imageUrl,
      widget.content.imageUrl,
      widget.content.backdropUrl,
    ].whereType<String>().where((url) => url.trim().isNotEmpty).toSet().toList();
  }

  @override
  void initState() {
    super.initState();
    // Only restores synchronously-cached artwork here. Resolving requires
    // an ImageConfiguration (MediaQuery) which is not available in initState.
    _restoreResolvedArtwork();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _imageConfig = createLocalImageConfiguration(context);
    if (!_didInitDeps) {
      _didInitDeps = true;
      if (_provider == null) _resolveArtwork();
    }
  }

  List<String> _candidatesOf(ContentArt widget) {
    final locked = widget.imageUrl?.trim() ?? '';
    if (widget.lockToImageUrl && locked.isNotEmpty) return [locked];
    return <String?>[
      widget.imageUrl,
      widget.content.imageUrl,
      widget.content.backdropUrl,
    ].whereType<String>().where((url) => url.trim().isNotEmpty).toSet().toList();
  }

  @override
  void didUpdateWidget(covariant ContentArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCandidates = _candidatesOf(oldWidget);
    final candidatesChanged = !_sameStrings(_candidates, oldCandidates);
    if (oldWidget.orientation != widget.orientation ||
        oldWidget.lockToImageUrl != widget.lockToImageUrl ||
        (candidatesChanged && !_candidates.contains(_selectedUrl))) {
      _resolveArtwork();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  String _probeKey(String url) {
    final targetWidth = widget.orientation == ArtworkOrientation.portrait
        ? 512
        : 1280;
    return '$targetWidth|$url';
  }

  /// A card that was already painted has completed probes in this process.
  /// Reusing that exact provider synchronously means a detail route's very
  /// first frame contains the image, rather than a placeholder flash.
  bool _restoreResolvedArtwork() {
    _ArtworkProbe? best;
    String? bestUrl;
    var bestScore = double.negativeInfinity;
    var allKnown = true;
    for (final url in _candidates) {
      final probe = _probeResults[_probeKey(url)];
      if (probe == null) {
        allKnown = false;
        continue;
      }
      final score = artworkAspectScore(probe.aspectRatio, widget.orientation);
      if (score > bestScore) {
        best = probe;
        bestUrl = url;
        bestScore = score;
      }
      final clearlyMatches = widget.orientation == ArtworkOrientation.portrait
          ? probe.aspectRatio < 1
          : probe.aspectRatio > 1.15;
      if (clearlyMatches) break;
    }
    if (best == null || (!allKnown && bestScore < -.35)) return false;
    _provider = best.provider;
    _selectedUrl = bestUrl;
    return true;
  }

  Future<void> _resolveArtwork() async {
    final generation = ++_generation;
    final candidates = _candidates;
    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _provider = null;
          _selectedUrl = null;
        });
      }
      return;
    }

    final config = _imageConfig;
    _ArtworkProbe? best;
    String? bestUrl;
    var bestScore = double.negativeInfinity;
    for (final url in candidates) {
      final probe = await _probe(url, widget.orientation, config);
      if (!mounted || generation != _generation) return;
      if (probe == null) continue;
      final score = artworkAspectScore(probe.aspectRatio, widget.orientation);
      if (score > bestScore) {
        best = probe;
        bestUrl = url;
        bestScore = score;
      }
      final clearlyMatches = widget.orientation == ArtworkOrientation.portrait
          ? probe.aspectRatio < 1
          : probe.aspectRatio > 1.15;
      if (clearlyMatches) break;
    }

    if (!mounted || generation != _generation) return;
    // The probe decodes before this setState, so the Image below would be
    // served synchronously from cache and any frameBuilder fade would be a
    // no-op. Fading an explicit visibility flag instead guarantees the
    // butter-smooth crossfade over the placeholder on every real switch.
    final changed = bestUrl != _selectedUrl;
    setState(() {
      _provider = best?.provider;
      _selectedUrl = bestUrl;
      if (changed && best != null) _artVisible = false;
    });
    if (changed && best != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        setState(() => _artVisible = true);
      });
    }
  }

  Future<_ArtworkProbe?> _probe(
    String url,
    ArtworkOrientation orientation,
    ImageConfiguration config,
  ) {
    final targetWidth = orientation == ArtworkOrientation.portrait ? 512 : 1280;
    final cacheKey = '$targetWidth|$url';
    final cached = _probeCache.remove(cacheKey);
    if (cached != null) {
      _probeCache[cacheKey] = cached;
      return cached;
    }
    while (_probeCache.length >= _maxProbeEntries) {
      _probeCache.remove(_probeCache.keys.first);
    }
    // Transient failures (offline decode errors) resolve to null. They are
    // evicted (guarded by future identity so an older completion can never
    // remove a newer attempt) so a retry after connectivity returns can
    // actually re-probe instead of serving a process-lifetime cached null.
    late final Future<_ArtworkProbe?> future;
    future = _decodeProbe(url, targetWidth, config).then((result) {
      if (result != null) {
        while (_probeResults.length >= _maxProbeEntries) {
          _probeResults.remove(_probeResults.keys.first);
        }
        _probeResults[cacheKey] = result;
      } else if (identical(_probeCache[cacheKey], future)) {
        _probeCache.remove(cacheKey);
      }
      return result;
    });
    _probeCache[cacheKey] = future;
    return future;
  }

  Future<_ArtworkProbe?> _decodeProbe(
    String url,
    int targetWidth,
    ImageConfiguration config,
  ) {
    final completer = Completer<_ArtworkProbe?>();
    final provider = ResizeImage.resizeIfNeeded(
      targetWidth,
      null,
      imageProviderForUrl(url),
    );
    final stream = provider.resolve(config);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // NOTE: the decoded handle is intentionally NOT disposed here. The
        // provider/completer stays in the framework ImageCache and the Image
        // widget below reuses that exact cached artwork; disposing the
        // shared handle would destroy the image the card is about to paint.
        // Only dimensions + provider are retained.
        if (!completer.isCompleted) {
          completer.complete(
            _ArtworkProbe(provider, info.image.width / info.image.height),
          );
        }
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: widget.content.colors,
                ),
              ),
            ),
          ),
          if (_provider case final provider?)
            // One short opacity animation per artwork switch: the image is
            // already decoded (probe), so the fade only composites an alpha
            // over the placeholder gradient behind — no decode/layout work
            // per frame, no parent rebuilds, no lag even with many cards.
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _artVisible ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                child: Image(
                  image: provider,
                  width: double.infinity,
                  height: double.infinity,
                  alignment: Alignment.center,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  // Second safety net: if the bytes were evicted from cache
                  // and must decode again, fade that pass too.
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          child: child,
                        );
                      },
                  errorBuilder: (_, _, _) => ExcludeSemantics(
                    child: CustomPaint(
                      painter: _PosterPainter(widget.content.id.hashCode),
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _PosterPainter(widget.content.id.hashCode),
                ),
              ),
            ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xD9000000)],
                  stops: [.42, 1],
                ),
              ),
            ),
          ),
          if (widget.showTitle)
            Positioned(
              right: 14,
              left: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.content.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (widget.content.year > 1900)
                        _CardMetaBadge(
                          icon: Icons.calendar_month_rounded,
                          label: '${widget.content.year}',
                        ),
                      if (widget.content.rating > 0)
                        _CardMetaBadge(
                          icon: Icons.star_rounded,
                          label: 'IMDb ${widget.content.ratingLabel}',
                          highlighted: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CardMetaBadge extends StatelessWidget {
  const _CardMetaBadge({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFB21A);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? accent.withValues(alpha: .18)
            : Colors.black.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: highlighted ? accent : Colors.white.withValues(alpha: .22),
          width: highlighted ? 1.25 : 1,
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: accent.withValues(alpha: .20), blurRadius: 8)]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: highlighted ? accent : Colors.white70,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? const Color(0xFFFFD36A) : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterPainter extends CustomPainter {
  const _PosterPainter(this.seed);
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    for (var i = 0; i < 7; i++) {
      final paint = Paint()
        ..color = Colors.white.withValues(
          alpha: .025 + random.nextDouble() * .065,
        );
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height * .75,
      );
      final radius = size.shortestSide * (.12 + random.nextDouble() * .34);
      canvas.drawCircle(center, radius, paint);
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .36),
        width: size.width * .72,
        height: size.width * .72,
      ),
      .4,
      4.8,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _PosterPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
