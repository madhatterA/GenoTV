import '../l10n/app_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/glass_surface.dart';
import '../focus/focusable_action.dart';
import '../theme/app_theme.dart';
import '../theme/rivulet_tokens.dart';

/// Pure geometry math for [PlayerPanelHost], split out so placement can be
/// table-tested without pumping a widget tree.
///
/// Source: player floating panel geometry — corner radius 40, rail gap 12,
/// content padding 24, edge inset 40, max height 560 (owner-supplied
/// "Decisions" table, `planning/part-04-ui/chapter-03-player-ui/phase-05-panels.md`,
/// radius revised from 20 to ~40 per the ch03-p05 visual rejection —
/// `evidence/part-04-rivulet/ch03-p05/track_panel_compare.png` — matching
/// the floating glass card in `evidence/part-04-rivulet/infuse-ref/tvos/IMG_8304.jpg`);
/// no numbered Rivulet source line names these values, so they are cited to
/// the phase file's own Decisions table, not a `.swift` line.
import '../platform/form_factor.dart';

import '../platform/adaptive_behavior.dart';

class PlayerPanelGeometry {
  const PlayerPanelGeometry._();

  static const double radius = 40;
  static const double railGap = 12;
  static const double padding = 24;
  static const double edgeInset = 40;
  static const double maxHeight = 560;
  static const double minUsableHeight = 400;

  /// Aligns the panel's start or end edge to [openerTopLeft]/[openerSize]
  /// (the opener button, or the rail's bounds when passed instead),
  /// placed [railGap] above it, then clamps the whole rect inside
  /// [viewport] with [edgeInset] on every edge — never past either side,
  /// never above the top, and capped at [maxHeight] tall.
  static Rect resolve({
    required Offset openerTopLeft,
    required Size openerSize,
    required Size viewport,
    required double panelWidth,
    required double panelHeight,
    bool alignToOpenerStart = false,
  }) {
    final room = openerTopLeft.dy - railGap - edgeInset;
    var height = panelHeight > maxHeight ? maxHeight : panelHeight;
    // Never taller than the space above the rail (a clamped top would slide
    // the panel down over it), but never below what the Options header and
    // first rows need to lay out without overflowing.
    if (room > 0 && height > room) {
      height = room > minUsableHeight
          ? room
          : (height < minUsableHeight ? height : minUsableHeight);
    }
    final openerRight = openerTopLeft.dx + openerSize.width;
    var left = alignToOpenerStart ? openerTopLeft.dx : openerRight - panelWidth;
    final maxLeft = viewport.width - panelWidth - edgeInset;
    final minLeft = edgeInset;
    if (left > maxLeft) left = maxLeft;
    if (left < minLeft) left = minLeft;

    var top = openerTopLeft.dy - railGap - height;
    final maxTop = viewport.height - height - edgeInset;
    final minTop = edgeInset;
    if (top > maxTop) top = maxTop;
    if (top < minTop) top = minTop;

    return Rect.fromLTWH(left, top, panelWidth, height);
  }
}

/// Focus-fenced, opener-restoring floating panel host for every player
/// overlay (track, info/insights, Up Next, source picker).
///
/// - Fences keyboard traversal to its own content: Flutter's default
///   [FocusTraversalPolicy] already resolves `next`/`previous` against the
///   nearest enclosing [FocusScopeNode] (`nearestScope`), so wrapping the
///   panel body in its own [FocusScope] is sufficient — Tab/arrow
///   traversal started inside it never reaches rail/video focus nodes
///   outside. No custom policy needed (Context7 lookup below).
/// - Gives Back/Menu first refusal: an [Escape]/`goBack`/menu key press is
///   consumed here and dismisses the panel instead of reaching whatever the
///   underlying screen would otherwise do with it.
/// - Animates in over 200ms (rise y12 + alpha 0->1) and out over 150ms,
///   honoring `MediaQuery.disableAnimations`.
/// - Restores focus to [opener] on dismissal, or [fallbackFocus] (the
///   nearest still-attached rail button, supplied by the caller) when the
///   opener node was disposed while the panel was open (row removed, etc).
///
/// Context7: Flutter focus/`FocusTraversalPolicy.next` docs — "By default,
/// FocusTraversalPolicy.next will look for the next widget in the nearest
/// FocusScopeNode" (api.flutter.dev, `FocusTraversalPolicy` class docs,
/// fetched via Context7 in a prior successful session; Context7 was
/// disconnected during this phase's run — see report; behavior re-confirmed
/// against the Flutter SDK source at
/// `packages/flutter/lib/src/widgets/focus_traversal.dart`, `_sortAllDescendants`
/// walking `currentNode.nearestScope`).
class PlayerPanelHost extends StatefulWidget {
  const PlayerPanelHost({
    required this.opener,
    required this.builder,
    required this.onDismissed,
    this.fallbackFocus,
    this.anchorLink,
    this.railKey,
    this.panelWidth = 420,
    this.panelHeight,
    this.fitContent = false,
    this.alignToOpenerStart = false,
    this.title,
    super.key,
  });

  /// The control that opened this panel. Focus returns here on dismissal.
  final FocusNode opener;

  /// Builds the panel content. `dismiss` requests the close animation and
  /// then calls [onDismissed].
  final Widget Function(BuildContext context, VoidCallback dismiss) builder;

  /// Called once the dismiss animation finishes; the caller removes the
  /// host from the tree in response (this widget never removes itself).
  final VoidCallback onDismissed;

  /// The control rail; when set, the panel sits [PlayerPanelGeometry.railGap]
  /// above the rail's top edge instead of above the opener button.
  final GlobalKey? railKey;

  /// Used instead of [opener] when the opener node is no longer attached
  /// (e.g. its row scrolled out and was disposed while the panel was open).
  final FocusNode? fallbackFocus;

  final double panelWidth;
  final double? panelHeight;
  final bool fitContent;
  final bool alignToOpenerStart;
  final String? title;

  final LayerLink? anchorLink;

  @override
  State<PlayerPanelHost> createState() => PlayerPanelHostState();
}

class PlayerPanelHostState extends State<PlayerPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RivuletMotion.base,
    reverseDuration: RivuletMotion.base,
  );
  late final FocusScopeNode _scopeNode = FocusScopeNode(
    debugLabel: 'player-panel',
  );
  bool _dismissing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = effectiveDuration(context, RivuletMotion.base);
    _controller.reverseDuration = effectiveDuration(
      context,
      RivuletMotion.base,
    );
    if (_controller.status == AnimationStatus.dismissed && !_dismissing) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scopeNode.dispose();
    super.dispose();
  }

  /// Requests the close animation, restores focus, and reports
  /// [PlayerPanelHost.onDismissed] once the reverse animation completes.
  /// Idempotent — a second call while already dismissing is a no-op.
  void dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _restoreOpenerFocus();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      widget.onDismissed();
      return;
    }
    _controller.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.onDismissed();
    });
  }

  void _restoreOpenerFocus() {
    // `context != null` is the real "still attached" signal: a disposed or
    // never-attached node keeps `canRequestFocus == true` (it is just a
    // stored flag) but `requestFocus()` on it is a silent no-op, which is
    // exactly the case (opener's row scrolled out and was disposed) this
    // falls back for.
    if (widget.opener.context != null && widget.opener.canRequestFocus) {
      widget.opener.requestFocus();
      return;
    }
    final fallback = widget.fallbackFocus;
    if (fallback != null &&
        fallback.context != null &&
        fallback.canRequestFocus) {
      fallback.requestFocus();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.contextMenu) {
      dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Theme(
    // The floating player panel always uses dark glass, even in light mode.
    data: AppTheme.dark(tv: false),
    child: Builder(builder: _buildPanel),
  );

  Widget _buildPanel(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final viewport = MediaQuery.sizeOf(context);
    final openerBox = widget.opener.context?.findRenderObject();
    final Offset openerTopLeft;
    final Size openerSize;
    if (openerBox is RenderBox && openerBox.attached && openerBox.hasSize) {
      openerTopLeft = openerBox.localToGlobal(Offset.zero);
      openerSize = openerBox.size;
    } else {
      openerTopLeft = Offset(
        viewport.width - PlayerPanelGeometry.padding,
        viewport.height,
      );
      openerSize = Size.zero;
    }
    final railBox = widget.railKey?.currentContext?.findRenderObject();
    final railTop = railBox is RenderBox && railBox.attached && railBox.hasSize
        ? railBox.localToGlobal(Offset.zero).dy
        : openerTopLeft.dy;
    final panelHeight =
        widget.panelHeight ??
        (viewport.height * 0.6).clamp(240.0, PlayerPanelGeometry.maxHeight);
    final rect = PlayerPanelGeometry.resolve(
      openerTopLeft: Offset(openerTopLeft.dx, railTop),
      openerSize: openerSize,
      viewport: viewport,
      panelWidth: widget.panelWidth.clamp(
        0,
        viewport.width - 2 * PlayerPanelGeometry.edgeInset,
      ),
      panelHeight: widget.fitContent
          ? panelHeight.clamp(
              0,
              (railTop -
                      PlayerPanelGeometry.railGap -
                      PlayerPanelGeometry.edgeInset)
                  .clamp(0, PlayerPanelGeometry.maxHeight),
            )
          : panelHeight,
      alignToOpenerStart: widget.alignToOpenerStart,
    );

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: rect.height),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final curved = _controller.drive(
            CurveTween(curve: RivuletMotion.easeOut),
          );
          final faded = FadeTransition(opacity: curved, child: child);
          return reduceMotion ||
                  AdaptiveBehavior.of(context).formFactor == FormFactor.tv
              ? faded
              : ScaleTransition(
                  alignment: Alignment.bottomRight,
                  scale: curved.drive(Tween(begin: 0.96, end: 1.0)),
                  child: faded,
                );
        },
        child: FocusScope(
          node: _scopeNode,
          autofocus: AdaptiveBehavior.of(context).formFactor == FormFactor.tv,
          onKeyEvent: _handleKey,
          child: FocusTraversalGroup(
            child: KeyedSubtree(
              key: const ValueKey<String>('player-panel-host'),
              child: GlassSurface(
                radius: RivuletRadius.large,
                padding: const EdgeInsets.all(PlayerPanelGeometry.padding),
                child: Column(
                  mainAxisSize: widget.fitContent
                      ? MainAxisSize.min
                      : MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (widget.title case final title?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: AppText(
                                title,
                                style: tokens.typeStyles.title,
                              ),
                            ),
                            FocusRing(
                              child: IconButton(
                                autofocus:
                                    AdaptiveBehavior.of(context).formFactor ==
                                    FormFactor.tv,
                                key: const ValueKey<String>(
                                  'close-player-overlay',
                                ),
                                onPressed: dismiss,
                                icon: Icon(
                                  Icons.close,
                                  color: tokens.colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Flexible(
                      fit: widget.fitContent ? FlexFit.loose : FlexFit.tight,
                      child: widget.builder(context, dismiss),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Positioned(
      left: rect.left,
      top: widget.fitContent ? null : rect.top,
      bottom: widget.fitContent ? viewport.height - rect.bottom : null,
      width: rect.width,
      height: widget.fitContent ? null : rect.height,
      child: widget.anchorLink == null
          ? panel
          : CompositedTransformFollower(
              link: widget.anchorLink!,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(
                rect.left - openerTopLeft.dx,
                rect.bottom - openerTopLeft.dy,
              ),
              child: panel,
            ),
    );
  }
}
