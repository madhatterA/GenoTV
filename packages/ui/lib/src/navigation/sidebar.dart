import '../l10n_gen/app_strings.dart';

import 'package:flutter/material.dart';

import '../components/glass_surface.dart';
import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'app_destination.dart';

/// Icon glyph inside the menu pill (DESIGN_SPEC §7.2).
const double _pillIconSize = 20;

/// Slide distance of the panel while it fades in (DESIGN_SPEC §5.2).
const double _panelSlide = 24;

/// Distance below the top safe area where the top controls sit.
const double _topControlsGap = 12;

/// Swipe-left close thresholds (DESIGN_SPEC §7.3).
const double _closeVelocity = 300;
const double _closeDragFraction = 0.4;

/// Where the menu pill floats: left = gutter (+ [shift] on pages with a back
/// button), top = safe-area top + 12, height from §4.5, width from the
/// current destination's label. The single source for the pill's geometry.
Rect menuPillRect(BuildContext context, AppDestination active, double shift) {
  final profile = AdaptiveBehavior.of(context);
  final sizes = AdaptiveBehavior.sizesOf(context);
  final style = RivuletTokens.of(context).typeStyles.label;
  final label = TextPainter(
    text: TextSpan(text: active.labelIn(context), style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width =
      2 * RivuletSpacing.s16 +
      _pillIconSize +
      RivuletSpacing.s8 +
      label.width.ceilToDouble();
  label.dispose();
  return Rect.fromLTWH(
    RivuletSpacing.gutter(profile.formFactor) + shift,
    MediaQuery.paddingOf(context).top + _topControlsGap,
    width,
    sizes.menuPillHeight,
  );
}

/// Top y of the top controls (search button, back button).
double topControlsTop(BuildContext context) =>
    MediaQuery.paddingOf(context).top + _topControlsGap;

/// The menu pill and the menu panel (DESIGN_SPEC §7.2, §7.3). `expanded` and
/// the selected id are owned by the caller ([AppShell]); this widget owns the
/// one open/close controller and plays only fades and slides (P5).
class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.destinations,
    required this.activeId,
    required this.pillFocusNode,
    this.pillShift = 0,
    required this.expanded,
    required this.onSelect,
    required this.onCollapse,
    required this.onExpand,
  });

  final List<AppDestination> destinations;
  final String activeId;
  final FocusNode pillFocusNode;

  /// How far the pill steps right to leave room for a back button.
  final double pillShift;
  final bool expanded;

  /// Row activated; the caller selects the destination and closes the panel.
  final ValueChanged<String> onSelect;
  final VoidCallback onCollapse;

  /// Pill activated.
  final VoidCallback onExpand;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> with TickerProviderStateMixin {
  final Map<String, FocusNode> _rowFocus = <String, FocusNode>{};
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.expanded ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: RivuletMotion.drawer,
    reverseCurve: RivuletMotion.easeOut,
  );

  /// Horizontal finger offset of the panel while a swipe-to-close drag runs.
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  FocusNode _focusFor(String id) => _rowFocus.putIfAbsent(id, FocusNode.new);

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _drag.value = 0;
    });
  }

  @override
  void didUpdateWidget(AppSidebar old) {
    super.didUpdateWidget(old);
    if (widget.expanded == old.expanded) return;
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    if (widget.expanded) {
      _controller.duration = effectiveDuration(
        context,
        tv ? RivuletMotion.fast : RivuletMotion.panel,
      );
      _controller.forward();
      // Opening focuses the current destination's row.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusFor(widget.activeId).requestFocus();
      });
    } else {
      final duration = effectiveDuration(
        context,
        tv ? RivuletMotion.fast : RivuletMotion.base,
      );
      _controller.reverseDuration = duration;
      _controller.reverse();
      if (_drag.value != 0) {
        _drag.animateTo(
          -AdaptiveBehavior.sizesOf(context).menuPanelWidth,
          duration: duration,
          curve: RivuletMotion.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _drag.dispose();
    _curve.dispose();
    _controller.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    _drag.value = (_drag.value + details.delta.dx).clamp(-width, 0);
  }

  void _onDragEnd(DragEndDetails details, double width) {
    if (details.velocity.pixelsPerSecond.dx < -_closeVelocity ||
        _drag.value < -_closeDragFraction * width) {
      widget.onCollapse();
    } else {
      _drag.animateTo(
        0,
        duration: effectiveDuration(context, RivuletMotion.fast),
        curve: RivuletMotion.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final profile = AdaptiveBehavior.of(context);
    final sizes = AdaptiveBehavior.sizesOf(context);
    final tv = profile.formFactor == FormFactor.tv;
    final active = widget.destinations.firstWhere(
      (d) => d.id == widget.activeId,
      orElse: () => widget.destinations.first,
    );
    final pillRect = menuPillRect(context, active, 0);
    final panelWidth = sizes.menuPanelWidth;
    final slide = Tween<Offset>(
      begin: tv ? Offset.zero : const Offset(-_panelSlide, 0) / panelWidth,
      end: Offset.zero,
    ).animate(_curve);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dismissed = _controller.status == AnimationStatus.dismissed;
        final completed = _controller.status == AnimationStatus.completed;
        return Stack(
          key: const ValueKey<String>('app-sidebar'),
          children: <Widget>[
            // Gone while fully open so only the panel (plus the search or
            // back button) blurs (P3).
            if (!completed)
              Positioned(
                left: pillRect.left,
                top: pillRect.top,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: widget.pillShift),
                  duration: effectiveDuration(context, RivuletMotion.base),
                  curve: RivuletMotion.easeOut,
                  builder: (context, dx, child) =>
                      Transform.translate(offset: Offset(dx, 0), child: child),
                  child: FadeTransition(
                    opacity: ReverseAnimation(_curve),
                    child: IgnorePointer(
                      ignoring: widget.expanded,
                      child: ExcludeFocus(
                        excluding: widget.expanded,
                        child: _MenuPill(
                          destination: active,
                          width: pillRect.width,
                          focusNode: widget.pillFocusNode,
                          onTap: widget.onExpand,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!dismissed) ...<Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !widget.expanded,
                  child: FadeTransition(
                    opacity: _curve,
                    child: GestureDetector(
                      key: const ValueKey<String>('menu-scrim'),
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onCollapse,
                      child: ColoredBox(color: tokens.colors.scrimMenu),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -RivuletRadius.large,
                top: 0,
                bottom: 0,
                width: panelWidth + RivuletRadius.large,
                child: IgnorePointer(
                  ignoring: !widget.expanded,
                  child: FadeTransition(
                    opacity: _curve,
                    child: SlideTransition(
                      position: slide,
                      child: RepaintBoundary(
                        key: const ValueKey<String>('menu-panel'),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) =>
                              _onDragUpdate(d, panelWidth),
                          onHorizontalDragEnd: (d) => _onDragEnd(d, panelWidth),
                          child: AnimatedBuilder(
                            animation: _drag,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(_drag.value, 0),
                              child: child,
                            ),
                            child: _MenuPanel(
                              destinations: widget.destinations,
                              activeId: widget.activeId,
                              focusFor: _focusFor,
                              onSelect: widget.onSelect,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The floating pill: current destination's Fill icon and label.
class _MenuPill extends StatelessWidget {
  const _MenuPill({
    required this.destination,
    required this.width,
    required this.focusNode,
    required this.onTap,
  });

  final AppDestination destination;
  final double width;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final sizes = AdaptiveBehavior.sizesOf(context);
    return FocusableAction(
      key: const ValueKey<String>('menu-pill'),
      onActivate: onTap,
      focusNode: focusNode,
      semanticLabel: destination.labelIn(context),
      minSize: AdaptiveBehavior.hitTargetOf(context),
      centered: true,
      focusRadius: BorderRadius.circular(RivuletRadius.full),
      child: SizedBox(
        width: width,
        height: sizes.menuPillHeight,
        child: GlassSurface(
          radius: RivuletRadius.full,
          padding: const EdgeInsets.symmetric(horizontal: RivuletSpacing.s16),
          child: Row(
            children: <Widget>[
              AppDestinationIcon(
                destination: destination,
                current: true,
                color: tokens.colors.textPrimary,
                size: _pillIconSize,
              ),
              const SizedBox(width: RivuletSpacing.s8),
              AppText(
                destination.labelIn(context),
                maxLines: 1,
                softWrap: false,
                style: tokens.typeStyles.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header, one row per destination, hairline, Settings pinned at the bottom.
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.destinations,
    required this.activeId,
    required this.focusFor,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final String activeId;
  final FocusNode Function(String id) focusFor;
  final ValueChanged<String> onSelect;

  static const String _pinnedId = 'settings';

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final safe = MediaQuery.paddingOf(context);
    _MenuRow row(AppDestination d) => _MenuRow(
      destination: d,
      current: d.id == activeId,
      focusNode: focusFor(d.id),
      onSelect: onSelect,
    );
    final pinned = destinations.where((d) => d.id == _pinnedId);
    return GlassSurface(
      radius: RivuletRadius.large,
      // The left corners sit off-screen; this keeps content in view.
      padding: const EdgeInsets.only(left: RivuletRadius.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(RivuletSpacing.s24)
                .copyWith(top: RivuletSpacing.s24 + safe.top),
            child: AppText(
              AppStrings.of(context).app_title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typeStyles.title,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: RivuletSpacing.s8,
              ),
              children: <Widget>[
                for (final d in destinations)
                  if (d.id != _pinnedId) row(d),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: tokens.colors.hairline),
          Padding(
            padding: EdgeInsets.fromLTRB(
              RivuletSpacing.s8,
              RivuletSpacing.s8,
              RivuletSpacing.s8,
              RivuletSpacing.s16 + safe.bottom,
            ),
            child: Column(children: <Widget>[for (final d in pinned) row(d)]),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.destination,
    required this.current,
    required this.focusNode,
    required this.onSelect,
  });

  final AppDestination destination;
  final bool current;
  final FocusNode focusNode;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final sizes = AdaptiveBehavior.sizesOf(context);
    // §7.3 rows: phone 56, desktop and TV 52.
    final height = sizes.formFactor == FormFactor.phone ? 56.0 : 52.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: RivuletSpacing.s4),
      child: FocusableAction(
        key: ValueKey<String>('menu-item-${destination.id}'),
        onActivate: () => onSelect(destination.id),
        focusNode: focusNode,
        semanticLabel: destination.labelIn(context),
        minSize: height,
        focusRadius: BorderRadius.circular(RivuletRadius.medium),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: current
                ? tokens.colors.tintFillSelected
                : Colors.transparent,
            borderRadius: BorderRadius.circular(RivuletRadius.medium),
          ),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RivuletSpacing.s16,
              ),
              child: Row(
                children: <Widget>[
                  AppDestinationIcon(
                    destination: destination,
                    current: current,
                    color: current
                        ? tokens.colors.accent
                        : tokens.colors.textPrimary,
                    size: sizes.iconGlyph,
                  ),
                  const SizedBox(width: RivuletSpacing.s12),
                  Expanded(
                    child: AppText(
                      destination.labelIn(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typeStyles.label,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
