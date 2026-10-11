import '../l10n_gen/app_strings.dart';

import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/ambient_background.dart';
import '../components/app_icon_button.dart';
import '../focus/focusable_action.dart';
import '../focus/focusable_card.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'app_destination.dart';
import 'app_page_route.dart';
import 'back_dispatcher.dart';
import 'page_back_button.dart';
import 'page_top_inset.dart';
import 'sidebar.dart';

/// Exposes the shell's shared [BackDispatcher] to descendant screens (an
/// overlay/panel registers a handler here so Back/Menu asks it first — see
/// `AppShell`'s "Back priority" decision: overlay -> menu panel -> local
/// stack -> app exit) and where the menu pill floats.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.backDispatcher,
    this.pillRect = Rect.zero,
    this.select,
    required super.child,
  });

  /// Switches to the destination with the given id (an empty page's action,
  /// e.g. Liked's "Browse movies").
  final ValueChanged<String>? select;

  static ValueChanged<String>? selectOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppShellScope>()?.select;

  final BackDispatcher backDispatcher;

  /// Where the menu pill floats over every page (DESIGN_SPEC §7.2). Pushed
  /// pages keep their own top-left controls clear of it; see
  /// `PageBackButton`.
  final Rect pillRect;

  static Rect pillRectOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>()?.pillRect ??
      Rect.zero;

  static BackDispatcher? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppShellScope>()
      ?.backDispatcher;

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      backDispatcher != oldWidget.backDispatcher ||
      pillRect != oldWidget.pillRect;
}

/// The one shell on every form factor (DESIGN_SPEC §7): a floating menu pill
/// that opens a menu panel, a search button on phone and desktop, no bottom
/// bar and no static side bar. Each destination keeps its own retained
/// `Navigator` stack: switching destinations never rebuilds another one's
/// pages, scroll offsets, or `PageStorage`.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.destinations,
    required this.activeId,
    this.onExitRequested,
  }) : assert(
         destinations.length > 0,
         'AppShell needs at least one destination',
       );

  final List<AppDestination> destinations;

  /// The initially active destination id. Selection afterwards is owned by
  /// the shell itself (a menu row or the search button).
  final String activeId;

  /// Back priority's last resort: no overlay consumed it, the menu panel is
  /// closed and the active destination's stack cannot pop.
  final VoidCallback? onExitRequested;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late String _activeId = widget.activeId;
  String? _outgoingId;
  bool _menuOpen = false;

  /// Drives the incoming destination's fade-through (DESIGN_SPEC §5.2).
  late final AnimationController _switch = AnimationController(
    vsync: this,
    value: 1,
  );
  final Map<String, int> _pushed = <String, int>{};

  /// Destinations whose primary vertical scroll is past 8 px; the top scrim
  /// shows for the active one (DESIGN_SPEC §7.2).
  final Set<String> _scrolled = <String>{};

  static const double _scrimScrollThreshold = 8;
  static const double _topScrimHeight = 96;

  final BackDispatcher _back = BackDispatcher();
  final FocusNode _edgeCatcherFocus = FocusNode(
    debugLabel: 'shell-edge-catcher',
  );
  final FocusNode _pillFocus = FocusNode(debugLabel: 'menu-pill');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'top-search');

  /// Routes currently in each destination's stack, bottom first; the top one
  /// owns the page-entry focus node (DESIGN_SPEC §6.4 rule 9).
  final Map<String, List<Route<dynamic>>> _routes =
      <String, List<Route<dynamic>>>{};

  /// The focused node at the moment the panel opened; focus returns to it on
  /// close (DESIGN_SPEC §6.4 rule 7).
  FocusNode? _restoreFocus;

  // Built once, never in build(): recreating a Navigator's GlobalKey on
  // every rebuild would tear down and rebuild that destination's whole
  // stack (phase-02-navigation.md's "Pitfalls").
  late final Map<String, GlobalKey<NavigatorState>> _navigatorKeys =
      <String, GlobalKey<NavigatorState>>{
        for (final destination in widget.destinations)
          destination.id: GlobalKey<NavigatorState>(
            debugLabel: 'nav-${destination.id}',
          ),
      };

  /// Pushed pages are the ones with a back button; the pill steps right for
  /// them so the button sits to its left.
  bool get _hasBackButton => (_pushed[_activeId] ?? 0) > 0;

  bool _isTv(BuildContext context) =>
      AdaptiveBehavior.of(context).formFactor == FormFactor.tv;

  void _track(String id, int delta, Route<dynamic> route) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pushed[id] = (_pushed[id] ?? 0) + delta;
          _scrolled.remove(id);
        });
        final page = route is ModalRoute ? route.subtreeContext : null;
        final scope = page == null
            ? null
            : Focus.maybeOf(page, scopeOk: true, createDependency: false);
        if (delta > 0 && id == _activeId && scope is FocusScopeNode) {
          _focusPushedPage(scope);
        }
        if (id == _activeId && !_isTv(context)) {
          if (delta > 0) {
            _focusEntry();
          } else {
            _focusEntryIfLost();
          }
        }
      });

  /// TV: a freshly pushed page leaves focus on the page it covers (or
  /// nowhere), so the D-pad would act on something invisible. Put focus on
  /// the new page's first control, preferring one other than its Back button.
  void _focusPushedPage(FocusScopeNode scope) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isTv(context)) return;
      final top = FocusManager.instance.primaryFocus;
      if (top != null &&
          top is! FocusScopeNode &&
          scope.descendants.contains(top)) {
        return; // the page took focus itself (autofocus)
      }
      final candidates = scope.traversalDescendants.where(
        (n) => n is! FocusScopeNode && n.canRequestFocus && !n.skipTraversal,
      );
      final first = candidates
          .where(
            (n) =>
                n.context?.findAncestorWidgetOfExactType<PageBackButton>() ==
                null,
          )
          .firstOrNull;
      (first ?? candidates.firstOrNull)?.requestFocus();
    });
  }

  bool get menuOpen => _menuOpen;
  String get activeId => _activeId;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TV opens in remote mode: the first page takes focus on its entry.
      if (mounted && _isTv(context) && _entryNode() != null) {
        _restoreContentFocus();
      }
    });
  }

  /// TV: a route popped back to this shell (or any other loss) can leave no
  /// focus at all, so the D-pad would do nothing visible; put focus back on
  /// the page's last focused control.
  void _onPrimaryFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    final fromSurface = _verticalFrom;
    if (fromSurface != null) {
      _verticalFrom = null;
      if (_landOnRowMemory(focus, fromSurface)) return;
    }
    final retraceTarget = _retraceTarget;
    if (retraceTarget != null) {
      _retraceTarget = null;
      if (focus != retraceTarget &&
          retraceTarget.context != null &&
          retraceTarget.canRequestFocus) {
        retraceTarget.requestFocus();
        return;
      }
    }
    final pending = _pendingRetrace;
    if (pending != null) {
      _pendingRetrace = null;
      _retrace = (from: pending.from, to: focus, direction: pending.direction);
    } else if (_retrace != null && focus != _retrace!.to) {
      _retrace = null;
    }
    if (focus != null && focus != FocusManager.instance.rootScope) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuOpen) return;
      if (!_isTv(context) || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final now = FocusManager.instance.primaryFocus;
      if (now == null || now == FocusManager.instance.rootScope) {
        _restoreContentFocus();
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _edgeCatcherFocus.dispose();
    _pillFocus.dispose();
    _searchFocus.dispose();
    _switch.dispose();
    super.dispose();
  }

  bool _typingInTextField() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent ||
        (event is KeyRepeatEvent &&
            (_directionOf(key) == null || _isTv(context)))) {
      return KeyEventResult.ignored;
    }
    if (_menuOpen) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.arrowRight) {
        _closeMenu();
        return KeyEventResult.handled;
      }
      // Held/extra Left inside the open panel must not traverse out of it
      // (bug_history 2026-10-06 TV walk).
      if (key == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    final character = event.character;
    final typeAhead = _routes[_activeId]?.lastOrNull is AppPageRoute
        ? (_routes[_activeId]!.last as AppPageRoute).entry.typeAhead
        : null;
    if (typeAhead != null &&
        !_isTv(context) &&
        !_typingInTextField() &&
        character != null &&
        character.trim().length == 1 &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      typeAhead(character);
      return KeyEventResult.handled;
    }
    if (!_isTv(context) &&
        !_typingInTextField() &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.backspace)) {
      final navigator = _navigatorKeys[_activeId]?.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.keyM && !_typingInTextField())) {
      _openMenu();
      return KeyEventResult.handled;
    }
    if (!_isTv(context)) return _desktopMove(key);
    if (key == LogicalKeyboardKey.arrowLeft) {
      final moved =
          FocusManager.instance.primaryFocus?.focusInDirection(
            TraversalDirection.left,
          ) ??
          false;
      if (!moved) _openMenu();
      return KeyEventResult.handled;
    }
    // DESIGN_SPEC §7.4: the pill is Up from the top of the page and Down
    // from it returns to the page's entry element.
    if (key == LogicalKeyboardKey.arrowDown && _pillFocus.hasPrimaryFocus) {
      _entryNode()?.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      // Row to row lands on the item the target row last had (§6.4 rule 2).
      _verticalFrom = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FocusableCard>()
          ?.surfaceId;
    }
    final moved = _crossScopeMove(key);
    // The focus change lands in a microtask queued by the move above.
    scheduleMicrotask(() => _verticalFrom = null);
    if (moved == KeyEventResult.ignored &&
        key == LogicalKeyboardKey.arrowUp &&
        _pillFocus.context != null) {
      // A pushed page's Back button sits left of the pill (§7.2).
      final back = _backNode();
      (back != null && back.canRequestFocus ? back : _pillFocus).requestFocus();
      return KeyEventResult.handled;
    }
    return moved;
  }

  static TraversalDirection? _directionOf(LogicalKeyboardKey key) =>
      switch (key) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        LogicalKeyboardKey.arrowRight => TraversalDirection.right,
        _ => null,
      };

  /// Surface of the card a vertical move started from, while that move is in
  /// flight; [_landOnRowMemory] consumes it.
  String? _verticalFrom;

  /// DESIGN_SPEC §6.4 rule 2: Up/Down into another row land on the item that
  /// row last had focused; with none, the geometric (nearest centre) choice
  /// the traversal already made stands. Returns whether it moved focus again.
  bool _landOnRowMemory(FocusNode? landed, String fromSurface) {
    final card = landed?.context
        ?.findAncestorWidgetOfExactType<FocusableCard>();
    if (card == null || card.surfaceId == fromSurface) return false;
    final remembered = card.memory.restingNode(card.surfaceId);
    if (remembered != null &&
        remembered != landed &&
        remembered.context != null &&
        remembered.canRequestFocus) {
      remembered.requestFocus();
      return true;
    }
    return false;
  }

  /// The last vertical move, so the opposite key retraces it: Down from Play
  /// to the row below and Up again lands back on Play, not on whatever sits
  /// geometrically nearest (DESIGN_SPEC §6.4 rule 2).
  ({FocusNode from, FocusNode? to, TraversalDirection direction})? _retrace;
  ({FocusNode from, TraversalDirection direction})? _pendingRetrace;
  FocusNode? _retraceTarget;

  /// The back button of the active pushed page, if it has one.
  FocusNode? _backNode() => _navigatorKeys[_activeId]
      ?.currentState
      ?.focusNode
      .traversalDescendants
      .where(
        (n) =>
            n.context?.findAncestorWidgetOfExactType<PageBackButton>() != null,
      )
      .firstOrNull;

  /// Desktop arrows (DESIGN_SPEC §6.4 rule 4): the floating controls link to
  /// each other and to the page's entry element; inside the page a move the
  /// page's own scopes cannot make continues across them, and Up from the top
  /// of the page lands on the menu pill. Nothing wraps.
  KeyEventResult _desktopMove(LogicalKeyboardKey key) {
    final direction = _directionOf(key);
    final current = FocusManager.instance.primaryFocus;
    if (direction == null || current == null || !current.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    // A text field keeps Left/Right (caret) and multi-line Up/Down.
    final editable = current.context
        ?.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null &&
        (direction == TraversalDirection.left ||
            direction == TraversalDirection.right ||
            editable.maxLines != 1)) {
      return KeyEventResult.ignored;
    }
    final search = _searchFocus.context != null ? _searchFocus : null;
    final back = _backNode();
    FocusNode? target;
    if (current == _pillFocus) {
      target = switch (direction) {
        TraversalDirection.right => search,
        TraversalDirection.left => back,
        TraversalDirection.down => _entryNode(),
        TraversalDirection.up => null,
      };
    } else if (current == _searchFocus) {
      target = switch (direction) {
        TraversalDirection.left => _pillFocus,
        TraversalDirection.down => _entryNode(),
        _ => null,
      };
    } else if (current == back) {
      target = switch (direction) {
        TraversalDirection.right => _pillFocus,
        TraversalDirection.down => _entryNode(),
        _ => null,
      };
    } else {
      if (direction == TraversalDirection.up ||
          direction == TraversalDirection.down) {
        _verticalFrom = current.context
            ?.findAncestorWidgetOfExactType<FocusableCard>()
            ?.surfaceId;
      }
      if (direction == TraversalDirection.up ||
          direction == TraversalDirection.down) {
        final retrace = _retrace;
        if (retrace != null &&
            retrace.to == current &&
            retrace.direction != direction) {
          _retraceTarget = retrace.from;
          _retrace = null;
        } else {
          _pendingRetrace = (from: current, direction: direction);
        }
      }
      final moved =
          current.focusInDirection(direction) ||
          _crossScopeMove(key) == KeyEventResult.handled;
      // The focus change lands in a microtask queued by the move above.
      scheduleMicrotask(() {
        _verticalFrom = null;
        _pendingRetrace = null;
        _retraceTarget = null;
      });
      if (moved) return KeyEventResult.handled;
      if (direction == TraversalDirection.up) target = _pillFocus;
    }
    if (target != null && target.context != null && target.canRequestFocus) {
      FocusTraversalPolicy.defaultTraversalRequestFocusCallback(target);
    }
    return KeyEventResult.handled;
  }

  /// The page's primary element, else the first control of the page other
  /// than its back button.
  FocusNode? _entryNode() {
    final top = _routes[_activeId]?.lastOrNull;
    final registered = top is AppPageRoute ? top.entry.node : null;
    if (registered != null &&
        registered.context != null &&
        registered.canRequestFocus) {
      return registered;
    }
    final pageContext = top is ModalRoute ? top.subtreeContext : null;
    final scope = pageContext == null
        ? _navigatorKeys[_activeId]?.currentState?.focusNode
        : Focus.maybeOf(pageContext, scopeOk: true, createDependency: false);
    final candidates = (scope?.traversalDescendants ?? const <FocusNode>[])
        .where(
          (n) =>
              n is! FocusScopeNode &&
              n.canRequestFocus &&
              !n.skipTraversal &&
              n.context?.findAncestorWidgetOfExactType<PageBackButton>() ==
                  null,
        );
    return candidates.firstOrNull;
  }

  /// Keyboard/remote page entry (DESIGN_SPEC §6.4 rule 9).
  void _focusEntry() {
    if (_menuOpen ||
        !focusRingVisibleFor(AdaptiveBehavior.of(context).inputMode)) {
      return;
    }
    _entryNode()?.requestFocus();
  }

  /// After a pop: focus is only taken when the opener did not get it back.
  void _focusEntryIfLost() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null &&
        focus != FocusManager.instance.rootScope &&
        focus.context != null) {
      return;
    }
    _focusEntry();
  }

  @override
  Widget build(BuildContext context) {
    final profile = AdaptiveBehavior.of(context);
    final tv = profile.formFactor == FormFactor.tv;
    final active = widget.destinations.firstWhere(
      (d) => d.id == _activeId,
      orElse: () => widget.destinations.first,
    );
    final backSlot = menuBackSlotOf(context);
    final pill = menuPillRect(context, active, _hasBackButton ? backSlot : 0);
    final colors = RivuletTokens.of(context).colors;
    final gutter = RivuletSpacing.gutter(profile.formFactor);
    final controlsVisible = ModalRoute.isCurrentOf(context) ?? true;
    final showSearch =
        controlsVisible &&
        !tv &&
        !_hasBackButton &&
        _activeId != 'search' &&
        widget.destinations.any((d) => d.id == 'search');
    return AppShellScope(
      backDispatcher: _back,
      pillRect: pill,
      select: _select,
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (_, _) => _handleBack(),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) => _onKey(context, event),
          child: Scaffold(
            backgroundColor: colors.bgBase,
            body: Stack(
              children: <Widget>[
                const Positioned.fill(
                  child: AmbientBackground(child: SizedBox.expand()),
                ),
                _contentStack(),
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: _topScrimHeight,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      key: const ValueKey<String>('top-scrim'),
                      duration: effectiveDuration(context, RivuletMotion.fast),
                      opacity: _scrolled.contains(_activeId) ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: colors.scrimTopBar),
                      ),
                    ),
                  ),
                ),
                if (showSearch)
                  Positioned(
                    right: gutter,
                    top: pill.top,
                    height: pill.height
                        .clamp(
                          AdaptiveBehavior.hitTargetOf(context),
                          double.infinity,
                        )
                        .toDouble(),
                    child: Align(
                      alignment: Alignment.centerRight,
                      widthFactor: 1,
                      child: AppIconButton(
                        key: const ValueKey<String>('top-search'),
                        focusNode: _searchFocus,
                        glass: true,
                        icon: PhosphorIconsRegular.magnifyingGlass,
                        semanticLabel: AppStrings.of(context).common_search,
                        onActivate: () => _select('search'),
                      ),
                    ),
                  ),
                // Edge catcher (TV): a Left/focus move out of content lands
                // here and opens the panel.
                if (tv)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: Focus(
                      focusNode: _edgeCatcherFocus,
                      onFocusChange: (hasFocus) {
                        if (hasFocus && !_menuOpen) _openMenu();
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                Positioned.fill(
                  child: Visibility(
                    visible: controlsVisible,
                    maintainState: true,
                    child: AppSidebar(
                      key: const ValueKey<String>('app-sidebar-widget'),
                      destinations: widget.destinations,
                      activeId: _activeId,
                      pillFocusNode: _pillFocus,
                      pillShift: _hasBackButton ? backSlot : 0,
                      expanded: _menuOpen,
                      onSelect: _selectAndClose,
                      onCollapse: _closeMenu,
                      onExpand: _openMenu,
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

  Widget _contentStack() => AnimatedBuilder(
    animation: _switch,
    builder: (context, _) => Stack(
      key: const ValueKey<String>('shell-content-stack'),
      fit: StackFit.expand,
      children: <Widget>[
        for (final destination in widget.destinations)
          Offstage(
            offstage:
                destination.id != _activeId &&
                (destination.id != _outgoingId || !_switch.isAnimating),
            child: IgnorePointer(
              ignoring: destination.id != _activeId,
              child: ExcludeSemantics(
                excluding: destination.id != _activeId,
                child: _switchTransition(
                  incoming: destination.id == _activeId,
                  child: ExcludeFocus(
                    excluding: destination.id != _activeId || _menuOpen,
                    child: _tabNavigator(destination),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _switchTransition({required Widget child, required bool incoming}) =>
      _isTv(context)
      ? FadeTransition(
          opacity: incoming ? _switch : ReverseAnimation(_switch),
          child: child,
        )
      : FadeThroughTransition(
          animation: incoming ? _switch : kAlwaysCompleteAnimation,
          secondaryAnimation: incoming ? kAlwaysDismissedAnimation : _switch,
          child: child,
        );

  Widget _tabNavigator(AppDestination destination) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (destination.id == _activeId) _handleScroll(notification);
          return false;
        },
        child: Navigator(
          key: _navigatorKeys[destination.id],
          observers: <NavigatorObserver>[
            _DepthObserver(
              (delta, route) => _track(destination.id, delta, route),
              (route, added) {
                final stack = _routes.putIfAbsent(
                  destination.id,
                  () => <Route<dynamic>>[],
                );
                added ? stack.add(route) : stack.remove(route);
              },
            ),
          ],
          onGenerateRoute: (settings) => AppPageRoute<void>(
            settings: settings,
            builder: destination.builder,
          ),
        ),
      );

  /// Only the page's own primary vertical scroll (depth 0) drives the top
  /// scrim.
  void _handleScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return;
    }
    final scrolled = notification.metrics.pixels > _scrimScrollThreshold;
    if (scrolled == _scrolled.contains(_activeId)) return;
    setState(() {
      if (scrolled) {
        _scrolled.add(_activeId);
      } else {
        _scrolled.remove(_activeId);
      }
    });
  }

  void _select(String id) {
    // Owner fix (round-a item 7): clicking the ALREADY-active destination
    // (e.g. Home while a detail page is pushed on top of it) pops that
    // destination's stack to its root. Switching to a DIFFERENT destination
    // keeps its pushed stack untouched (`navigation_shell_test.dart`'s
    // "switching destinations retains each stack's pushed route" case).
    if (id == _activeId) {
      _navigatorKeys[id]?.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    _switch.duration = effectiveDuration(
      context,
      _isTv(context) ? RivuletMotion.fast : RivuletMotion.base,
    );
    setState(() {
      _outgoingId = _activeId;
      _activeId = id;
    });
    _switch.forward(from: 0);
  }

  void _selectAndClose(String id) {
    _select(id);
    _closeMenu(restoreFocus: false);
    _restoreContentFocus();
  }

  void _openMenu() {
    if (_menuOpen) return;
    final focus = FocusManager.instance.primaryFocus;
    _restoreFocus =
        focus == null || focus is FocusScopeNode || focus == _edgeCatcherFocus
        ? null
        : focus;
    setState(() => _menuOpen = true);
  }

  void _closeMenu({bool restoreFocus = true}) {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    final saved = _restoreFocus;
    _restoreFocus = null;
    if (!restoreFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuOpen) return;
      if (saved != null && saved.context != null && saved.canRequestFocus) {
        saved.requestFocus();
      } else {
        _restoreContentFocus();
      }
    });
  }

  /// TV: a D-pad move that the focus scope holding the current node cannot
  /// make (e.g. Home's hero scope has nothing below Play) continues to the
  /// nearest focusable control of the whole active page in that direction,
  /// so focus is never stuck inside a nested scope.
  KeyEventResult _crossScopeMove(LogicalKeyboardKey key) {
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft when !_isTv(context) =>
        TraversalDirection.left,
      LogicalKeyboardKey.arrowLeft => null,
      _ => _directionOf(key),
    };
    final current = FocusManager.instance.primaryFocus;
    final page = _navigatorKeys[_activeId]?.currentState?.focusNode;
    if (direction == null ||
        _menuOpen ||
        current == null ||
        page == null ||
        !current.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    if (!_isTv(context)) {
      // desktop callers already tried the scope-local move
    } else if (current.focusInDirection(direction)) {
      return KeyEventResult.handled;
    }
    final from = current.rect;
    FocusNode? best;
    var bestScore = double.infinity;
    for (final node in page.traversalDescendants) {
      if (node == current ||
          node is FocusScopeNode ||
          !node.canRequestFocus ||
          node.skipTraversal ||
          node.context == null) {
        continue;
      }
      final to = node.rect;
      if (to.isEmpty) continue;
      final (along, across) = switch (direction) {
        TraversalDirection.down => (
          to.top - from.bottom,
          to.center.dx - from.center.dx,
        ),
        TraversalDirection.up => (
          from.top - to.bottom,
          to.center.dx - from.center.dx,
        ),
        TraversalDirection.right => (
          to.left - from.right,
          to.center.dy - from.center.dy,
        ),
        TraversalDirection.left => (
          from.left - to.right,
          to.center.dy - from.center.dy,
        ),
      };
      if (along < -1) continue;
      // Desktop: Left/Right never jump to another row of the page.
      if (!_isTv(context) &&
          (direction == TraversalDirection.left ||
              direction == TraversalDirection.right) &&
          (to.bottom <= from.top || to.top >= from.bottom)) {
        continue;
      }
      final score = along.abs() + 2 * across.abs();
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    if (best == null) return KeyEventResult.ignored;
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(best);
    return KeyEventResult.handled;
  }

  /// After a destination is chosen (or focus is lost) put focus on the active
  /// page's primary element; touch input has no visible focus, so it is left
  /// alone there.
  void _restoreContentFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuOpen) return;
      if (_isTv(context)) {
        final scope = _navigatorKeys[_activeId]?.currentState?.focusNode;
        final held = FocusManager.instance.primaryFocus;
        if (scope == null ||
            (scope.hasFocus && held != scope && held is! FocusScopeNode)) {
          return;
        }
        // A page with nothing focusable would trap D-pad focus outside the
        // shell; keep the user in the menu instead.
        if (!scope.descendants.any(
          (n) => n is! FocusScopeNode && n.canRequestFocus,
        )) {
          _openMenu();
        } else {
          // Back to the control the page last had focus on, else its entry.
          final remembered = scope.nearestScope?.focusedChild;
          if (remembered != null &&
              remembered is! FocusScopeNode &&
              scope.descendants.contains(remembered)) {
            remembered.requestFocus();
          } else {
            _entryNode()?.requestFocus();
          }
        }
        return;
      }
      if (!focusRingVisibleFor(AdaptiveBehavior.of(context).inputMode)) return;
      final entry = _entryNode();
      if (entry != null) {
        entry.requestFocus();
        return;
      }
      final navigatorContext = _navigatorKeys[_activeId]?.currentContext;
      if (navigatorContext == null) return;
      final scope = FocusScope.of(navigatorContext);
      if (!scope.hasFocus) scope.requestFocus();
    });
  }

  /// Back order: player overlay -> menu panel -> tab pop -> app exit.
  void _handleBack() {
    if (_back.dispatch()) return;
    if (_menuOpen) {
      _closeMenu();
      return;
    }
    final navigator = _navigatorKeys[_activeId]?.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    widget.onExitRequested?.call();
  }
}

/// Reports pages pushed above (+1) or removed from (-1) a destination's root,
/// and keeps the destination's route stack up to date.
class _DepthObserver extends NavigatorObserver {
  _DepthObserver(this._report, this._stack);

  final void Function(int delta, Route<dynamic> route) _report;
  final void Function(Route<dynamic> route, bool added) _stack;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack(route, true);
    if (previousRoute != null) _report(1, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack(route, false);
    _report(-1, route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack(route, false);
    _report(-1, route);
  }
}
