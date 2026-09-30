import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/country_flags.dart';
import '../core/episode_catalog.dart';
import '../core/library_store.dart';
import '../core/platform_ui.dart';
import '../core/search_direction.dart';
import '../core/theme.dart';
import '../core/watch_progress.dart';
import '../models/movie_content.dart';
import '../services/accessibility_service.dart';
import '../services/mbn_sync.dart';
import '../services/mbn_auth.dart';
import '../services/movie_api.dart';
import '../widgets/ambient_background.dart';
import '../widgets/brand_mark.dart';
import '../widgets/browsable_shelf.dart';
import '../widgets/content_art.dart';
import '../widgets/pressable.dart';
import 'cast_screen.dart';
import 'detail_screen.dart';
import 'delfan_phone_link_screen.dart';
import 'download_manager_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'subscription_screen.dart';
import 'update_screen.dart';
import '../services/app_links.dart';
import '../widgets/announcement_popup.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a content item along with its source card's Hero [tag] so the
/// cover flies into the detail popup (and back on close).
typedef OpenContent = Future<void> Function(MovieContent item, String tag);

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.email,
    required this.auth,
    required this.onLogout,
    required this.api,
  });
  final String email;
  final MbnAuth auth;
  final Future<void> Function() onLogout;
  final MovieApi api;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _store = LibraryStore();
  final _homeKey = GlobalKey<_HomePageState>();
  late final PageController _pageController;
  final Map<String, MovieContent> _favorites = {};
  final List<MovieContent> _history = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _restore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(AnnouncementService.checkAndShow(context, widget.auth, app: 'movie'));
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final values = await Future.wait([_store.favorites(), _store.history()]);
    if (!mounted) return;
    setState(() {
      _favorites.addEntries(
        values[0]
            .where((item) => !MovieApi.isPromotionalContent(item))
            .map((item) => MapEntry(item.id, item)),
      );
      _history.addAll(
        values[1].where((item) => !MovieApi.isPromotionalContent(item)),
      );
    });
  }

  Future<void> _open(MovieContent item, String tag) async {
    if (MovieApi.isPromotionalContent(item)) return;
    setState(() {
      _history.removeWhere((old) => old.id == item.id);
      _history.insert(0, item);
    });
    unawaited(_store.addToHistory(item));
    unawaited(MbnSync.instance.pushHistoryThrottled());
    DetailScreen detail() => DetailScreen(
      content: item,
      api: widget.api,
      heroTag: tag,
      isFavorite: _favorites.containsKey(item.id),
      onFavoriteChanged: (selected) {
        setState(() {
          if (selected) {
            _favorites[item.id] = item;
          } else {
            _favorites.remove(item.id);
          }
        });
        unawaited(_store.saveFavorites(_favorites.values));
        unawaited(MbnSync.instance.pushFavorites());
      },
    );
    if (isDesktopWindow) {
      // Desktop: detail opens as a large modal. Outside taps must NOT
      // close it (barrierDismissible: false); the back arrow closes it.
      await showDesktopPopup<void>(context, detail());
      // Popping back to home changes no tab, so refresh its «ادامه تماشا»
      // shelf explicitly — otherwise it keeps showing the previous title.
      unawaited(_homeKey.currentState?.refreshContinueWatch());
      return;
    }
    await Navigator.push<void>(
      context,
      slideUpRoute(detail(), durationMs: 520),
    );
    // Same as above: a pop return fires no tab change.
    unawaited(_homeKey.currentState?.refreshContinueWatch());
  }

  void _select(int value) {
    Navigator.maybePop(context);
    _goToPage(value);
  }

  void _goToPage(int value) {
    if (value == _index) {
      // Re-tapping home still refreshes its «ادامه تماشا» shelf.
      if (value == 0) _homeKey.currentState?.refreshContinueWatch();
      return;
    }
    setState(() => _index = value);
    // The home «ادامه تماشا» shelf must reflect the latest player exit.
    if (value == 0) _homeKey.currentState?.refreshContinueWatch();
    if (!_pageController.hasClients) return;
    if (isDesktopWindow) {
      _pageController.jumpToPage(value);
    } else {
      _pageController.animateToPage(
        value,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _push(Widget page) {
    Navigator.maybePop(context);
    Navigator.push<void>(context, slideUpRoute(page));
  }

  void _openSearch() => _push(_SearchPage(api: widget.api, onOpen: _open));
  void _openCastSearch() =>
      _push(CastSearchScreen(api: widget.api, onOpen: _open));
  void _openActor(MoviePerson person) =>
      _push(CastTitlesScreen(person: person, api: widget.api, onOpen: _open));
  void _openHistory() => _push(
    _SavedPage(
      api: widget.api,
      title: 'بازدیدشده‌ها',
      emptyText: 'هنوز عنوانی باز نکرده‌ای',
      emptyIcon: Icons.history_rounded,
      itemsProvider: () => _history.toList(),
      onOpen: _open,
      clearTooltip: 'پاک کردن تاریخچه',
      clearTitle: 'پاک کردن تاریخچه؟',
      clearMessage: 'فهرست عنوان‌های بازدیدشده پاک می‌شود.',
      onClear: () async {
        await _store.clearHistory();
        if (mounted) {
          setState(() {
            _history.clear();
          });
        }
        unawaited(MbnSync.instance.touchAndPush('history'));
      },
    ),
  );

  void _openFavorites() => _push(
    _SavedPage(
      api: widget.api,
      title: 'علاقه‌مندی‌ها',
      emptyText: 'هنوز چیزی به علاقه‌مندی‌ها اضافه نکرده‌ای',
      emptyIcon: Icons.favorite_outline_rounded,
      itemsProvider: () => _favorites.values.toList(),
      onOpen: _open,
      clearTooltip: 'پاک کردن علاقه‌مندی‌ها',
      clearTitle: 'پاک کردن علاقه‌مندی‌ها؟',
      clearMessage: 'همهٔ علاقه‌مندی‌ها پاک می‌شود.',
      onClear: () async {
        _favorites.clear();
        await _store.saveFavorites([]);
        if (mounted) setState(() {});
        unawaited(MbnSync.instance.touchAndPush('favorites'));
      },
    ),
  );

  void _openPlaylists() => _push(PlaylistsPage(onOpen: _open));

  void _openSiblingAnime() => AppLinks.openSibling(context, siblingAnime);

  void _openUpdates() => _push(const UpdateScreen());

  Future<void> _openDelfanLink() async {
    final linked = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => DelfanPhoneLinkScreen(auth: widget.auth),
      ),
    );
    if (linked == true) {
      final body = await widget.auth.getJson('/api/me');
      widget.auth.profile = MbnProfile.fromJson(
        (body['user'] as Map).cast<String, dynamic>(),
      );
      final session = await widget.auth.getJson('/api/me/delfan/session');
      widget.api.bindDelfanSession(
        mobile: session['mobile']?.toString() ?? '',
        password: session['password']?.toString() ?? '',
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(
        key: _homeKey,
        api: widget.api,
        onOpen: _open,
        onTab: _goToPage,
        onSearch: _openSearch,
        onActors: _openCastSearch,
        onActor: _openActor,
      ),
      _CatalogPage(
        key: const ValueKey('movies'),
        api: widget.api,
        kind: ContentKind.movie,
        title: 'فیلم‌ها',
        onOpen: _open,
      ),
      _CatalogPage(
        key: const ValueKey('series'),
        api: widget.api,
        kind: ContentKind.series,
        title: 'سریال‌ها',
        onOpen: _open,
      ),
      // _UnseenPage(
      //   api: widget.api,
      //   seenIds: _history.map((item) => item.id).toSet(),
      //   onOpen: _open,
      // ),
      _SavedBody(
        api: widget.api,
        title: 'علاقه‌مندی‌ها',
        emptyText: 'هنوز چیزی به علاقه‌مندی‌ها اضافه نکرده‌ای',
        emptyIcon: Icons.favorite_outline_rounded,
        items: _favorites.values.toList(),
        onOpen: _open,
        heroPrefix: 'fav-',
      ),
    ];
    return Scaffold(
      extendBody: true,
      drawer: _MenuDrawer(
        auth: widget.auth,
        email: widget.email,
        selected: _index,
        select: _select,
        search: _openSearch,
        actors: _openCastSearch,
        history: _openHistory,
        playlists: _openPlaylists,
        downloads: () => _push(const DownloadManagerScreen()),
        settings: () => _push(const SettingsScreen()),
        updates: _openUpdates,
        subscription: () => _push(
          SubscriptionScreen(loadProfile: () => widget.auth.getJson('/api/me')),
        ),
        genres: () =>
            _push(_GroupsPage(api: widget.api, country: false, onOpen: _open)),
        countries: () =>
            _push(_GroupsPage(api: widget.api, country: true, onOpen: _open)),
        logout: () async {
          Navigator.maybePop(context);
          await widget.onLogout();
        },
      ),
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                showPhoneWarning: widget.auth.profile?.delfanVerified != true,
                onPhoneWarning: _openDelfanLink,
                search: _openSearch,
                actors: _openCastSearch,
                history: _openHistory,
                favorites: _openFavorites,
                switchApp: _openSiblingAnime,
              ),
              if (isAndroidTv)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      for (final (index, label) in [
                        'ویترین',
                        'سینمایی',
                        'سریال',
                        // 'دیده‌نشده',
                        'علاقه‌مندی‌ها',
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: ChoiceChip(
                            autofocus: index == 0,
                            label: Text(label),
                            selected: _index == index,
                            onSelected: (_) => _goToPage(index),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: isLargeScreenDevice
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                  onPageChanged: (value) {
                    if (_index != value) setState(() => _index = value);
                  },
                  children: pages,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isLargeScreenDevice
          ? null
          : _AnimatedBottomNav(index: _index, onSelected: _goToPage),
    );
  }
}

class _AnimatedBottomNav extends StatelessWidget {
  const _AnimatedBottomNav({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'ویترین'),
    (icon: Icons.movie_rounded, label: 'سینمایی'),
    (icon: Icons.video_collection_rounded, label: 'سریال'),
    // (icon: Icons.visibility_off_rounded, label: 'دیده‌نشده'),
    (icon: Icons.favorite_rounded, label: 'علاقه‌مندی‌ها'),
  ];

  @override
  Widget build(BuildContext context) {
    final iconsOnly = Platform.isAndroid;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF24252B),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: List.generate(_items.length, (itemIndex) {
              final item = _items[itemIndex];
              final selected = itemIndex == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: item.label,
                  child: InkWell(
                    onTap: () => onSelected(itemIndex),
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? MovieColors.orange.withValues(alpha: .92)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: MovieColors.orange.withValues(
                                    alpha: .28,
                                  ),
                                  blurRadius: 14,
                                ),
                              ]
                            : null,
                      ),
                      child: iconsOnly
                          ? Icon(
                              item.icon,
                              size: 22,
                              color: selected ? Colors.black : Colors.white70,
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: animation,
                                          child: child,
                                        ),
                                      ),
                                  child: selected
                                      ? Padding(
                                          key: ValueKey(itemIndex),
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Icon(
                                            item.icon,
                                            size: 22,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                Flexible(
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.black
                                          : Colors.white70,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// دکمه شناور جابه‌جایی بین برنامه‌ها: گرادیانی، پالس‌دار و متمایز.
class _AppSwitchButton extends StatefulWidget {
  const _AppSwitchButton({
    required this.tooltip,
    required this.gradient,
    required this.icon,
    required this.onTap,
    this.size = 40,
  });
  final String tooltip;
  final List<Color> gradient;
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  @override
  State<_AppSwitchButton> createState() => _AppSwitchButtonState();
}

class _AppSwitchButtonState extends State<_AppSwitchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (!AccessibilityService.instance.reduceMotion) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AccessibilityService.instance.reduceMotion;
    if (reduce && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    } else if (!reduce && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final reduce = AccessibilityService.instance.reduceMotion;
        final pulse = reduce ? 0.0 : Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: widget.gradient,
            ),
            borderRadius: BorderRadius.circular(widget.size * 0.35),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.first.withValues(
                  alpha: .25 + .3 * pulse,
                ),
                blurRadius: 10 + 8 * pulse,
                spreadRadius: 1,
              ),
            ],
          ),
          child: reduce ? child : Transform.scale(scale: 1 + .07 * pulse, child: child),
        );
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(widget.size * 0.35),
        child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.55),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showPhoneWarning,
    required this.onPhoneWarning,
    required this.search,
    required this.actors,
    required this.history,
    required this.favorites,
    required this.switchApp,
  });
  final bool showPhoneWarning;
  final VoidCallback onPhoneWarning;
  final VoidCallback search;
  final VoidCallback actors;
  final VoidCallback history;
  final VoidCallback favorites;
  final VoidCallback switchApp;

  Widget _actionButton({
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
    double iconSize = 24,
    double buttonSize = 40,
  }) => SizedBox(
    width: buttonSize,
    height: buttonSize,
    child: IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
      iconSize: iconSize,
      onPressed: onPressed,
      icon: Icon(icon),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;
    final reduceMotion = AccessibilityService.instance.reduceMotion;
    // Extra warning button takes more room: hide the wordmark sooner.
    final hideWordmark = showPhoneWarning ? width < 420 : width < 380;

    final warningButton = SizedBox(
      width: isCompact ? 36 : 40,
      height: isCompact ? 36 : 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: isCompact ? 36 : 40,
          minHeight: isCompact ? 36 : 40,
        ),
        tooltip: 'شمارهٔ موبایل تأیید نشده؛ تکمیل حساب',
        onPressed: onPhoneWarning,
        icon: Icon(
          Icons.warning_rounded,
          color: Colors.redAccent,
          size: isCompact ? 22 : 26,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 12,
        vertical: isCompact ? 4 : 8,
      ),
      child: SizedBox(
        height: isCompact ? 46 : 54,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                // Drawer button
                _actionButton(
                  tooltip: 'منوی اصلی',
                  onPressed: Scaffold.of(context).openDrawer,
                  icon: Icons.menu_rounded,
                  iconSize: isCompact ? 26 : 28,
                  buttonSize: isCompact ? 38 : 42,
                ),
                if (showPhoneWarning) ...[
                  const SizedBox(width: 2),
                  if (reduceMotion)
                    warningButton
                  else
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: .75, end: 1),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeInOut,
                      builder: (context, value, child) => Transform.scale(
                        scale: value,
                        child: child,
                      ),
                      child: warningButton,
                    ),
                ],
                const Spacer(),
                // Wide-screen actions (favorites/history are on bottom nav for phone)
                if (!isCompact) ...[
                  _actionButton(
                    tooltip: 'علاقه‌مندی‌ها',
                    onPressed: favorites,
                    icon: Icons.favorite_rounded,
                  ),
                  const SizedBox(width: 4),
                  _actionButton(
                    tooltip: 'بازدیدشده‌ها',
                    onPressed: history,
                    icon: Icons.history_rounded,
                  ),
                  const SizedBox(width: 4),
                  _actionButton(
                    tooltip: 'جست‌وجوی بازیگران',
                    onPressed: actors,
                    icon: Icons.people_alt_rounded,
                    iconSize: 22,
                  ),
                  const SizedBox(width: 4),
                ],
                // Search button
                _actionButton(
                  tooltip: 'جست‌وجو',
                  onPressed: search,
                  icon: Icons.search_rounded,
                  iconSize: isCompact ? 22 : 24,
                  buttonSize: isCompact ? 38 : 40,
                ),
                const SizedBox(width: 4),
                // Switch App button
                _AppSwitchButton(
                  tooltip: 'رفتن به MBNime',
                  gradient: const [Color(0xFFFF7A1A), Color(0xFFFF4F6D)],
                  icon: Icons.animation_rounded,
                  onTap: switchApp,
                  size: isCompact ? 34 : 40,
                ),
              ],
            ),
            // Always centered title (never shifted by asymmetric actions).
            IgnorePointer(
              child: BrandMark(
                size: isCompact ? 28 : 38,
                showWordmark: !hideWordmark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuDrawer extends StatelessWidget {
  const _MenuDrawer({
    required this.auth,
    required this.email,
    required this.selected,
    required this.select,
    required this.search,
    required this.actors,
    required this.history,
    required this.playlists,
    required this.genres,
    required this.countries,
    required this.logout,
    required this.downloads,
    required this.settings,
    required this.updates,
    required this.subscription,
  });
  final MbnAuth auth;
  final String email;
  final int selected;
  final ValueChanged<int> select;
  final VoidCallback search;
  final VoidCallback actors;
  final VoidCallback history;
  final VoidCallback playlists;
  final VoidCallback genres;
  final VoidCallback countries;
  final VoidCallback logout;
  final VoidCallback downloads;
  final VoidCallback settings;
  final VoidCallback updates;
  final VoidCallback subscription;

  @override
  Widget build(BuildContext context) => Drawer(
    width: MediaQuery.sizeOf(context).width.clamp(290, 360).toDouble(),
    backgroundColor: MovieColors.surface,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
        children: [
          const Center(child: BrandMark(size: 82)),
          const SizedBox(height: 12),
          Text(
            email,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: MovieColors.muted),
          ),
          const SizedBox(height: 10),
          _subscriptionBadge(context),
          const SizedBox(height: 14),
          _section('مرور محتوا', [
            _tile(Icons.home_rounded, 'ویترین', () => select(0), index: 0),
            _tile(Icons.movie_rounded, 'فیلم‌ها', () => select(1), index: 1),
            _tile(
              Icons.video_collection_rounded,
              'سریال‌ها',
              () => select(2),
              index: 2,
            ),
            _tile(Icons.manage_search_rounded, 'جست‌وجو', search),
            _tile(Icons.people_alt_rounded, 'جست‌وجوی بازیگران', actors),
            _tile(Icons.theater_comedy_rounded, 'دسته‌بندی فیلم‌ها', genres),
            _tile(Icons.flag_rounded, 'کشورها', countries),
          ]),
          _section('کتابخانهٔ من', [
            // _tile(
            //   Icons.visibility_off_rounded,
            //   'دیده‌نشده‌ها',
            //   () => select(3),
            //   index: 3,
            // ),
            _tile(
              Icons.favorite_rounded,
              'علاقه‌مندی‌ها',
              () => select(3),
              index: 3,
            ),
            _tile(Icons.history_rounded, 'بازدیدشده‌ها', history),
            _tile(Icons.queue_music_rounded, 'پلی‌لیست‌ها', playlists),
          ]),
          _section('حساب کاربری', [
            _tile(
              Icons.workspace_premium_rounded,
              'مدیریت اشتراک',
              subscription,
              tool: true,
            ),
            _tile(Icons.logout_rounded, 'خروج از حساب کاربری', logout),
          ]),
          // Support button with Telegram blue color #229ED9
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF229ED9).withValues(alpha: .24),
                  const Color(0xFF229ED9).withValues(alpha: .08),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFF229ED9).withValues(alpha: .6),
              ),
            ),
            child: ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF229ED9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: const Text(
                'تماس با پشتیبانی',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                '@mbnproo در تلگرام',
                style: TextStyle(color: Color(0xFF229ED9), fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_left_rounded,
                color: Color(0xFF229ED9),
              ),
              onTap: () => launchUrl(
                Uri.parse('https://t.me/mbnproo'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MovieColors.violet.withValues(alpha: .3),
                  MovieColors.cyan.withValues(alpha: .13),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: MovieColors.violet.withValues(alpha: .6),
              ),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.swap_horiz_rounded,
                color: MovieColors.cyan,
              ),
              title: const Text('رفتن به MBNime'),
              subtitle: const Text('دنیای انیمه'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => AppLinks.openSibling(context, siblingAnime),
            ),
          ),
          _section('ابزارهای برنامه', [
            _tile(
              Icons.download_for_offline_rounded,
              'مدیریت دانلودها',
              downloads,
              tool: true,
            ),
            _tile(Icons.tune_rounded, 'تنظیمات', settings, tool: true),
            _tile(
              Icons.system_update_alt_rounded,
              'به‌روزرسانی برنامه',
              updates,
              tool: true,
            ),
          ]),
        ],
      ),
    ),
  );

  Widget _subscriptionBadge(BuildContext context) {
    final profile = auth.profile;
    final isAdmin = profile?.role == 'admin';
    final exp = profile?.subscriptionExpiresAt;
    final expiry = exp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final remaining = expiry?.difference(DateTime.now());
    final hasActive = isAdmin || (remaining != null && !remaining.isNegative);

    String text;
    if (isAdmin) {
      text = 'اشتراک: نامحدود (مدیر)';
    } else if (exp == null) {
      text = 'اشتراک: ثبت نشده';
    } else if (remaining == null || remaining.isNegative) {
      text = 'اشتراک به پایان رسیده';
    } else if (remaining.inDays > 0) {
      text = '${_toPersianDigits(remaining.inDays)} روز مانده از اشتراک';
    } else {
      final hours = remaining.inHours;
      text = hours > 0
          ? '${_toPersianDigits(hours)} ساعت مانده از اشتراک'
          : 'کمتر از ۱ ساعت مانده از اشتراک';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MovieColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasActive
              ? MovieColors.orange.withValues(alpha: 0.3)
              : Colors.redAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasActive ? Icons.verified_rounded : Icons.schedule_rounded,
                size: 16,
                color: hasActive ? const Color(0xFF00E676) : Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: hasActive ? Colors.white70 : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => launchUrl(
                Uri.parse('https://t.me/mbnproo'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.autorenew_rounded, size: 16),
              label: const Text(
                'تمدید اشتراک',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _toPersianDigits(Object value) => '$value'.replaceAllMapped(
    RegExp(r'\d'),
    (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match.group(0)!)],
  );

  Widget _label(String label) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
    child: Text(
      label,
      style: const TextStyle(
        color: MovieColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(6, 12, 6, 7),
    decoration: BoxDecoration(
      color: MovieColors.surfaceHigh,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white12),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_label(title), ...children],
      ),
    ),
  );

  Widget _tile(
    IconData icon,
    String label,
    VoidCallback tap, {
    int? index,
    bool tool = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      selected: index == selected,
      selectedTileColor: MovieColors.orange.withValues(alpha: .14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Icon(
        icon,
        color: index == selected || tool
            ? MovieColors.orange
            : MovieColors.muted,
      ),
      title: Text(label),
      trailing: tool ? const Icon(Icons.chevron_left_rounded, size: 20) : null,
      onTap: tap,
    ),
  );
}

class _HomePage extends StatefulWidget {
  const _HomePage({
    super.key,
    required this.api,
    required this.onOpen,
    required this.onTab,
    required this.onSearch,
    required this.onActors,
    required this.onActor,
  });
  final MovieApi api;
  final OpenContent onOpen;

  /// Switches the bottom-nav tab (1 = movies, 2 = series) for «مشاهده همه».
  final void Function(int index) onTab;
  final VoidCallback onSearch;
  final VoidCallback onActors;
  final ValueChanged<MoviePerson> onActor;
  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late Future<HomeCatalog> _future = widget.api.home();
  final _lastWatchStore = LastWatchStore();
  LastWatch? _lastWatch;

  @override
  void initState() {
    super.initState();
    _reloadContinueWatch();
  }

  Future<void> _reload() async {
    final next = widget.api.home();
    setState(() {
      _future = next;
    });
    unawaited(_reloadContinueWatch());
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the failure. Do not leak it from a tap/refresh.
    }
  }

  Future<void> _reloadContinueWatch() => refreshContinueWatch();

  /// Reloads the «ادامه تماشا» shelf (called on tab select + after resume).
  Future<void> refreshContinueWatch() async {
    final last = await _lastWatchStore.load();
    if (mounted) setState(() => _lastWatch = last);
  }

  void _openSectionAll(HomeSection section) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _SectionAllPage(
          api: widget.api,
          section: section,
          kind: section.id == 'updated'
              ? ContentKind.series
              : ContentKind.movie,
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  void _openCollection(MovieCollection collection) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _CollectionTitlesPage(
          api: widget.api,
          collection: collection,
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  void _openAllCollections(List<MovieCollection> initial) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _AllCollectionsPage(
          api: widget.api,
          initialCollections: initial,
          onOpenCollection: _openCollection,
        ),
      ),
    );
  }

  void _openBanner(MovieBanner banner) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _CategoryTitlesPage(
          api: widget.api,
          banner: banner,
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  void _openGenre(CatalogGroup group) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _GroupResultsPage(
          api: widget.api,
          group: group,
          country: false,
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  void _openCountry(CatalogGroup group) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _GroupResultsPage(
          api: widget.api,
          group: group,
          country: true,
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  void _openTag(MovieTag tag) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _TagResultsPage(api: widget.api, tag: tag, onOpen: widget.onOpen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HomeCatalog>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _HomeLoadingSkeleton();
      }
      if (snapshot.hasError || snapshot.data == null) {
        return _ErrorState(retry: _reload, error: snapshot.error);
      }
      final data = snapshot.data!;
      final seenIds = <String>{};
      final featured =
          (data.featured.isEmpty
                  ? [...data.series, ...data.movies]
                  : data.featured)
              .where((item) => seenIds.add(item.id))
              .toList(growable: false);
      return RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (featured.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 0,
                  child: _Featured(items: featured, onOpen: widget.onOpen),
                ),
              ),
            if (data.actors.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 2,
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      _SectionTitle('بازیگران', onAll: widget.onActors),
                      SizedBox(
                        height: 150,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: data.actors.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final actor = data.actors[index];
                            return Pressable(
                              onTap: () => widget.onActor(actor),
                              child: SizedBox(
                                width: 105,
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 45,
                                      foregroundImage:
                                          actor.imageUrl == null ||
                                              actor.imageUrl!.isEmpty
                                          ? null
                                          : NetworkImage(actor.imageUrl!),
                                      child: const Icon(Icons.person_rounded),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      actor.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
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
              ),
            if (_lastWatch case final last?)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 1,
                  child: _ContinueWatchSection(
                    last: last,
                    onPlayed: refreshContinueWatch,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _SectionEntrance(
                index: 1,
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _SectionTitle(
                      'آخرین سریال‌ها',
                      onAll: () => widget.onTab(2),
                    ),
                    _PaginatedPosterRow(
                      api: widget.api,
                      kind: ContentKind.series,
                      initial: data.series,
                      onOpen: widget.onOpen,
                      heroPrefix: 'hseries-',
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionEntrance(
                index: 2,
                child: Column(
                  children: [
                    const SizedBox(height: 26),
                    _SectionTitle(
                      'آخرین فیلم‌ها',
                      onAll: () => widget.onTab(1),
                    ),
                    _PaginatedPosterRow(
                      api: widget.api,
                      kind: ContentKind.movie,
                      initial: data.movies,
                      onOpen: widget.onOpen,
                      heroPrefix: 'hmovies-',
                    ),
                  ],
                ),
              ),
            ),
            if (data.banners.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 3,
                  child: Column(
                    children: [
                      const SizedBox(height: 26),
                      const _PlainSectionTitle('دسته‌های ویژه'),
                      _HorizontalRail(
                        height: 150,
                        children: [
                          for (final banner in data.banners)
                            Pressable(
                              onTap: () => _openBanner(banner),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Stack(
                                  children: [
                                    Image.network(
                                      banner.imageUrl,
                                      width: 280,
                                      height: 150,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox(
                                        width: 280,
                                        height: 150,
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withValues(
                                                alpha: .75,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 14,
                                      left: 14,
                                      bottom: 12,
                                      child: Text(
                                        banner.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (data.collections.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 4,
                  child: Column(
                    children: [
                      const SizedBox(height: 26),
                      _SectionTitle(
                        'مجموعه‌ها',
                        onAll: () => _openAllCollections(data.collections),
                      ),
                      _HorizontalRail(
                        height: 190,
                        children: [
                          for (final collection in data.collections)
                            Pressable(
                              onTap: () => _openCollection(collection),
                              child: SizedBox(
                                width: 130,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: collection.imageUrl == null
                                            ? const DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      MovieColors.surface,
                                                      Color(0xFF232838),
                                                    ],
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.collections_rounded,
                                                  color: MovieColors.cyan,
                                                  size: 40,
                                                ),
                                              )
                                            : Image.network(
                                                collection.imageUrl!,
                                                width: 130,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    const Icon(
                                                      Icons.collections_rounded,
                                                    ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      collection.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (data.genres.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 5,
                  child: Column(
                    children: [
                      const SizedBox(height: 26),
                      const _PlainSectionTitle('ژانرها'),
                      _HorizontalRail(
                        height: 44,
                        gap: 8,
                        children: [
                          for (final genre in data.genres)
                            ActionChip(
                              label: Text(genre.name),
                              onPressed: () => _openGenre(genre),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (data.countries.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 6,
                  child: Column(
                    children: [
                      const SizedBox(height: 22),
                      const _PlainSectionTitle('کشورها'),
                      _HorizontalRail(
                        height: 44,
                        gap: 8,
                        children: [
                          for (final country in data.countries)
                            ActionChip(
                              avatar: const Icon(
                                Icons.public_rounded,
                                size: 16,
                              ),
                              label: Text(country.name),
                              onPressed: () => _openCountry(country),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (data.tags.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 7,
                  child: Column(
                    children: [
                      const SizedBox(height: 22),
                      const _PlainSectionTitle('موضوعات'),
                      _HorizontalRail(
                        height: 44,
                        gap: 8,
                        children: [
                          for (final tag in data.tags)
                            ActionChip(
                              avatar: const Icon(Icons.tag_rounded, size: 16),
                              label: Text(tag.title),
                              onPressed: () => _openTag(tag),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            for (var index = 0; index < data.sections.length; index++)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: index + 3,
                  child: Column(
                    children: [
                      const SizedBox(height: 26),
                      _SectionTitle(
                        data.sections[index].title,
                        onAll: () => _openSectionAll(data.sections[index]),
                      ),
                      // ردیف‌های ویترین با ۸ آیتم سرور شروع می‌شوند و با
                      // اسکرول، صفحه‌های بعدی هم‌نوع اضافه می‌شود.
                      _PaginatedPosterRow(
                        api: widget.api,
                        kind: data.sections[index].id == 'updated'
                            ? ContentKind.series
                            : ContentKind.movie,
                        initial: data.sections[index].items,
                        onOpen: widget.onOpen,
                        heroPrefix: 'home-${data.sections[index].id}-',
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
          ],
        ),
      );
    },
  );
}

class _SectionEntrance extends StatefulWidget {
  const _SectionEntrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_SectionEntrance> createState() => _SectionEntranceState();
}

class _SectionEntranceState extends State<_SectionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, .055),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (isDesktopWindow) {
      _controller.value = 1;
      return;
    }
    _start();
  }

  Future<void> _start() async {
    await Future<void>.delayed(
      Duration(milliseconds: (widget.index * 75).clamp(0, 450).toInt()),
    );
    if (mounted) await _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _offset, child: widget.child),
  );
}

class _HomeLoadingSkeleton extends StatefulWidget {
  const _HomeLoadingSkeleton();

  @override
  State<_HomeLoadingSkeleton> createState() => _HomeLoadingSkeletonState();
}

class _HomeLoadingSkeletonState extends State<_HomeLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final color = Color.lerp(
        MovieColors.surface,
        MovieColors.surfaceHigh,
        Curves.easeInOut.transform(_controller.value),
      )!;
      // Mirror the loaded layout so the skeleton looks complete on wide
      // desktop windows: featured banner (340 + dots) and poster rows
      // (230 x 148) with enough items to fill the row width.
      final rowWidth = MediaQuery.sizeOf(context).width - 36;
      final rowCount = ((rowWidth / (148 + 12)).ceil()).clamp(4, 12).toInt();
      // Purely decorative shimmer: keep it out of the accessibility tree so
      // engine AX updates stay quiet while content loads.
      return ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 100),
          children: [
            _SkeletonBox(height: 340, color: color, radius: 32),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (i) => Container(
                  width: i == 0 ? 24 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            for (var section = 0; section < 3; section++) ...[
              SizedBox(height: section == 0 ? 24 : 26),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _SkeletonBox(height: 22, width: 150, color: color),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 230,
                child: ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  itemCount: rowCount,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, _) => _SkeletonBox(
                    height: 230,
                    width: 148,
                    color: color,
                    radius: 24,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.height,
    required this.color,
    this.width = double.infinity,
    this.radius = 12,
  });

  final double height;
  final double width;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _Featured extends StatefulWidget {
  const _Featured({required this.items, required this.onOpen});
  final List<MovieContent> items;
  final OpenContent onOpen;
  @override
  State<_Featured> createState() => _FeaturedState();
}

class _FeaturedState extends State<_Featured> {
  late final PageController _controller;
  Timer? _autoPlayTimer;
  int _page = 0;

  int get _count => widget.items.length.clamp(0, 12);

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: .9);
    _restartAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _Featured oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _count) _page = 0;
    _restartAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartAutoPlay() {
    _autoPlayTimer?.cancel();
    if (_count < 2 || isAndroidTv) return;
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted ||
          !_controller.hasClients ||
          !TickerMode.valuesOf(context).enabled ||
          ModalRoute.of(context)?.isCurrent == false ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _goTo((_page + 1) % _count, restartTimer: false);
    });
  }

  void _goTo(int target, {bool restartTimer = true}) {
    if (_count < 2 || !_controller.hasClients) return;
    final normalized = (target + _count) % _count;
    _controller.animateToPage(
      normalized,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubicEmphasized,
    );
    if (restartTimer) _restartAutoPlay();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Column(
      children: [
        SizedBox(
          height: isAndroidTv ? 250 : 340,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                  overscroll: false,
                ),
                child: Listener(
                  onPointerDown: (_) => _restartAutoPlay(),
                  child: PageView.builder(
                    controller: _controller,
                    physics: const BouncingScrollPhysics(),
                    padEnds: true,
                    itemCount: count,
                    onPageChanged: (value) {
                      setState(() => _page = value);
                      _restartAutoPlay();
                    },
                    itemBuilder: (_, index) => AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final current =
                            _controller.hasClients &&
                                _controller.position.hasContentDimensions
                            ? (_controller.page ?? _page.toDouble())
                            : _page.toDouble();
                        final distance = (current - index).abs().clamp(
                          0.0,
                          1.0,
                        );
                        return Opacity(
                          opacity: 1 - (distance * .28),
                          child: Transform.scale(
                            scale: 1 - (distance * .055),
                            child: child,
                          ),
                        );
                      },
                      child: _FeaturedCard(
                        item: widget.items[index],
                        onOpen: widget.onOpen,
                      ),
                    ),
                  ),
                ),
              ),
              if (count > 1) ...[
                Positioned(
                  left: 22,
                  child: _SliderArrow(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'اسلاید بعدی',
                    onTap: () => _goTo(_page + 1),
                  ),
                ),
                Positioned(
                  right: 22,
                  child: _SliderArrow(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'اسلاید قبلی',
                    onTap: () => _goTo(_page - 1),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            count,
            (i) => InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _goTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                width: i == _page ? 24 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _page ? MovieColors.orange : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: i == _page
                      ? [
                          BoxShadow(
                            color: MovieColors.orange.withValues(alpha: .45),
                            blurRadius: 9,
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
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.onOpen});
  final MovieContent item;
  final OpenContent onOpen;

  @override
  Widget build(BuildContext context) {
    final tag = 'featured-${item.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Pressable(
        onTap: () => onOpen(item, tag),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ContentArt(
              content: item,
              imageUrl: item.backdropUrl ?? item.imageUrl,
              orientation: ArtworkOrientation.landscape,
              borderRadius: 32,
              showTitle: false,
            ),
            Positioned(
              right: 22,
              left: 22,
              bottom: 22,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          [
                            '${item.year}',
                            item.kindLabel,
                            if (item.rating > 0) 'IMDB: ${item.ratingLabel}',
                          ].join(' · '),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    iconSize: 34,
                    onPressed: () => onOpen(item, tag),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderArrow extends StatelessWidget {
  const _SliderArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .56),
    shape: const CircleBorder(),
    elevation: 8,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 34),
    ),
  );
}

// ignore: unused_element
class _UnseenPage extends StatelessWidget {
  const _UnseenPage({
    required this.api,
    required this.seenIds,
    required this.onOpen,
  });
  final MovieApi api;
  final Set<String> seenIds;
  final OpenContent onOpen;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'فیلم‌ها'),
            Tab(text: 'سریال‌ها'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _CatalogPage(
                api: api,
                kind: ContentKind.movie,
                title: 'فیلم‌های دیده‌نشده',
                onOpen: onOpen,
                hiddenIds: seenIds,
              ),
              _CatalogPage(
                api: api,
                kind: ContentKind.series,
                title: 'سریال‌های دیده‌نشده',
                onOpen: onOpen,
                hiddenIds: seenIds,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CatalogPage extends StatefulWidget {
  const _CatalogPage({
    super.key,
    required this.api,
    required this.kind,
    required this.title,
    required this.onOpen,
    this.hiddenIds = const {},
  });
  final MovieApi api;
  final ContentKind kind;
  final String title;
  final OpenContent onOpen;
  final Set<String> hiddenIds;
  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<_CatalogPage> {
  final items = <MovieContent>[];
  final scroll = ScrollController();
  int page = 0;
  bool loading = false;
  bool more = true;
  String? error;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 450) _load();
    });
    _load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (loading || (!more && !reset)) return;
    if (reset) {
      page = 0;
      more = true;
      items.clear();
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.api.catalog(kind: widget.kind, page: page + 1);
      if (!mounted) return;
      setState(() {
        page++;
        items.addAll(next.where((e) => !items.any((old) => old.id == e.id)));
        more = next.isNotEmpty;
      });
      _fillIfNeeded();
    } on MovieApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// اگر همه موارد صفحه اول در نما جا شوند، صفحه‌های بعدی خودکار خوانده
  /// می‌شوند تا فهرست نصفه نماند.
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

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => _load(reset: true),
    child: CustomScrollView(
      controller: scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _PageTitle(
            widget.title,
            action: _FilterAction(
              api: widget.api,
              onOpen: widget.onOpen,
              title: widget.title,
              type: widget.kind == ContentKind.movie ? 'movie' : 'serie',
            ),
          ),
        ),
        if (items.isEmpty && loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty && error != null)
          SliverFillRemaining(child: _ErrorState(retry: _load))
        else
          _ContentGrid(
            items: items
                .where((item) => !widget.hiddenIds.contains(item.id))
                .toList(),
            onOpen: widget.onOpen,
            heroPrefix: widget.kind == ContentKind.movie
                ? 'movies-'
                : 'series-',
          ),
        if (items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, bottomListGap),
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : error != null
                    ? TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('تلاش دوباره'),
                      )
                    : !more
                    ? const Text(
                        'همه عنوان‌ها نمایش داده شد',
                        style: TextStyle(color: MovieColors.muted),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    ),
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({
    required this.api,
    required this.onOpen,
    this.title = 'جست‌وجو',
    this.initialType = '',
    this.initialGenre,
    this.initialCountry,
    this.sourcePage,
  });
  final String title;
  final String initialType;
  final CatalogGroup? initialGenre;
  final CatalogGroup? initialCountry;
  final Future<List<MovieContent>> Function(int page)? sourcePage;
  final MovieApi api;
  final OpenContent onOpen;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final controller = TextEditingController();
  final yearFromController = TextEditingController();
  final yearToController = TextEditingController();
  final scroll = ScrollController();
  Timer? debounce;
  Timer? _yearDebounce;
  List<MovieContent> results = [];
  bool loading = false;
  bool advanced = false;
  // True once a search actually ran for the current query; while false the
  // empty area shows a hint instead of a bogus "nothing found".
  bool _hasSearched = false;
  // Advanced-filter collapse state (auto-opened when presets exist).
  bool _advancedExpanded = false;
  int _advPage = 0;
  bool _advMore = true;
  bool _advLoadingMore = false;
  String? error;
  // Monotonic request generation: every search captures its id and only the
  // latest may touch results/error/loading, so a slow earlier request can
  // never overwrite the current query's state.
  int _searchGeneration = 0;
  Future<List<MovieContent>>? _scopedItems;
  static const _recentSearchesKey = 'recent_searches_movie';
  List<String> _recentSearches = [];

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentSearchesKey) ?? [];
    if (mounted) setState(() => _recentSearches = list);
  }

  Future<void> _addRecentSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final updated = [
      q,
      ..._recentSearches.where((s) => s.toLowerCase() != q.toLowerCase()),
    ];
    if (updated.length > 15) updated.removeRange(15, updated.length);
    if (mounted) setState(() => _recentSearches = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, updated);
  }

  Future<void> _removeRecentSearch(String item) async {
    final updated = _recentSearches.where((s) => s != item).toList();
    if (mounted) setState(() => _recentSearches = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, updated);
  }

  Future<void> _clearRecentSearches() async {
    if (mounted) setState(() => _recentSearches = []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
  }

  Future<List<MovieContent>> _loadScopedItems() => _scopedItems ??= () async {
    final items = <MovieContent>[];
    final seen = <String>{};
    var repeatedPages = 0;
    for (var page = 1; page <= 800; page++) {
      final next = await widget.sourcePage!(page);
      if (next.isEmpty) break;
      final before = items.length;
      for (final item in next) {
        if (seen.add(item.id)) items.add(item);
      }
      repeatedPages = items.length == before ? repeatedPages + 1 : 0;
      if (repeatedPages >= 2) break;
    }
    return items;
  }();

  // فیلدهای جست‌وجوی پیشرفته (مطابق فرم اپ مرجع).
  bool exact = false;
  String type = '';
  String dub = '';
  String stateSerie = '';
  CatalogGroup? genre;
  CatalogGroup? country;
  String imdb = '';
  String sortBy = 'NewMovie';
  List<CatalogGroup> _genres = const [];
  List<CatalogGroup> _countries = const [];

  static const _typeOptions = [
    MapEntry('', 'همه'),
    MapEntry('movie', 'فیلم'),
    MapEntry('serie', 'سریال'),
  ];
  static const _dubOptions = [
    MapEntry('', 'مهم نیست'),
    MapEntry('dub', 'دوبله'),
    MapEntry('sub', 'زیرنویس'),
    MapEntry('nosub', 'بدون زیرنویس'),
  ];
  static const _stateOptions = [
    MapEntry('', 'مهم نیست'),
    MapEntry('1', 'در حال پخش'),
    MapEntry('0', 'تمام‌شده'),
  ];
  static const _imdbOptions = [
    MapEntry('', 'مهم نیست'),
    MapEntry('9', '۹ به بالا'),
    MapEntry('8', '۸ به بالا'),
    MapEntry('7', '۷ به بالا'),
    MapEntry('6', '۶ به بالا'),
    MapEntry('5', '۵ به بالا'),
  ];
  static const _sortOptions = [
    MapEntry('NewMovie', 'پیش‌فرض'),
    MapEntry('new', 'جدیدترین'),
    MapEntry('imdb', 'بالاترین امتیاز'),
  ];

  @override
  void initState() {
    super.initState();
    type = widget.initialType;
    genre = widget.initialGenre;
    country = widget.initialCountry;
    // If the page opened with preset filters, show the advanced section open.
    _advancedExpanded =
        type.isNotEmpty || genre != null || country != null;
    scroll.addListener(() {
      if (_advMore &&
          !_advLoadingMore &&
          scroll.position.extentAfter < 500 &&
          (advanced || controller.text.trim().length >= 2)) {
        _loadMoreResults();
      }
    });
    _preloadGroups();
    unawaited(_loadRecentSearches());
    if (widget.sourcePage == null &&
        (type.isNotEmpty ||
            genre != null ||
            country != null ||
            controller.text.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) runAdvanced();
      });
    }
  }

  Future<void> _preloadGroups() async {
    try {
      final loaded = await Future.wait([
        widget.api.genres(),
        widget.api.countries(),
      ]);
      if (!mounted) return;
      setState(() {
        _genres = loaded[0];
        _countries = loaded[1];
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    debounce?.cancel();
    _yearDebounce?.cancel();
    controller.dispose();
    yearFromController.dispose();
    yearToController.dispose();
    scroll.dispose();
    super.dispose();
  }

  void changed(String value) {
    debounce?.cancel();
    _searchGeneration++;
    setState(() {
      error = null;
      // Never leave the buttons locked: typing during a request cancels it
      // and returns the page to the pre-search hint state.
      loading = false;
      advanced = false;
      results = [];
      _hasSearched = false;
    });
  }

  Future<void> search() async {
    if (widget.sourcePage != null ||
        exact ||
        type.isNotEmpty ||
        dub.isNotEmpty ||
        stateSerie.isNotEmpty ||
        genre != null ||
        country != null ||
        imdb.isNotEmpty ||
        sortBy != 'NewMovie' ||
        _year(yearFromController).isNotEmpty ||
        _year(yearToController).isNotEmpty) {
      await runAdvanced();
      return;
    }
    final query = controller.text.trim();
    if (query.length < 2) return;
    unawaited(_addRecentSearch(query));
    final generation = ++_searchGeneration;
    setState(() {
      loading = true;
      error = null;
      advanced = false;
      _hasSearched = true;
    });
    try {
      final found = await widget.api.search(
        query,
        isCanceled: () =>
            !mounted ||
            generation != _searchGeneration ||
            query != controller.text.trim(),
        onPartial: (partial) {
          if (!mounted ||
              generation != _searchGeneration ||
              query != controller.text.trim()) {
            return;
          }
          setState(() => results = partial);
        },
      );
      if (!mounted || generation != _searchGeneration) return;
      if (query != controller.text.trim()) return;
      setState(() {
        results = found;
        _advPage = 1;
        _advMore = found.isNotEmpty;
      });
    } on MovieApiException catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      if (query != controller.text.trim()) return;
      setState(() => error = e.message);
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => loading = false);
      }
    }
  }

  static String _year(TextEditingController controller) {
    final digits = controller.text
        .replaceAll(RegExp(r'[^0-9۰-۹٠-٩]'), '')
        .replaceAllMapped(
          RegExp(r'[۰-۹٠-٩]'),
          (match) => '${'۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩'.indexOf(match.group(0)!) % 10}',
        );
    if (digits.length != 4) return '';
    final year = int.tryParse(digits) ?? 0;
    if (year < 1300 || year > 2100) return '';
    return '$year';
  }

  Future<void> runAdvanced() async {
    debounce?.cancel();
    final query = controller.text.trim();
    final hasFilters =
        exact ||
        type.isNotEmpty ||
        dub.isNotEmpty ||
        stateSerie.isNotEmpty ||
        genre != null ||
        country != null ||
        imdb.isNotEmpty ||
        sortBy != 'NewMovie' ||
        _year(yearFromController).isNotEmpty ||
        _year(yearToController).isNotEmpty;
    if (widget.sourcePage == null && query.length >= 2 && !hasFilters) {
      await search();
      return;
    }
    if (query.length >= 2) unawaited(_addRecentSearch(query));
    final generation = ++_searchGeneration;
    setState(() {
      loading = true;
      error = null;
      advanced = true;
      _hasSearched = true;
      _advPage = 0;
      _advMore = true;
    });
    try {
      final source = widget.sourcePage == null
          ? null
          : await _loadScopedItems();
      final found = await (source == null
          ? widget.api.advancedFilter(
              query: controller.text.trim(),
              exact: exact,
              type: type,
              dub: dub,
              genre: genre?.id ?? '',
              country: country?.id ?? '',
              imdb: imdb,
              sortBy: sortBy,
              yearFrom: _year(yearFromController),
              yearTo: _year(yearToController),
              stateSerie: stateSerie,
              page: 1,
            )
          : widget.api.filterWithinSource(
              source,
              query: controller.text.trim(),
              exact: exact,
              type: type,
              dub: dub,
              genre: genre?.id ?? '',
              country: country?.id ?? '',
              imdb: imdb,
              sortBy: sortBy,
              yearFrom: _year(yearFromController),
              yearTo: _year(yearToController),
              stateSerie: stateSerie,
            ));
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        results = found;
        _advPage = 1;
        _advMore = found.isNotEmpty;
      });
    } on MovieApiException catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => error = e.message);
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _loadMoreResults() async {
    if (_advLoadingMore || !_advMore) return;
    final query = controller.text.trim();
    if (!advanced && query.length < 2) return;
    final generation = _searchGeneration;
    final fType = type;
    final fDub = dub;
    final fGenre = genre?.id ?? '';
    final fCountry = country?.id ?? '';
    final fImdb = imdb;
    final fSort = sortBy;
    final fYearFrom = _year(yearFromController);
    final fYearTo = _year(yearToController);
    final fState = stateSerie;
    final fExact = exact;
    setState(() => _advLoadingMore = true);
    try {
      final source = widget.sourcePage == null
          ? null
          : await _loadScopedItems();
      final found = advanced
          ? await (source == null
                ? widget.api.advancedFilter(
                    query: query,
                    exact: fExact,
                    type: fType,
                    dub: fDub,
                    genre: fGenre,
                    country: fCountry,
                    imdb: fImdb,
                    sortBy: fSort,
                    yearFrom: fYearFrom,
                    yearTo: fYearTo,
                    stateSerie: fState,
                    page: _advPage + 1,
                  )
                : widget.api.filterWithinSource(
                    source,
                    query: query,
                    exact: fExact,
                    type: fType,
                    dub: fDub,
                    genre: fGenre,
                    country: fCountry,
                    imdb: fImdb,
                    sortBy: fSort,
                    yearFrom: fYearFrom,
                    yearTo: fYearTo,
                    stateSerie: fState,
                    page: _advPage + 1,
                  ))
          : await widget.api.search(query, page: _advPage + 1);
      if (!mounted || generation != _searchGeneration) return;
      if (query != controller.text.trim()) return;
      setState(() {
        _advPage++;
        final seen = {for (final item in results) item.id};
        for (final item in found) {
          if (seen.add(item.id)) results.add(item);
        }
        _advMore = found.isNotEmpty;
      });
    } on MovieApiException {
      // خطای گذرا؛ اسکرول بعدی دوباره تلاش می‌کند.
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _advLoadingMore = false);
      }
    }
  }

  void clearSearch() {
    _searchGeneration++;
    debounce?.cancel();
    _yearDebounce?.cancel();
    controller.clear();
    setState(() {
      results = [];
      error = null;
      loading = false;
      advanced = false;
      _hasSearched = false;
    });
  }

  /// Number of active advanced filters (for the collapse subtitle).
  int get _activeFilterCount {
    var n = 0;
    if (exact) n++;
    if (type.isNotEmpty) n++;
    if (dub.isNotEmpty) n++;
    if (stateSerie.isNotEmpty) n++;
    if (genre != null) n++;
    if (country != null) n++;
    if (imdb.isNotEmpty) n++;
    if (sortBy != 'NewMovie') n++;
    if (_year(yearFromController).isNotEmpty) n++;
    if (_year(yearToController).isNotEmpty) n++;
    return n;
  }

  static String _faDigits(int value) => '$value'.replaceAllMapped(
    RegExp(r'\d'),
    (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match.group(0)!)],
  );

  /// Year inputs apply automatically (debounced) instead of needing a button.
  void _onYearChanged() {
    _yearDebounce?.cancel();
    _yearDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) unawaited(runAdvanced());
    });
  }

  String _optionLabel(List<MapEntry<String, String>> options, String value) {
    for (final option in options) {
      if (option.key == value) return option.value;
    }
    return 'مهم نیست';
  }

  Future<void> _pickOption({
    required String title,
    required List<MapEntry<String, String>> options,
    required String current,
    required ValueChanged<String> onPick,
  }) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option.key),
              child: Row(
                children: [
                  Expanded(child: Text(option.value)),
                  if (option.key == current)
                    const Icon(Icons.check_rounded, color: MovieColors.orange),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) onPick(picked);
  }

  Future<void> _pickGenre() async {
    if (_genres.isEmpty) {
      await _preloadGroups();
      if (_genres.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فهرست ژانرها در دسترس نیست.')),
        );
      }
      return;
    }
    await _pickOption(
      title: 'ژانرها',
      options: [
        const MapEntry('', 'مهم نیست'),
        for (final group in _genres) MapEntry(group.id, group.name),
      ],
      current: genre?.id ?? '',
      onPick: (value) {
        setState(
          () => genre = value.isEmpty
              ? null
              : _genres.firstWhere((group) => group.id == value),
        );
        unawaited(runAdvanced());
      },
    );
  }

  Future<void> _pickCountry() async {
    if (_countries.isEmpty) {
      await _preloadGroups();
      if (_countries.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فهرست کشورها در دسترس نیست.')),
        );
      }
      return;
    }
    await _pickOption(
      title: 'کشورها',
      options: [
        const MapEntry('', 'مهم نیست'),
        for (final group in _countries) MapEntry(group.id, group.name),
      ],
      current: country?.id ?? '',
      onPick: (value) {
        setState(
          () => country = value.isEmpty
              ? null
              : _countries.firstWhere((group) => group.id == value),
        );
        unawaited(runAdvanced());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = results;
    return _InnerScaffold(
      title: widget.title,
      child: CustomScrollView(
        controller: scroll,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Directionality(
                          textDirection: searchTextDirection(controller.text),
                          child: SearchBar(
                            controller: controller,
                            hintText: 'نام فیلم یا سریال را بنویس…',
                            leading: IconButton(
                              icon: const Icon(Icons.search_rounded),
                              onPressed: search,
                              tooltip: 'جستجو',
                            ),
                            trailing: [
                              if (controller.text.isNotEmpty)
                                IconButton(
                                  onPressed: clearSearch,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                            onChanged: changed,
                            onSubmitted: (_) => search(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(116, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        // Never locked: a new tap cancels the in-flight
                        // request (generation guard) so the user can always
                        // edit and re-search.
                        onPressed: search,
                        icon: loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.search_rounded),
                        label: const Text('جست‌وجو کن'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (controller.text.trim().isEmpty &&
              results.isEmpty &&
              !loading &&
              _recentSearches.isNotEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: MovieColors.surfaceHigh.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.history_rounded,
                                  size: 20,
                                  color: MovieColors.orange,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'جست‌وجوهای اخیر',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _clearRecentSearches,
                                  icon: const Icon(
                                    Icons.delete_sweep_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'پاک کردن تاریخچه',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item in _recentSearches)
                                  InputChip(
                                    avatar: const Icon(
                                      Icons.history_rounded,
                                      size: 16,
                                      color: MovieColors.orange,
                                    ),
                                    label: Text(item),
                                    onDeleted: () => _removeRecentSearch(item),
                                    onPressed: () {
                                      controller.text = item;
                                      search();
                                    },
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
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Card(
                color: MovieColors.surfaceHigh,
                child: ExpansionTile(
                  initiallyExpanded: _advancedExpanded,
                  onExpansionChanged: (open) =>
                      setState(() => _advancedExpanded = open),
                  leading: const Icon(
                    Icons.tune_rounded,
                    color: MovieColors.orange,
                  ),
                  title: const Text(
                    'جستجوی پیشرفته',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: _activeFilterCount == 0
                      ? const Text('فیلترها: همه')
                      : Text(
                          '${_faDigits(_activeFilterCount)} فیلتر فعال — برای اعمال، «جست‌وجو کن»',
                        ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('جست‌وجوی دقیق نام فیلم'),
                        value: exact,
                        onChanged: (value) {
                          setState(() => exact = value);
                          unawaited(runAdvanced());
                        },
                      ),
                      const Divider(height: 8),
                      _filterRow(
                        icon: Icons.category_rounded,
                        label: 'دسته',
                        value: _optionLabel(_typeOptions, type),
                        onTap: () => _pickOption(
                          title: 'دسته',
                          options: _typeOptions,
                          current: type,
                          onPick: (value) {
                            setState(() => type = value);
                            unawaited(runAdvanced());
                          },
                        ),
                      ),
                      _filterRow(
                        icon: Icons.movie_filter_rounded,
                        label: 'محتوا',
                        value: _optionLabel(_dubOptions, dub),
                        onTap: () => _pickOption(
                          title: 'محتوا',
                          options: _dubOptions,
                          current: dub,
                          onPick: (value) {
                            setState(() => dub = value);
                            unawaited(runAdvanced());
                          },
                        ),
                      ),
                      _filterRow(
                        icon: Icons.play_circle_outline_rounded,
                        label: 'وضعیت پخش',
                        value: _optionLabel(_stateOptions, stateSerie),
                        onTap: () => _pickOption(
                          title: 'وضعیت پخش',
                          options: _stateOptions,
                          current: stateSerie,
                          onPick: (value) {
                            setState(() => stateSerie = value);
                            unawaited(runAdvanced());
                          },
                        ),
                      ),
                      _filterRow(
                        icon: Icons.tag_rounded,
                        label: 'ژانرها',
                        value: genre?.name ?? 'مهم نیست',
                        onTap: _pickGenre,
                      ),
                      _filterRow(
                        icon: Icons.flag_rounded,
                        label: 'کشورها',
                        value: country?.name ?? 'مهم نیست',
                        onTap: _pickCountry,
                      ),
                      _filterRow(
                        icon: Icons.star_rounded,
                        label: 'امتیاز imdb',
                        value: _optionLabel(_imdbOptions, imdb),
                        onTap: () => _pickOption(
                          title: 'امتیاز imdb',
                          options: _imdbOptions,
                          current: imdb,
                          onPick: (value) {
                            setState(() => imdb = value);
                            unawaited(runAdvanced());
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_rounded,
                              size: 20,
                              color: MovieColors.muted,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('سال انتشار')),
                            SizedBox(
                              width: 84,
                              child: TextField(
                                controller: yearFromController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: 'از',
                                ),
                                onChanged: (_) => _onYearChanged(),
                                onSubmitted: (_) =>
                                    unawaited(runAdvanced()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 84,
                              child: TextField(
                                controller: yearToController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: 'تا',
                                ),
                                onChanged: (_) => _onYearChanged(),
                                onSubmitted: (_) =>
                                    unawaited(runAdvanced()),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _filterRow(
                        icon: Icons.sort_rounded,
                        label: 'ترتیب بر اساس',
                        value: _optionLabel(_sortOptions, sortBy),
                        onTap: () => _pickOption(
                          title: 'ترتیب بر اساس',
                          options: _sortOptions,
                          current: sortBy,
                          onPick: (value) {
                            setState(() => sortBy = value);
                            unawaited(runAdvanced());
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
          if (loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: MovieColors.coral),
                ),
              ),
            ),
          if (!loading && error == null && filtered.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: _EmptyState(
                  // Before any search ran, show a hint — never a bogus
                  // "nothing found" while the user is still typing.
                  icon: !_hasSearched
                      ? Icons.manage_search_rounded
                      : Icons.search_off_rounded,
                  message: !_hasSearched
                      ? 'نام را بنویس و «جست‌وجو کن»'
                      : 'نتیجه‌ای پیدا نشد',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid.builder(
                gridDelegate: _grid(context),
                itemCount:
                    filtered.length +
                    (_advMore &&
                            (advanced || controller.text.trim().length >= 2)
                        ? 1
                        : 0),
                itemBuilder: (_, i) {
                  if (i >= filtered.length) {
                    if (_advLoadingMore) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Center(
                      child: TextButton.icon(
                        onPressed: _loadMoreResults,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('بیشتر'),
                      ),
                    );
                  }
                  final tag = 'search-${filtered[i].id}';
                  return Pressable(
                    onTap: () => widget.onOpen(filtered[i], tag),
                    child: Hero(
                      tag: tag,
                      transitionOnUserGestures: true,
                      createRectTween: smoothHeroRectTween,
                      flightShuttleBuilder: portraitHeroFlightShuttle,
                      child: ContentArt(content: filtered[i]),
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
        ],
      ),
    );
  }

  Widget _filterRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 20, color: MovieColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(
              color: MovieColors.orange,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_left_rounded,
            size: 18,
            color: MovieColors.muted,
          ),
        ],
      ),
    ),
  );
}

/// Distinct accent per card so genres are visually distinguishable.
const _groupAccents = <Color>[
  Color(0xFFFF7A1A),
  Color(0xFF8D6BFF),
  Color(0xFF3FD8D4),
  Color(0xFFFF4F6D),
  Color(0xFF4ADE80),
  Color(0xFFFBBF24),
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
  Color(0xFF2DD4BF),
  Color(0xFFF87171),
  Color(0xFFA3E635),
  Color(0xFFE879F9),
];

class _GroupsPage extends StatefulWidget {
  const _GroupsPage({
    required this.api,
    required this.country,
    required this.onOpen,
  });
  final MovieApi api;
  final bool country;
  final OpenContent onOpen;
  @override
  State<_GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<_GroupsPage> {
  late Future<List<CatalogGroup>> future = widget.country
      ? widget.api.countriesWithContent()
      : widget.api.genres();

  Future<void> _reload() async {
    final next = widget.country
        ? widget.api.countriesWithContent()
        : widget.api.genres();
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {
      // The original future remains available to FutureBuilder's error UI.
    }
  }

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.country ? 'کشورها' : 'دسته‌بندی فیلم‌ها',
    child: FutureBuilder<List<CatalogGroup>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (widget.country) ...[
                  const SizedBox(height: 16),
                  const Text('در حال بررسی کشورهای دارای محتوا…'),
                ],
              ],
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(retry: _reload, error: snapshot.error);
        }
        final groups = snapshot.data!;
        if (groups.isEmpty) {
          return const _EmptyState(
            icon: Icons.flag_outlined,
            message: 'در حال حاضر کشوری با محتوای قابل نمایش نیست',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            childAspectRatio: widget.country ? .92 : 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: groups.length,
          itemBuilder: (_, i) {
            final group = groups[i];
            final accent = _groupAccents[i % _groupAccents.length];
            return Pressable(
              onTap: () => Navigator.push<void>(
                context,
                slideUpRoute(
                  _GroupResultsPage(
                    api: widget.api,
                    group: group,
                    country: widget.country,
                    onOpen: widget.onOpen,
                  ),
                ),
              ),
              child: widget.country
                  ? _CountryCard(group: group)
                  : _GenreCard(group: group, accent: accent),
            );
          },
        );
      },
    ),
  );
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({required this.group, required this.accent});
  final CatalogGroup group;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [accent.withValues(alpha: .26), MovieColors.surfaceHigh],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: accent.withValues(alpha: .38)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.auto_awesome_rounded, color: accent, size: 24),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            group.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.group});
  final CatalogGroup group;

  @override
  Widget build(BuildContext context) {
    final flag = countryFlagAsset(group.name);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MovieColors.surfaceHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(21),
              ),
              child: flag == null
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [MovieColors.surface, Color(0xFF232838)],
                        ),
                      ),
                      child: Icon(
                        Icons.public_rounded,
                        color: MovieColors.cyan,
                        size: 44,
                      ),
                    )
                  : Image.asset(
                      flag,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [MovieColors.surface, Color(0xFF232838)],
                          ),
                        ),
                        child: Icon(
                          Icons.public_rounded,
                          color: MovieColors.cyan,
                          size: 44,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(
              group.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupResultsPage extends StatefulWidget {
  const _GroupResultsPage({
    required this.api,
    required this.group,
    required this.country,
    required this.onOpen,
  });
  final MovieApi api;
  final CatalogGroup group;
  final bool country;
  final OpenContent onOpen;
  @override
  State<_GroupResultsPage> createState() => _GroupResultsPageState();
}

/// گرید عنوان‌ها با صفحه‌بندی خودکار: صفحه اول، اسکرول به انتها صفحه‌های
/// بعدی را می‌آورد و اگر همه موارد در نما جا شوند خودکار ادامه می‌دهد تا
/// فهرست نصفه نماند.
class _PaginatedGridPage extends StatefulWidget {
  const _PaginatedGridPage({
    required this.title,
    required this.heroPrefix,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.onOpen,
    required this.loadPage,
    this.api,
    this.filterGenre,
    this.filterCountry,
    this.filterWithinList = false,
  });
  final String title;
  final String heroPrefix;
  final IconData emptyIcon;
  final String emptyMessage;
  final OpenContent onOpen;
  final Future<List<MovieContent>> Function(int page) loadPage;
  final MovieApi? api;
  final CatalogGroup? filterGenre;
  final CatalogGroup? filterCountry;
  final bool filterWithinList;
  @override
  State<_PaginatedGridPage> createState() => _PaginatedGridPageState();
}

class _PaginatedGridPageState extends State<_PaginatedGridPage> {
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
      if (_scroll.position.extentAfter < 450) _load();
    });
    _load();
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
        _load();
      }
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!_more && !reset)) return;
    if (reset) {
      _page = 0;
      _more = true;
      _items.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.loadPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        final seen = {for (final item in _items) item.id};
        var added = 0;
        for (final item in next) {
          if (seen.add(item.id)) {
            _items.add(item);
            added++;
          }
        }
        _more = next.isNotEmpty && added > 0;
      });
      _fillIfNeeded();
    } on MovieApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.title,
    child: Column(
      children: [
        if (widget.api != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: _FilterAction(
                api: widget.api!,
                onOpen: widget.onOpen,
                title: widget.title,
                genre: widget.filterGenre,
                country: widget.filterCountry,
                sourcePage: widget.filterWithinList ? widget.loadPage : null,
              ),
            ),
          ),
        Expanded(
          child: _items.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty && _error != null
              ? _ErrorState(retry: () => _load(reset: true), error: _error)
              : CustomScrollView(
                  controller: _scroll,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    if (_items.isEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 300,
                          child: _EmptyState(
                            icon: widget.emptyIcon,
                            message: widget.emptyMessage,
                          ),
                        ),
                      )
                    else
                      _ContentGrid(
                        items: _items,
                        onOpen: widget.onOpen,
                        heroPrefix: widget.heroPrefix,
                      ),
                    if (_loading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else if (_error != null && _items.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('تلاش دوباره'),
                          ),
                        ),
                      )
                    else if (!_more && _items.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: Center(
                            child: Text(
                              'همه عنوان‌ها نمایش داده شد',
                              style: TextStyle(color: MovieColors.muted),
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _GroupResultsPageState extends State<_GroupResultsPage> {
  @override
  Widget build(BuildContext context) => _PaginatedGridPage(
    title: widget.group.name,
    heroPrefix: 'group-',
    emptyIcon: Icons.movie_filter_outlined,
    emptyMessage: 'عنوانی در این بخش ثبت نشده است',
    onOpen: widget.onOpen,
    api: widget.api,
    filterGenre: widget.country ? null : widget.group,
    filterCountry: widget.country ? widget.group : null,
    loadPage: (page) => widget.api.catalogByGroup(
      group: widget.group,
      country: widget.country,
      page: page,
    ),
  );
}

class _CollectionTitlesPage extends StatefulWidget {
  const _CollectionTitlesPage({
    required this.api,
    required this.collection,
    required this.onOpen,
  });
  final MovieApi api;
  final MovieCollection collection;
  final OpenContent onOpen;
  @override
  State<_CollectionTitlesPage> createState() => _CollectionTitlesPageState();
}

class _CollectionTitlesPageState extends State<_CollectionTitlesPage> {
  @override
  Widget build(BuildContext context) => _PaginatedGridPage(
    title: widget.collection.title,
    heroPrefix: 'collection-${widget.collection.id}-',
    emptyIcon: Icons.collections_outlined,
    emptyMessage: 'عنوانی در این مجموعه ثبت نشده است',
    onOpen: widget.onOpen,
    api: widget.api,
    filterWithinList: true,
    loadPage: (page) =>
        widget.api.collectionTitles(widget.collection, page: page),
  );
}

class _AllCollectionsPage extends StatefulWidget {
  const _AllCollectionsPage({
    required this.api,
    required this.initialCollections,
    required this.onOpenCollection,
  });

  final MovieApi api;
  final List<MovieCollection> initialCollections;
  final ValueChanged<MovieCollection> onOpenCollection;

  @override
  State<_AllCollectionsPage> createState() => _AllCollectionsPageState();
}

class _AllCollectionsPageState extends State<_AllCollectionsPage> {
  late final List<MovieCollection> _collections = List.of(widget.initialCollections);
  late final Set<String> _seen = {for (final c in widget.initialCollections) c.id};
  final _scroll = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.collections(page: _page);
      if (!mounted) return;
      setState(() {
        _page++;
        for (final item in next) {
          if (_seen.add(item.id)) _collections.add(item);
        }
        _more = next.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('همه مجموعه‌ها'),
      centerTitle: false,
    ),
    body: _collections.isEmpty && _loading
        ? const Center(child: CircularProgressIndicator())
        : _collections.isEmpty && _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: MovieColors.muted),
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: MovieColors.muted)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _loadMore,
                  child: const Text('تلاش مجدد'),
                ),
              ],
            ),
          )
        : GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              childAspectRatio: 0.72,
              crossAxisSpacing: 14,
              mainAxisSpacing: 16,
            ),
            itemCount: _collections.length + (_loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _collections.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final collection = _collections[index];
              return Pressable(
                onTap: () => widget.onOpenCollection(collection),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: collection.imageUrl == null
                            ? const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      MovieColors.surface,
                                      Color(0xFF232838),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.collections_rounded,
                                  color: MovieColors.cyan,
                                  size: 40,
                                ),
                              )
                            : Image.network(
                                collection.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: MovieColors.surface,
                                  ),
                                  child: Icon(
                                    Icons.collections_rounded,
                                    color: MovieColors.cyan,
                                    size: 40,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      collection.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            },
          ),
  );
}

class _CategoryTitlesPage extends StatefulWidget {
  const _CategoryTitlesPage({
    required this.api,
    required this.banner,
    required this.onOpen,
  });
  final MovieApi api;
  final MovieBanner banner;
  final OpenContent onOpen;
  @override
  State<_CategoryTitlesPage> createState() => _CategoryTitlesPageState();
}

class _CategoryTitlesPageState extends State<_CategoryTitlesPage> {
  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.banner.title,
    child: DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'فیلم‌ها'),
              Tab(text: 'سریال‌ها'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CategoryGrid(
                  api: widget.api,
                  banner: widget.banner,
                  isMovie: 'movie',
                  heroPrefix: 'category-${widget.banner.category}-movie-',
                  onOpen: widget.onOpen,
                ),
                _CategoryGrid(
                  api: widget.api,
                  banner: widget.banner,
                  isMovie: 'serie',
                  heroPrefix: 'category-${widget.banner.category}-serie-',
                  onOpen: widget.onOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CategoryGrid extends StatefulWidget {
  const _CategoryGrid({
    required this.api,
    required this.banner,
    required this.isMovie,
    required this.heroPrefix,
    required this.onOpen,
  });
  final MovieApi api;
  final MovieBanner banner;
  final String isMovie;
  final String heroPrefix;
  final OpenContent onOpen;
  @override
  State<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<_CategoryGrid>
    with AutomaticKeepAliveClientMixin {
  final _items = <MovieContent>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _load();
    });
    _load();
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
        _load();
      }
    });
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.titlesByCategory(
        widget.banner,
        isMovie: widget.isMovie,
        page: _page + 1,
      );
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
  Widget build(BuildContext context) {
    super.build(context);
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return _ErrorState(retry: _load, error: _error);
    }
    if (_items.isEmpty) {
      return const _EmptyState(
        icon: Icons.movie_filter_outlined,
        message: 'عنوانی در این بخش ثبت نشده است',
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: _FilterAction(
              api: widget.api,
              onOpen: widget.onOpen,
              title: widget.banner.title,
              type: widget.isMovie,
              sourcePage: (page) => widget.api.titlesByCategory(
                widget.banner,
                isMovie: widget.isMovie,
                page: page,
              ),
            ),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverGrid.builder(
                  gridDelegate: _grid(context),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final tag = '${widget.heroPrefix}${_items[i].id}';
                    return Pressable(
                      onTap: () => widget.onOpen(_items[i], tag),
                      child: Hero(
                        tag: tag,
                        transitionOnUserGestures: true,
                        createRectTween: smoothHeroRectTween,
                        flightShuttleBuilder: portraitHeroFlightShuttle,
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
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تلاش دوباره'),
                    ),
                  ),
                )
              else if (!_more)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Center(
                      child: Text(
                        'همه عنوان‌ها نمایش داده شد',
                        style: TextStyle(color: MovieColors.muted),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TagResultsPage extends StatefulWidget {
  const _TagResultsPage({
    required this.api,
    required this.tag,
    required this.onOpen,
  });
  final MovieApi api;
  final MovieTag tag;
  final OpenContent onOpen;
  @override
  State<_TagResultsPage> createState() => _TagResultsPageState();
}

class _TagResultsPageState extends State<_TagResultsPage> {
  @override
  Widget build(BuildContext context) => _PaginatedGridPage(
    title: widget.tag.title,
    heroPrefix: 'tag-${widget.tag.id}-',
    emptyIcon: Icons.tag_outlined,
    emptyMessage: 'عنوانی با این موضوع ثبت نشده است',
    onOpen: widget.onOpen,
    api: widget.api,
    filterWithinList: true,
    loadPage: (page) => widget.api.search(widget.tag.title, page: page),
  );
}

class _SavedPage extends StatefulWidget {
  const _SavedPage({
    required this.api,
    required this.title,
    required this.emptyText,
    required this.emptyIcon,
    required this.itemsProvider,
    required this.onOpen,
    required this.onClear,
    this.clearTooltip = 'پاک کردن تاریخچه',
    this.clearTitle = 'پاک کردن تاریخچه؟',
    this.clearMessage = 'فهرست عنوان‌های بازدیدشده پاک می‌شود.',
  });
  final String title;
  final MovieApi api;
  final String emptyText;
  final IconData emptyIcon;

  /// Fresh snapshot on every build/return: the page must reflect favorite
  /// removals made in a pushed detail route instead of a one-time list.
  final List<MovieContent> Function() itemsProvider;
  final OpenContent onOpen;
  final Future<void> Function() onClear;
  final String clearTooltip;
  final String clearTitle;
  final String clearMessage;

  @override
  State<_SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<_SavedPage> {
  late List<MovieContent> _items = widget.itemsProvider();

  void _refresh() {
    if (!mounted) return;
    setState(() => _items = widget.itemsProvider());
  }

  Future<void> _openAndRefresh(MovieContent item, String tag) async {
    await widget.onOpen(item, tag);
    _refresh();
  }

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.title,
    actions: [
      if (_items.isNotEmpty)
        IconButton(
          tooltip: widget.clearTooltip,
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(widget.clearTitle),
                content: Text(widget.clearMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('انصراف'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('پاک شود'),
                  ),
                ],
              ),
            );
            if (yes == true) {
              await widget.onClear();
              _refresh();
              if (context.mounted) Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
    ],
    child: _SavedBody(
      api: widget.api,
      title: '',
      emptyText: widget.emptyText,
      emptyIcon: widget.emptyIcon,
      items: _items,
      onOpen: _openAndRefresh,
      heroPrefix: 'hist-',
    ),
  );
}

class _SavedBody extends StatelessWidget {
  const _SavedBody({
    required this.api,
    required this.title,
    required this.emptyText,
    required this.emptyIcon,
    required this.items,
    required this.onOpen,
    required this.heroPrefix,
  });
  final String title;
  final MovieApi api;
  final String emptyText;
  final IconData emptyIcon;
  final List<MovieContent> items;
  final OpenContent onOpen;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _EmptyState(icon: emptyIcon, message: emptyText);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _PageTitle(
            title,
            action: _FilterAction(
              api: api,
              onOpen: onOpen,
              title: title.isEmpty ? 'فهرست من' : title,
              sourcePage: (page) async => page == 1 ? items : const [],
            ),
          ),
        ),
        _ContentGrid(items: items, onOpen: onOpen, heroPrefix: heroPrefix),
        SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
      ],
    );
  }
}

class _InnerScaffold extends StatelessWidget {
  const _InnerScaffold({
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: AmbientBackground(child: child),
  );
}

class _ContentGrid extends StatelessWidget {
  const _ContentGrid({
    required this.items,
    required this.onOpen,
    required this.heroPrefix,
  });
  final List<MovieContent> items;
  final OpenContent onOpen;
  final String heroPrefix;
  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverGrid.builder(
      gridDelegate: _grid(context),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final tag = '$heroPrefix${items[i].id}';
        return Pressable(
          onTap: () => onOpen(items[i], tag),
          child: Hero(
            tag: tag,
            transitionOnUserGestures: true,
            createRectTween: smoothHeroRectTween,
            flightShuttleBuilder: portraitHeroFlightShuttle,
            child: ContentArt(content: items[i]),
          ),
        );
      },
    ),
  );
}

SliverGridDelegateWithFixedCrossAxisCount _grid(BuildContext context) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
      childAspectRatio: .67,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );

/// افقیِ قابل مرور با فلش‌های چپ/راست در دسکتاپ و درگ با موس؛ برای
/// ردیف‌های بنر، مجموعه و چیپ‌ها که تعدادشان ثابت است.
class _HorizontalRail extends StatefulWidget {
  const _HorizontalRail({
    required this.height,
    required this.children,
    this.gap = 12,
  });
  final double height;
  final List<Widget> children;
  final double gap;
  @override
  State<_HorizontalRail> createState() => _HorizontalRailState();
}

class _HorizontalRailState extends State<_HorizontalRail> {
  final _controller = ScrollController();

  void _page(bool forward) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels + (forward ? 1 : -1) * position.viewportDimension * .8)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final arrows = isLargeScreenDevice && widget.children.isNotEmpty;
    Widget row = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(horizontal: arrows ? 52 : 16),
      child: Row(
        children: [
          for (var i = 0; i < widget.children.length; i++) ...[
            if (i > 0) SizedBox(width: widget.gap),
            widget.children[i],
          ],
        ],
      ),
    );
    row = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          ...ScrollConfiguration.of(context).dragDevices,
          PointerDeviceKind.mouse,
        },
        scrollbars: false,
      ),
      child: row,
    );
    if (!arrows) return SizedBox(height: widget.height, child: row);
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(child: row),
          for (final left in [true, false])
            Positioned(
              left: left ? 4 : null,
              right: left ? null : 4,
              top: widget.height / 2 - 20,
              child: IconButton.filledTonal(
                tooltip: left == rtl ? 'موارد بعدی' : 'موارد قبلی',
                onPressed: () => _page(left == rtl),
                icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
              ),
            ),
        ],
      ),
    );
  }
}

/// ردیف «آخرین فیلم‌ها/سریال‌ها» با صفحه‌بندی: موارد ویترین اول می‌آیند و
/// با اسکرول به انتها، صفحه‌های بعدی فهرست اضافه می‌شود تا ردیف خالی نماند.
class _PaginatedPosterRow extends StatefulWidget {
  const _PaginatedPosterRow({
    required this.api,
    required this.kind,
    required this.initial,
    required this.onOpen,
    required this.heroPrefix,
  });
  final MovieApi api;
  final ContentKind kind;
  final List<MovieContent> initial;
  final OpenContent onOpen;
  final String heroPrefix;
  @override
  State<_PaginatedPosterRow> createState() => _PaginatedPosterRowState();
}

class _PaginatedPosterRowState extends State<_PaginatedPosterRow> {
  late final List<MovieContent> _items = List.of(widget.initial);
  late final Set<String> _seen = {for (final item in widget.initial) item.id};
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _more = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
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
    if (_loading || !_more || !mounted) return;
    setState(() => _loading = true);
    try {
      final next = await widget.api.catalog(kind: widget.kind, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        for (final item in next) {
          if (_seen.add(item.id)) _items.add(item);
        }
        _more = next.isNotEmpty;
      });
      _fillIfNeeded();
    } on MovieApiException {
      // خطای گذرا؛ اسکرول بعدی دوباره تلاش می‌کند.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notice) {
          if (notice.metrics.extentAfter < 600) _loadMore();
          return false;
        },
        child: BrowsableShelf(
          controller: _scroll,
          showNavigation: isLargeScreenDevice,
          itemCount: _items.length + (_more ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= _items.length) {
              return const SizedBox(
                width: 148,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }
            final tag = '${widget.heroPrefix}${_items[i].id}';
            return Pressable(
              onTap: () => widget.onOpen(_items[i], tag),
              child: Hero(
                tag: tag,
                transitionOnUserGestures: true,
                createRectTween: smoothHeroRectTween,
                flightShuttleBuilder: portraitHeroFlightShuttle,
                child: SizedBox(
                  width: 148,
                  child: ContentArt(content: _items[i]),
                ),
              ),
            );
          },
        ),
      );
}

/// Home shelf header: title on the right,
/// «مشاهده همه» facing it on the left (RTL row order handles the sides).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.onAll});
  final String title;
  final VoidCallback onAll;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton.icon(
          onPressed: onAll,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('مشاهده همه'),
        ),
      ],
    ),
  );
}

class _PlainSectionTitle extends StatelessWidget {
  const _PlainSectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

String _fmtContinuePosition(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Home «ادامه تماشا» shelf: the last playback exit with its exact position
/// and a progress bar. Tapping asks the shared confirmation popup (title +
/// minute) and resumes directly. Hidden when there is no resumable exit.
class _ContinueWatchSection extends StatelessWidget {
  const _ContinueWatchSection({required this.last, required this.onPlayed});
  final LastWatch last;
  final Future<void> Function() onPlayed;

  @override
  Widget build(BuildContext context) {
    final ratio = last.durationMs > 0
        ? (last.positionMs / last.durationMs).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Pressable(
        onTap: () async {
          await askAndResumeLastWatch(context, last);
          await onPlayed();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MovieColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: MovieColors.orange.withValues(alpha: .35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: MovieColors.orange.withValues(alpha: .16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: MovieColors.orange,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ادامه تماشا',
                            style: TextStyle(
                              color: MovieColors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            last.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            last.episodeName.isNotEmpty
                                ? '${episodeDisplayName(last.episodeName)} · دقیقه ${_fmtContinuePosition(last.position)}'
                                : 'دقیقه ${_fmtContinuePosition(last.position)}',
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
                    const Icon(
                      Icons.chevron_left_rounded,
                      color: MovieColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation(
                      MovieColors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full grid of one home shelf («مشاهده همه» target). Shows the shelf's
/// loaded items with distinct Hero tags so the shelf row beneath stays intact.
class _SectionAllPage extends StatefulWidget {
  const _SectionAllPage({
    required this.api,
    required this.section,
    required this.kind,
    required this.onOpen,
  });
  final MovieApi api;
  final HomeSection section;
  final ContentKind kind;
  final OpenContent onOpen;
  @override
  State<_SectionAllPage> createState() => _SectionAllPageState();
}

class _SectionAllPageState extends State<_SectionAllPage> {
  late final List<MovieContent> _items = List.of(widget.section.items);
  late final Set<String> _seen = {
    for (final item in widget.section.items) item.id,
  };
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.catalog(kind: widget.kind, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        for (final item in next) {
          if (_seen.add(item.id)) _items.add(item);
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

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.section.title,
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: _FilterAction(
              api: widget.api,
              onOpen: widget.onOpen,
              title: widget.section.title,
              type: widget.kind == ContentKind.movie ? 'movie' : 'serie',
            ),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              _ContentGrid(
                items: _items,
                onOpen: widget.onOpen,
                heroPrefix: 'all-${widget.section.id}-',
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: TextButton(
                        onPressed: _loadMore,
                        child: Text(_error!),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.title, {this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        ?action,
      ],
    ),
  );
}

class _FilterAction extends StatelessWidget {
  const _FilterAction({
    required this.api,
    required this.onOpen,
    required this.title,
    this.type = '',
    this.genre,
    this.country,
    this.sourcePage,
  });
  final MovieApi api;
  final OpenContent onOpen;
  final String title;
  final String type;
  final CatalogGroup? genre;
  final CatalogGroup? country;
  final Future<List<MovieContent>> Function(int page)? sourcePage;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => Navigator.push<void>(
      context,
      slideUpRoute(
        _SearchPage(
          api: api,
          onOpen: onOpen,
          title: 'فیلتر $title',
          initialType: type,
          initialGenre: genre,
          initialCountry: country,
          sourcePage: sourcePage,
        ),
      ),
    ),
    icon: const Icon(Icons.tune_rounded, size: 19),
    label: const Text('فیلتر'),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 60, color: MovieColors.muted),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: MovieColors.muted)),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.retry, this.error});
  final FutureOr<void> Function() retry;
  final Object? error;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 56, color: MovieColors.muted),
        const SizedBox(height: 12),
        const Text('دریافت اطلاعات انجام نشد'),
        if (error is MovieApiException)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              (error! as MovieApiException).message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MovieColors.muted),
            ),
          ),
        const SizedBox(height: 10),
        FilledButton.tonal(onPressed: retry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}
