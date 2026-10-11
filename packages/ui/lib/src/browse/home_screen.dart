import '../l10n_gen/app_strings.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../components/ambient_background.dart';
import '../components/artwork.dart';
import '../focus/focus_memory.dart';
import '../navigation/page_entry_focus.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import '../states/empty_view.dart';
import '../states/error_view.dart';
import 'hero_backdrop.dart';
import 'home_view_model.dart';
import 'media_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.viewModel,
    this.progress = const <String, PlaybackProgress>{},
    this.onRowBuild,
    this.onItemTap,
    this.onSeeAll,
    this.onRetry,
    this.logger,
    super.key,
  });

  final HomeViewModel viewModel;
  final Map<String, PlaybackProgress> progress;
  final ValueChanged<String>? onRowBuild;
  final ValueChanged<MediaItem>? onItemTap;
  final ValueChanged<HomeRow>? onSeeAll;
  final VoidCallback? onRetry;
  final AppLogger? logger;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Index of the first/second "deferred" shelf within `viewModel.rows` — the
/// fakeable 2s/3s staged-reveal gate from the Phase file's step 7. Matches
/// Rivulet's staging of secondary shelves behind the always-ready hero +
/// primary rows.
const int _firstDeferredRowIndex = 3;
const int _secondDeferredRowIndex = 4;

/// Decoded size of one 3840x2160 RGBA picture, the largest TMDB `original`
/// backdrop: headroom reserved before the first hero picture's real size is
/// known (default image cache is 100 MiB, one such picture is ~31.6 MiB).
const int _largestRgbaImageBytes = 3840 * 2160 * 4;

class _HomeScreenState extends State<HomeScreen> {
  final FocusMemory _memory = FocusMemory();
  Timer? _firstDeferredTimer;
  Timer? _secondDeferredTimer;
  bool _firstDeferredRevealed = false;
  bool _secondDeferredRevealed = false;

  // Part B: secondary-action gate + hero collapse/Back-staging focus plumbing.
  //
  // `_heroFocusScope` wraps the hero button row; its `hasFocus` is true
  // whenever Play/Watchlist/Info/Next holds focus (`FocusScopeNode.hasFocus`
  // is true for the scope itself or any descendant — see Flutter's
  // `focus_manager.dart` docs on `FocusScopeNode`). `_firstRowFocusScope`
  // wraps the first shelf row only, matching
  // `PlexHomeViewController.swift:5453-5460`'s "the first row under the hero
  // collapses the hero ... deeper rows [do something else]" — only the first
  // row triggers hero collapse.
  final FocusScopeNode _heroFocusScope = FocusScopeNode(debugLabel: 'hero');
  final FocusScopeNode _firstRowFocusScope = FocusScopeNode(
    debugLabel: 'first-shelf-row',
  );
  final FocusNode _heroPlayFocusNode = FocusNode(debugLabel: 'hero-play');
  final FocusNode _heroDetailsFocusNode = FocusNode(debugLabel: 'hero-details');
  PageEntry? _entry;

  /// True once the first content frame has been built: only rows that mount
  /// before it play the first-load entry animation (DESIGN_SPEC §5.2).
  bool _entered = false;

  /// The hero action focus should land on when focus returns to the hero
  /// (Back from the first row, or the scope regaining focus generally) —
  /// `HeroButtonRowView.swift:143-151`'s `preferredFocusEnvironments`
  /// defaults to Play, but once a different hero button has been focused
  /// this remembers it instead, same idea as `FocusMemory` for shelves.
  FocusNode? _lastHeroFocusNode;

  /// True once focus has entered the hero at least once while it currently
  /// still lives somewhere in the hero. Gates the secondary hero buttons:
  /// `HeroButtonRowView.swift:124,153-157` — "while focus lives outside the
  /// hero, the secondary buttons are removed from focus candidacy and Play
  /// is the only possible landing. The hero overlay re-enables them once
  /// focus is inside." Play itself is never gated (`heroPlayFocusNode`
  /// always has `canRequestFocus: true`).
  bool _heroFocusEntered = false;

  /// True while focus lives in the first shelf row — drives the hero
  /// collapse (`PlexHomeViewController.swift:5453` comment: "the first row
  /// under the hero collapses the hero to a FIXED, hero-derived band").
  bool _firstRowFocused = false;

  /// True once the hero has held focus at least once in this session. Guards
  /// the collapse below against the pre-existing "Continue watching"
  /// autofocus-on-mount workaround (`MediaRow`'s
  /// `autofocus: index == 0 && title == 'Continue watching'`, Part A):
  /// that autofocus lands directly in the first shelf row without the hero
  /// ever holding focus, and it must not be read as "focus entered the
  /// first shelf" — the hero starts expanded, exactly as before Part B.
  /// Collapse only applies once a real hero-to-shelf transition has
  /// happened.
  bool _heroEverFocused = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    _armDeferredSections();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheHero();
    });
    _entry = PageEntryFocus.register(context, _heroPlayFocusNode);
    _heroFocusScope.addListener(_onHeroFocusScopeChanged);
    _firstRowFocusScope.addListener(_onFirstRowFocusScopeChanged);
    for (final node in <FocusNode>[_heroPlayFocusNode, _heroDetailsFocusNode]) {
      node.addListener(() {
        if (node.hasFocus) _lastHeroFocusNode = node;
      });
    }
  }

  /// Fetches and decodes every hero item's picture (the same provider the
  /// hero paints with, so the image-cache key matches), first item first, so
  /// paging the hero never waits on the network. A failed picture is logged
  /// and left to the hero's own fallback; there is no retry.
  Future<void> _precacheHero() async {
    final model = widget.viewModel;
    if (model.loadState != HomeLoadState.content) return;
    final resolve = ArtworkResolverScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = PaintingBinding.instance.imageCache;
    var largest = _largestRgbaImageBytes;
    for (final item in model.heroItems) {
      final url = model.heroArtwork[item.id] ?? item.artwork;
      if (url == null) continue;
      // Keep room for the rest of the set so earlier pictures are not
      // evicted by later ones; only ever raises the limit.
      final needed = cache.currentSizeBytes + largest;
      if (cache.maximumSizeBytes < needed) cache.maximumSizeBytes = needed;
      final before = cache.currentSizeBytes;
      await precacheImage(
        ArtworkView.sized(resolve(url.toString()), width, dpr),
        context,
        onError: (error, stack) => widget.logger?.warn(
          'Hero artwork failed to load: $url',
          error: error,
          stack: stack,
        ),
      );
      if (!mounted || widget.viewModel != model) return;
      final decoded = cache.currentSizeBytes - before;
      if (decoded > 0) largest = decoded;
    }
  }

  void _onHeroFocusScopeChanged() {
    if (!mounted) return;
    var entered = _heroFocusScope.hasFocus;
    // TV: focus that leaves for the menu panel (outside this page) keeps the
    // hero reachable, so closing the panel can put focus back on it.
    final away = FocusManager.instance.primaryFocus?.context;
    if (!entered &&
        _heroFocusEntered &&
        (AdaptiveBehavior.of(context).formFactor == FormFactor.tv) &&
        away != null &&
        away.findAncestorStateOfType<_HomeScreenState>() != this) {
      entered = true;
    }
    if (entered && !_heroEverFocused) _heroEverFocused = true;
    if (entered == _heroFocusEntered) return;
    setState(() => _heroFocusEntered = entered);
  }

  void _onFirstRowFocusScopeChanged() {
    if (!mounted) return;
    // Gated on `_heroEverFocused` — see its doc comment.
    final focused = _firstRowFocusScope.hasFocus && _heroEverFocused;
    if (focused == _firstRowFocused) return;
    setState(() => _firstRowFocused = focused);
  }

  /// Back-staging: pressing Back while focus is in the first shelf row
  /// returns focus to the hero (the previously-focused action, defaulting
  /// to Play) instead of leaving the screen. A second Back — focus already
  /// in the hero — is left unhandled so it propagates to the shell, per the
  /// Phase file step 6: "Back below the first row first moves to the top
  /// row; the next Back goes to the shell."
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    // Android remote Back also sends a pop route; only that path handles it.
    final isBack =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace;
    // Up from the first row goes to the hero's buttons, which the collapsed
    // hero has moved out of the traversal geometry (DESIGN_SPEC
    // §6.4 rule 4).
    if (!_firstRowFocused || !(isBack || up)) {
      return KeyEventResult.ignored;
    }
    // The collapsed hero is out of focus traversal; expand it, then focus.
    setState(() {
      _firstRowFocused = false;
      _heroFocusEntered = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Up lands on Play (DESIGN_SPEC §6.4 rule 4); Back returns to the
      // action focus last had.
      final target = up
          ? _heroPlayFocusNode
          : (_lastHeroFocusNode ?? _heroPlayFocusNode);
      FocusTraversalPolicy.defaultTraversalRequestFocusCallback(target);
    });
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      // Home session changed identity: cancel the old session's timers and
      // re-arm fresh ones against the new session, rather than let a stale
      // timer reveal a section that belongs to a since-replaced viewModel.
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
      _cancelDeferredTimers();
      _firstDeferredRevealed = false;
      _secondDeferredRevealed = false;
      _armDeferredSections();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheHero();
      });
    }
  }

  void _armDeferredSections() {
    if (widget.viewModel.firstDeferredSectionReady) {
      _firstDeferredRevealed = true;
    } else {
      _firstDeferredTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _firstDeferredRevealed = true);
      });
    }
    if (widget.viewModel.secondDeferredSectionReady) {
      _secondDeferredRevealed = true;
    } else {
      _secondDeferredTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _secondDeferredRevealed = true);
      });
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    var changed = !identical(_shownRows, widget.viewModel.rows);
    if (!_firstDeferredRevealed && widget.viewModel.firstDeferredSectionReady) {
      _firstDeferredTimer?.cancel();
      _firstDeferredTimer = null;
      _firstDeferredRevealed = true;
      changed = true;
    }
    if (!_secondDeferredRevealed &&
        widget.viewModel.secondDeferredSectionReady) {
      _secondDeferredTimer?.cancel();
      _secondDeferredTimer = null;
      _secondDeferredRevealed = true;
      changed = true;
    }
    if (changed) setState(() {});
  }

  /// The rows list last built, to notice an in-place [HomeViewModel.replaceRows].
  late List<HomeRow> _shownRows = widget.viewModel.rows;

  void _cancelDeferredTimers() {
    _firstDeferredTimer?.cancel();
    _secondDeferredTimer?.cancel();
    _firstDeferredTimer = null;
    _secondDeferredTimer = null;
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _cancelDeferredTimers();
    _entry?.release(_heroPlayFocusNode);
    _heroFocusScope.removeListener(_onHeroFocusScopeChanged);
    _firstRowFocusScope.removeListener(_onFirstRowFocusScopeChanged);
    _heroFocusScope.dispose();
    _firstRowFocusScope.dispose();
    _heroPlayFocusNode.dispose();
    _heroDetailsFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.viewModel.loadState) {
      case HomeLoadState.loading:
        return _page(context, loading: true);
      case HomeLoadState.error:
        return ErrorView(
          key: const ValueKey<String>('home-error'),
          failure: widget.viewModel.failure!,
          onRetry: widget.onRetry,
          fullScreen: true,
        );
      case HomeLoadState.empty:
        return EmptyView(
          key: const ValueKey<String>('home-empty'),
          headline: AppStrings.of(context).state_emptyTitle,
        );
      case HomeLoadState.content:
        break;
    }
    _shownRows = widget.viewModel.rows;
    if (widget.viewModel.rows.isEmpty) {
      return EmptyView(
        key: const ValueKey<String>('home-empty'),
        headline: AppStrings.of(context).state_emptyTitle,
      );
    }
    return _page(context, loading: false);
  }

  /// The real Home layout; while [loading] it is fed placeholder rows and
  /// drawn as bones, so the content replaces it with no layout shift
  /// (DESIGN_SPEC §9.10).
  Widget _page(BuildContext context, {required bool loading}) {
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final tv = formFactor == FormFactor.tv;
    final colors = RivuletTokens.of(context).colors;
    final still = tv || MediaQuery.disableAnimationsOf(context);
    final model = widget.viewModel;
    final rows = loading ? _placeholderRows : model.rows;
    // Rows that mount in the first content frame animate in; later ones
    // (deferred rows, a refreshed list) appear at once.
    final play = !loading && !_entered && !still;
    if (!loading && !_entered) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _entered = true);
    }
    final firstVisible = rows.indexWhere((row) => row.items.isNotEmpty);
    final children = <Widget>[
      ListenableBuilder(
        listenable: model,
        builder: (_, _) => loading ? _skeletonHero() : _hero(context),
      ),
      for (var index = 0; index < rows.length; index++)
        // A row with nothing in it is not drawn.
        if (rows[index].items.isNotEmpty &&
            (loading ||
                ((index != _firstDeferredRowIndex || _firstDeferredRevealed) &&
                    (index != _secondDeferredRowIndex ||
                        _secondDeferredRevealed))))
          _RowEntry(
            key: ValueKey<String>(
              loading ? 'skeleton-row-$index' : 'entry-${rows[index].title}',
            ),
            index: index,
            play: play,
            child: Padding(
              padding: EdgeInsets.only(top: RivuletSpacing.rowGap(formFactor)),
              child: _buildRow(
                rows[index],
                index,
                loading: loading,
                first: index == firstVisible,
              ),
            ),
          ),
      SizedBox(height: RivuletSpacing.rowGap(formFactor)),
    ];
    return Focus(
      canRequestFocus: false,
      // Back-staging key handler — see `_onKeyEvent`. Wraps the whole
      // screen so it sits on every focused descendant's ancestor chain
      // without needing focus itself (`Focus.onKeyEvent` is consulted for
      // any key event bubbling up from a focused child).
      onKeyEvent: _onKeyEvent,
      child: AmbientBackground(
        key: const ValueKey<String>('home-screen'),
        child: ExcludeFocus(
          excluding: loading,
          child: Skeletonizer(
            enabled: loading,
            effect: still
                ? SolidColorEffect(color: colors.tintFill)
                : PulseEffect(
                    from: colors.tintFill,
                    to: colors.tintFillHover,
                    duration: const Duration(milliseconds: 900),
                  ),
            enableSwitchAnimation: !still,
            switchAnimationConfig: const SwitchAnimationConfig(
              duration: RivuletMotion.base,
              switchInCurve: RivuletMotion.easeOut,
              switchOutCurve: RivuletMotion.easeOut,
            ),
            child: ListView(padding: EdgeInsets.zero, children: children),
          ),
        ),
      ),
    );
  }

  Widget _skeletonHero() => const HeroBackdrop(
    item: MediaItem(
      id: 'skeleton-hero',
      title: _skeletonHeroTitle,
      kind: MediaKind.movie,
      year: 2024,
      duration: Duration(hours: 1, minutes: 52),
    ),
  );

  Widget _hero(BuildContext context) {
    final model = widget.viewModel;
    // Page dots track the curated, stable `heroItems` list (capped at
    // `heroItemCap`), not a raw row — see HomeViewModel.
    final heroItems = model.heroItems;
    final heroIndex = model.hero == null ? 0 : heroItems.indexOf(model.hero!);
    final currentIndex = heroIndex < 0 ? 0 : heroIndex;
    final remote = (AdaptiveBehavior.of(context).formFactor == FormFactor.tv);
    final hidden = remote
        ? _heroEverFocused && !_heroFocusEntered
        : _firstRowFocused;
    return FocusScope(
      node: _heroFocusScope,
      child: ExcludeFocus(
        excluding: hidden,
        child: HeroBackdrop(
          item: model.hero,
          artworkOverride: model.heroArtwork[model.hero?.id],
          pageCount: heroItems.length,
          pageIndex: currentIndex,
          playFocusNode: _heroPlayFocusNode,
          detailsFocusNode: _heroDetailsFocusNode,
          detailsEnabled: _heroFocusEntered,
          onPlay: model.hero == null
              ? null
              : () => widget.onItemTap?.call(model.hero!),
          onDetails: model.hero == null
              ? null
              : () => widget.onItemTap?.call(model.hero!),
          onPage: (index) => model.focus(heroItems[index]),
          onNext: heroItems.length > 1
              ? () => model.focus(
                  heroItems[(currentIndex + 1) % heroItems.length],
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildRow(
    HomeRow row,
    int index, {
    required bool loading,
    required bool first,
  }) {
    final widgetRow = MediaRow(
      key: ValueKey<String>(loading ? 'skeleton-$index' : 'row-${row.title}'),
      title: row.titleIn(context),
      items: row.items,
      memory: _memory,
      progress: widget.progress,
      onBuild: loading ? null : () => widget.onRowBuild?.call(row.title),
      onItemTap: loading ? null : widget.onItemTap,
      onSeeAll: !loading && row.query != null && widget.onSeeAll != null
          ? () => widget.onSeeAll!(row)
          : null,
      onFocused: widget.viewModel.focus,
      rowIndex: index,
    );
    // Only the first shelf row is wrapped in `_firstRowFocusScope` — that's
    // the one whose focus collapses the hero and whose Back returns to it
    // (Phase file step 6 / `PlexHomeViewController.swift:5453`). Deeper rows
    // are unwrapped and behave exactly as Part A left them.
    if (!first || loading) return widgetRow;
    return FocusScope(node: _firstRowFocusScope, child: widgetRow);
  }
}

/// Placeholder rows the loading skeleton is drawn from: 3 rows of 8 cards
/// with realistic title lengths, so the bones match the real layout.
/// Sizing text under the loading skeleton; never readable.
const String _skeletonRowTitle = 'Placeholder row title';
const String _skeletonFilmTitle = 'Placeholder film title';
const String _skeletonHeroTitle = 'Placeholder title of a featured film';

final List<HomeRow> _placeholderRows = <HomeRow>[
  for (var row = 0; row < 3; row++)
    HomeRow(
      title: _skeletonRowTitle,
      items: <MediaItem>[
        for (var item = 0; item < 8; item++)
          MediaItem(
            id: 'skeleton-$row-$item',
            title: _skeletonFilmTitle,
            kind: MediaKind.movie,
            year: 2024,
          ),
      ],
    ),
];

/// First-load entry of one Home row (DESIGN_SPEC §5.2): fade and rise 8 px
/// over `base`, 40 ms stagger, the first five rows only (the rest start with
/// the fifth). One controller per row drives opacity and a paint transform
/// only. Whether it plays is fixed when the row mounts, so a rebuild never
/// replays it.
class _RowEntry extends StatefulWidget {
  const _RowEntry({
    required this.index,
    required this.play,
    required this.child,
    super.key,
  });

  static const Duration stagger = Duration(milliseconds: 40);
  static const double rise = 8;

  final int index;
  final bool play;
  final Widget child;

  @override
  State<_RowEntry> createState() => _RowEntryState();
}

class _RowEntryState extends State<_RowEntry>
    with SingleTickerProviderStateMixin {
  late final bool _play = widget.play;
  late final Duration _delay = _RowEntry.stagger * math.min(widget.index, 4);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _delay + RivuletMotion.base,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delay.inMicroseconds / _controller.duration!.inMicroseconds,
      1,
      curve: RivuletMotion.easeOut,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (_play) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_play
      ? widget.child
      : FadeTransition(
          opacity: _progress,
          // The row is there for assistive technology from the first frame.
          alwaysIncludeSemantics: true,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, _RowEntry.rise * (1 - _progress.value)),
              child: child,
            ),
            child: widget.child,
          ),
        );
}
