import 'dart:math' as math;

import '../l10n_gen/app_strings.dart';

import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/ambient_background.dart';
import '../components/app_icon_button.dart';
import '../components/app_toast.dart';
import '../components/shader_warmup.dart';
import '../components/shortcut_sheet.dart';
import '../focus/focusable_action.dart';
import '../focus/focusable_card.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/desktop_menu_bar.dart';
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
    this.exitOnRootBack = false,
    this.sidebarMinWindow = RivuletSpacing.sidebarMinWindow,
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

  /// Back on the home tab's root (nothing open, no overlay) is left to the
  /// system, which leaves the app (tvOS Menu returns to the Apple TV home).
  final bool exitOnRootBack;

  /// Desktop window width (logical px) from which the persistent sidebar
  /// replaces the pill; `double.infinity` keeps the pill at any width.
  final double sidebarMinWindow;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late String _activeId = widget.activeId;
  String? _outgoingId;
  bool _menuOpen = false;
  final GlobalKey<DesktopSidebarState> _sidebarKey =
      GlobalKey<DesktopSidebarState>();
  bool _wasWide = false;

  /// Drives the incoming destination's fade-through (DESIGN_SPEC §5.2).
  late final AnimationController _switch = AnimationController(
    vsync: this,
    value: 1,
  );
  final Map<String, int> _pushed = <String, int>{};

  /// Destinations whose primary vertical scroll is past 8 px; the top scrim
  /// shows for the active one (DESIGN_SPEC §7.2).
  final Set<String> _scrolled = <String>{};

  /// Pings the top scrim alone when a page scrolls past the threshold, so the
  /// pages (all tabs) are not rebuilt for an opacity change.
  final ValueNotifier<int> _scrim = ValueNotifier<int>(0);

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
  final ValueNotifier<int> _ambientPages = ValueNotifier<int>(0);
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
      AdaptiveBehavior.formFactorOf(context) == FormFactor.tv;

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
    _back.addListener(_backHandlersChanged);
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
    _back.removeListener(_backHandlersChanged);
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _edgeCatcherFocus.dispose();
    _pillFocus.dispose();
    _searchFocus.dispose();
    _exitTimer?.cancel();
    _switch.dispose();
    _scrim.dispose();
    super.dispose();
  }

  // Handlers (player overlay, text entry) register during builds.
  void _backHandlersChanged() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });

  bool _backLeavesApp(BuildContext context) =>
      widget.exitOnRootBack &&
      !_menuOpen &&
      !_back.hasHandlers &&
      _activeId == widget.activeId &&
      (_pushed[_activeId] ?? 0) == 0 &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  bool? _sentFrameworkHandlesBack;

  /// Flutter only forwards "the framework handles Back" to the engine on
  /// Android, but the tvOS engine reads the same message: send it ourselves.
  /// False lets the system take Menu (the app leaves for the Apple TV home).
  void _syncFrameworkBack(bool handles) {
    if (!widget.exitOnRootBack || _sentFrameworkHandlesBack == handles) return;
    _sentFrameworkHandlesBack = handles;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        SystemChannels.platform.invokeMethod<void>(
          'SystemNavigator.setFrameworkHandlesBack',
          handles,
        ),
      );
    });
  }

  bool _typingInTextField() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  /// Part 07 p11 desktop shortcuts; null when [key] is not one of them.
  VoidCallback? _appShortcut(LogicalKeyboardKey key, String? character) {
    final keyboard = HardwareKeyboard.instance;
    if (AdaptiveBehavior.primaryModifierHeld()) {
      if (keyboard.isAltPressed || keyboard.isShiftPressed) return null;
      return switch (key) {
        LogicalKeyboardKey.keyF => _openSearch,
        LogicalKeyboardKey.comma => _openSettings,
        LogicalKeyboardKey.keyR => _refreshPage,
        _ => null,
      };
    }
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return null;
    }
    return switch (character) {
      '/' => _openSearch,
      '?' => () => showShortcutSheet(context),
      _ => null,
    };
  }

  /// A keyboard jump to a destination: the content keeps keyboard focus.
  void _selectByKey(String id) {
    if (!widget.destinations.any((d) => d.id == id)) return;
    _select(id);
    _restoreContentFocus(force: true);
  }

  void _openSearch() {
    _selectByKey('search');
  }

  void _openSettings() {
    _selectByKey('settings');
  }

  /// Rebuilds the current destination's root page (its data loads again).
  /// A pushed page is left alone: only a root page is refreshed.
  void _refreshPage() {
    if (_hasBackButton) return;
    final id = _activeId;
    _routes.remove(id);
    _navigatorKeys[id] = GlobalKey<NavigatorState>(debugLabel: 'nav-$id');
    setState(() {});
  }

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
    if (!_isTv(context) && !_typingInTextField()) {
      final shortcut = _appShortcut(key, character);
      if (shortcut != null) {
        shortcut();
        return KeyEventResult.handled;
      }
    }
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
    final back = HardwareKeyboard.instance.isAltPressed
        ? key == LogicalKeyboardKey.arrowLeft
        : HardwareKeyboard.instance.isMetaPressed &&
              key == LogicalKeyboardKey.bracketLeft;
    if (!_isTv(context) &&
        !_typingInTextField() &&
        (back ||
            key == LogicalKeyboardKey.escape ||
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
    if (_inSidebar(current)) {
      if (direction == TraversalDirection.right) {
        _focusPage();
      } else if (direction != TraversalDirection.left) {
        current.focusInDirection(direction);
      }
      return KeyEventResult.handled;
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
      if (_wide(context) && direction == TraversalDirection.left) {
        _sidebarKey.currentState?.focusActive();
        return KeyEventResult.handled;
      }
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
    final backSlot = menuPillShiftOf(context);
    var pill = menuPillRect(context, active, _hasBackButton ? backSlot : 0);
    // No pill beside the sidebar: pages keep its slot position, zero wide.
    if (_wide(context)) {
      pill = Rect.fromLTWH(pill.left, pill.top, 0, pill.height);
    }
    final colors = RivuletTokens.of(context).colors;
    final gutter = RivuletSpacing.gutterOf(context);
    final controlsVisible = ModalRoute.isCurrentOf(context) ?? true;
    final wide = _wide(context);
    final windowSize = MediaQuery.sizeOf(context);
    final available =
        windowSize.width - (wide ? RivuletSpacing.sidebarWidth : 0);
    // Ultra-wide desktop windows: content stays a readable width, centred.
    // (Only beside the sidebar: the pill sits at the window edge.)
    final capped = wide && available > RivuletSpacing.contentMaxWidth;
    final contentWidth = capped ? RivuletSpacing.contentMaxWidth : available;
    if (wide != _wasWide) {
      // Resizing across the threshold: focus lost with the old chrome goes to
      // the page; the current section is shell state and stays.
      _wasWide = wide;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusEntryIfLost();
      });
    }
    final showSearch =
        controlsVisible &&
        !tv &&
        !wide &&
        !_hasBackButton &&
        _activeId != 'search' &&
        widget.destinations.any((d) => d.id == 'search');
    _syncFrameworkBack(!_backLeavesApp(context));
    return DesktopMenuBar(
      onSearch: _openSearch,
      onSettings: _openSettings,
      onRefresh: _refreshPage,
      onShortcuts: () => showShortcutSheet(context),
      child: ScrollConfiguration(
        behavior: _ShellScrollBehavior(
          desktopScrollbars: profile.formFactor == FormFactor.desktop,
        ),
        child: AppShellScope(
          backDispatcher: _back,
          pillRect: pill,
          select: _select,
          child: PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (_, _) => _handleBack(),
            child: Listener(
              onPointerDown: _onPointerDown,
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) => _onKey(context, event),
                child: Scaffold(
                  backgroundColor: colors.bgBase,
                  body: AmbientCoverage(
                    pages: _ambientPages,
                    child: Stack(
                      children: <Widget>[
                        const Positioned.fill(
                          child: AmbientBackground(
                            shell: true,
                            child: SizedBox.expand(),
                          ),
                        ),
                        if (_isTv(context))
                          const Positioned(
                            right: 0,
                            bottom: 0,
                            child: ShaderWarmup(),
                          ),
                        if (wide || capped)
                          Positioned.fill(
                            left: wide ? RivuletSpacing.sidebarWidth : 0,
                            child: MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                size: Size(contentWidth, windowSize.height),
                              ),
                              child: capped
                                  ? Center(
                                      child: SizedBox(
                                        width: contentWidth,
                                        height: double.infinity,
                                        child: _contentStack(),
                                      ),
                                    )
                                  : _contentStack(),
                            ),
                          )
                        else
                          _contentStack(),
                        Positioned(
                          left: 0,
                          top: 0,
                          right: 0,
                          height: _topScrimHeight,
                          child: IgnorePointer(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _scrim,
                              // The gradient's own alpha is animated, not an
                              // opacity layer (its first show cost ~40 ms of raster
                              // on the TV; `ShaderWarmup` pre-compiles the gradient).
                              builder: (_, _, _) =>
                                  TweenAnimationBuilder<double>(
                                    key: const ValueKey<String>('top-scrim'),
                                    duration: effectiveDuration(
                                      context,
                                      RivuletMotion.fast,
                                    ),
                                    tween: Tween<double>(
                                      end: _scrolled.contains(_activeId)
                                          ? 1
                                          : 0,
                                    ),
                                    // TV: never fully clear (1/255 of black is
                                    // invisible), so the gradient is already compiled
                                    // when the first scroll shows it.
                                    builder: (_, opacity, _) =>
                                        opacity == 0 && !tv
                                        ? const SizedBox.shrink()
                                        : DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: colors.scrimTopBar
                                                  .scale(
                                                    tv
                                                        ? math.max(
                                                            opacity,
                                                            0.01,
                                                          )
                                                        : opacity,
                                                  ),
                                            ),
                                          ),
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
                                semanticLabel: AppStrings.of(context)
                                    .common_search,
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
                        if (wide && controlsVisible)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: DesktopSidebar(
                              key: _sidebarKey,
                              destinations: widget.destinations,
                              activeId: _activeId,
                              onSelect: _select,
                            ),
                          ),
                        Positioned.fill(
                          child: Visibility(
                            visible: controlsVisible && !wide,
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
    if (scrolled) {
      _scrolled.add(_activeId);
    } else {
      _scrolled.remove(_activeId);
    }
    _scrim.value++;
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

  /// Desktop window wide enough for the persistent sidebar (no pill, no panel).
  bool _wide(BuildContext context) =>
      AdaptiveBehavior.formFactorOf(context) == FormFactor.desktop &&
      MediaQuery.sizeOf(context).width >= widget.sidebarMinWindow;

  bool _inSidebar(FocusNode? node) =>
      node?.context?.findAncestorStateOfType<DesktopSidebarState>() != null;

  /// Right from the sidebar: the page's remembered focus, else its entry.
  void _focusPage() {
    final scope = _navigatorKeys[_activeId]?.currentState?.focusNode;
    final remembered = scope?.nearestScope?.focusedChild;
    if (remembered != null &&
        remembered is! FocusScopeNode &&
        remembered.context != null &&
        scope!.descendants.contains(remembered)) {
      remembered.requestFocus();
    } else {
      _entryNode()?.requestFocus();
    }
  }

  void _openMenu() {
    if (_menuOpen) return;
    if (_wide(context)) {
      _sidebarKey.currentState?.focusActive();
      return;
    }
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
  void _restoreContentFocus({bool force = false}) {
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
      if (!force &&
          !focusRingVisibleFor(AdaptiveBehavior.of(context).inputMode)) {
        return;
      }
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
    if (_activeId != widget.activeId) {
      _select(widget.activeId);
      _restoreContentFocus();
      return;
    }
    // Android phone and TV: a second Back within 2 s leaves the app.
    if (!widget.exitOnRootBack &&
        Theme.of(context).platform == TargetPlatform.android) {
      if (_exitTimer == null) {
        _exitTimer = Timer(_exitWindow, () => _exitTimer = null);
        showAppToast(
          context,
          PhosphorIconsRegular.signOut,
          AppStrings.of(context).back_pressAgainToExit,
          duration: _exitWindow,
        );
        return;
      }
    }
    widget.onExitRequested?.call();
  }

  static const Duration _exitWindow = RivuletMotion.backExit;
  Timer? _exitTimer;

  /// Mouse back button pops the active tab's pushed page (desktop).
  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kBackMouseButton == 0 || _isTv(context)) return;
    final navigator = _navigatorKeys[_activeId]?.currentState;
    if (navigator != null && navigator.canPop()) navigator.pop();
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

/// Desktop gets a thin auto-hiding vertical scrollbar; phone and TV none.
class _ShellScrollBehavior extends MaterialScrollBehavior {
  const _ShellScrollBehavior({required this.desktopScrollbars});

  final bool desktopScrollbars;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (!desktopScrollbars ||
        axisDirectionToAxis(details.direction) != Axis.vertical) {
      return child;
    }
    return Scrollbar(
      controller: details.controller,
      thickness: RivuletSpacing.scrollbarThickness,
      child: child,
    );
  }

  @override
  bool shouldNotify(_ShellScrollBehavior oldDelegate) =>
      oldDelegate.desktopScrollbars != desktopScrollbars;
}
