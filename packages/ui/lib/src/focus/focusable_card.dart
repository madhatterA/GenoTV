import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../platform/adaptive_behavior.dart';
import '../player/transport_control_button.dart' show TransportControlButton;
import '../platform/form_factor.dart';
import '../theme/app_theme.dart';
import '../theme/rivulet_tokens.dart';
import 'focus_memory.dart';
import 'focusable_action.dart';

class FocusableCard extends StatefulWidget {
  /// Room a list or grid must leave around each card so the focus growth and
  /// ring are never clipped by the scroll viewport or hidden by a neighbour.
  static const double glowInset = 32;

  /// TV vertical focus aligns the whole section below the floating controls.
  static void revealSection(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Future<void>.delayed(RivuletMotion.base, () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          var focused = false;
          FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
            e,
          ) {
            if (e == context) focused = true;
            return !focused;
          });
          if (!focused) return;
          final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
          final object = context.findRenderObject();
          if (scrollable == null || object == null) return;
          final viewport = RenderAbstractViewport.maybeOf(object);
          if (viewport == null) return;
          final position = scrollable.position;
          final target =
              viewport.getOffsetToReveal(object, 0).offset -
              RivuletSpacing.topInset(FormFactor.tv);
          position.jumpTo(
            target.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
        });
        WidgetsBinding.instance.scheduleFrame();
      });
    });
  }

  /// Space above and below cards for their focus scale and glow.
  static double focusRoom(double cardHeight) => cardHeight * 0.04 + 16;

  const FocusableCard({
    required this.surfaceId,
    required this.itemId,
    required this.memory,
    required this.child,
    this.focusNode,
    this.width = 160,
    this.height = 96,
    this.autofocus = false,
    this.enabled = true,
    this.onFocused,
    this.revealAncestors = true,
    this.onFixedFocus,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.focusKey,
    this.semanticLabel,
    super.key,
  });

  final String surfaceId;
  final String itemId;
  final FocusMemory memory;
  final Widget child;
  final FocusNode? focusNode;
  final double width;
  final double height;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onFocused;

  /// Rows reveal their header separately from the horizontal card viewport.
  final bool revealAncestors;

  /// TV fixed-focus rows (DESIGN_SPEC §6.4 rule 8): the row scrolls itself to
  /// put this card in its first slot, so the card does no horizontal reveal.
  final VoidCallback? onFixedFocus;
  final VoidCallback? onTap;

  /// Right-click, context-menu key or Shift+F10 on desktop (DESIGN_SPEC §6.3),
  /// with the global point the menu anchors to.
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<Offset>? onLongPress;

  /// Key of the inner [Focus] widget (the test contract's `row-0-item-0`).
  final Key? focusKey;

  /// Accessibility label for the card (e.g. the item's title). `PosterCell`/
  /// `ContinueWatchingCell` render no visible title caption on the tile
  /// itself (`PosterCell.swift:12-15`) — the title only surfaces in the
  /// preview popover — but the tile is still a real activation target and
  /// needs an accessible name regardless of what's painted on it.
  final String? semanticLabel;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard>
    with SingleTickerProviderStateMixin {
  late final bool _ownsFocusNode = widget.focusNode == null;
  late final FocusNode _focusNode =
      widget.focusNode ??
      FocusNode(debugLabel: widget.itemId, skipTraversal: !widget.enabled);
  bool _restorationScheduled = false;
  late final AnimationController _scale = AnimationController(
    vsync: this,
    lowerBound: 1,
    upperBound: RivuletFocusMetrics.standard.tileFocusScaleTv,
    value: 1,
  );
  bool _focused = false;
  bool _hovered = false;

  /// TV: running while Select is held; firing it opens the context menu.
  Timer? _hold;
  bool _selectDown = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.autofocus;
    widget.memory.attach(widget.surfaceId, widget.itemId, _focusNode);
  }

  @override
  void dispose() {
    _hold?.cancel();
    widget.memory.detach(widget.surfaceId, widget.itemId, _focusNode);
    _scale.dispose();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  /// Scale target for the current focus/hover/input state (§4.7, §5.2).
  void _syncScale() {
    final profile = AdaptiveBehavior.of(context);
    final focus = RivuletTokens.of(context).focus;
    final target = _focused && focusRingVisibleFor(profile.inputMode)
        ? (profile.formFactor == FormFactor.tv
              ? focus.tileFocusScaleTv
              : focus.tileFocusScale)
        : _hovered && profile.inputMode == InputMode.pointer
        ? focus.tileHoverScale
        : 1.0;
    _scale.animateTo(
      target,
      duration: effectiveDuration(context, RivuletMotion.press),
      curve: RivuletMotion.easeOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncScale();
    if (_restorationScheduled ||
        widget.memory.lastFocused(widget.surfaceId) != widget.itemId) {
      return;
    }
    _restorationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A row remounting while the user traverses must not steal focus from
      // the card they are on; restoration is for a page that has none.
      final current = FocusManager.instance.primaryFocus?.context;
      if (mounted &&
          !_focusNode.hasFocus &&
          current?.findAncestorWidgetOfExactType<FocusableCard>() == null) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final styles = AppTheme.textStylesOf(context);
    final ring =
        _focused && focusRingVisibleFor(AdaptiveBehavior.of(context).inputMode);
    final highContrast = MediaQuery.highContrastOf(context);
    final radius = BorderRadius.circular(RivuletRadius.medium);
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: widget.enabled,
      onTap: widget.enabled ? _activate : null,
      child: GestureDetector(
        key: ValueKey<String>(widget.itemId),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.enabled ? _activate : null,
        onLongPressStart:
            widget.enabled &&
                (widget.onLongPress != null || widget.onSecondaryTap != null)
            ? (details) => (widget.onLongPress ?? widget.onSecondaryTap)!(
                details.globalPosition,
              )
            : null,
        onSecondaryTapUp: widget.enabled && widget.onSecondaryTap != null
            ? (details) => widget.onSecondaryTap!(details.globalPosition)
            : null,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: MouseRegion(
            // Hover changes appearance only; it never requests focus.
            cursor: widget.enabled
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onEnter: (_) {
              _hovered = true;
              _syncScale();
            },
            onExit: (_) {
              _hovered = false;
              _syncScale();
            },
            child: Focus(
              key: widget.focusKey,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              canRequestFocus: widget.enabled,
              onKeyEvent: _onKeyEvent,
              onFocusChange: (focused) {
                setState(() => _focused = focused);
                _syncScale();
                if (!focused) {
                  widget.memory.leave(widget.surfaceId, widget.itemId);
                }
                if (focused) {
                  widget.memory.remember(widget.surfaceId, widget.itemId);
                  widget.onFocused?.call();
                  widget.onFixedFocus?.call();
                  if (widget.revealAncestors) {
                    _revealMinimal();
                  } else if (widget.onFixedFocus == null) {
                    Scrollable.of(_focusNode.context!).position.ensureVisible(
                      _focusNode.context!.findRenderObject()!,
                      duration: RivuletMotion.base,
                      alignment: 0.5,
                    );
                  }
                }
              },
              child: ScaleTransition(
                scale: _scale,
                child: CustomPaint(
                  foregroundPainter: ring
                      ? FocusRingPainter(radius: radius, color: colors.accent)
                      : null,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: highContrast && _focused
                          ? Border.all(color: colors.textPrimary, width: 3)
                          : null,
                    ),
                    // No clip: the card's art rounds itself and the text under
                    // it must not be cut by the corners.
                    // `.merge`, not the plain constructor: a plain
                    // `DefaultTextStyle` replaces the ambient default
                    // outright and drops the fallback font in tests.
                    child: DefaultTextStyle.merge(
                      style: styles.label,
                      child: widget.child,
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

  /// DESIGN_SPEC §6.4 rule 8: the smallest scroll, in every scrollable above
  /// the card, that shows it with a margin: 48 px (TV 64) vertically (`base`),
  /// one card of peek horizontally (`fast`), both `easeOut`. A fixed-focus
  /// row scrolls itself horizontally instead.
  void _revealMinimal() {
    final context = _focusNode.context;
    if (context == null) return;
    RenderObject? object = context.findRenderObject();
    var scrollable = Scrollable.maybeOf(context);
    while (object is RenderBox && scrollable != null) {
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) return;
      final position = scrollable.position;
      final vertical = position.axis == Axis.vertical;
      if (!vertical && widget.onFixedFocus != null) {
        object = scrollable.context.findRenderObject();
        scrollable = Scrollable.maybeOf(scrollable.context);
        continue;
      }
      // A viewport only has room for the card plus a margin that fits around
      // it; a bigger margin pushes the card half under whatever floats above.
      final margin = vertical
          ? math.min(
              AdaptiveBehavior.of(this.context).formFactor == FormFactor.tv
                  ? 64.0
                  : 48.0,
              math.max(
                0.0,
                (position.viewportDimension - object.size.height) / 2,
              ),
            )
          : widget.width;
      final rect = (Offset.zero & object.size).inflate(margin);
      final atEnd = viewport.getOffsetToReveal(object, 1, rect: rect).offset;
      final atStart = viewport.getOffsetToReveal(object, 0, rect: rect).offset;
      final pixels = position.pixels;
      final target = pixels < atEnd
          ? atEnd
          : pixels > atStart
          ? atStart
          : null;
      if (target != null) {
        scrollPositionTo(
          position,
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: effectiveDuration(
            this.context,
            vertical ? RivuletMotion.base : RivuletMotion.fast,
          ),
          curve: RivuletMotion.easeOut,
        );
      }
      object = scrollable.context.findRenderObject();
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  /// Enter, Space and Select activate the card; the context-menu key and
  /// Shift+F10 open its menu on desktop and phone. On TV, Select held for
  /// [TransportControlButton.longPressThreshold] opens it instead of
  /// activating (DESIGN_SPEC §6.3); the Menu key belongs to the shell there.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final select =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    if (tv && select && widget.enabled && widget.onSecondaryTap != null) {
      return _onTvSelect(event);
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (widget.enabled && select) {
      _activate();
      return KeyEventResult.handled;
    }
    if (widget.onSecondaryTap == null || tv) return KeyEventResult.ignored;
    final menuKey =
        key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed);
    if (!menuKey) return KeyEventResult.ignored;
    _openMenu();
    return KeyEventResult.handled;
  }

  KeyEventResult _onTvSelect(KeyEvent event) {
    if (event is KeyDownEvent) {
      _selectDown = true;
      _hold?.cancel();
      _hold = Timer(TransportControlButton.longPressThreshold, () {
        _hold = null;
        if (mounted) _openMenu();
      });
    } else if (event is KeyUpEvent && _selectDown) {
      _selectDown = false;
      final shortPress = _hold?.isActive ?? false;
      _hold?.cancel();
      _hold = null;
      if (shortPress) _activate();
    }
    return KeyEventResult.handled;
  }

  void _openMenu() {
    final box = context.findRenderObject()! as RenderBox;
    widget.onSecondaryTap!(box.localToGlobal(box.size.center(Offset.zero)));
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onFocused?.call();
    widget.onTap?.call();
  }
}
