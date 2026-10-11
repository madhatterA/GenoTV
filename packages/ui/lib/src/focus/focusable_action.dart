import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';

/// Whether the focus ring shows for [mode]: keyboard and remote only
/// (DESIGN_SPEC §4.7, §6.3).
bool focusRingVisibleFor(InputMode mode) =>
    mode == InputMode.keyboard || mode == InputMode.remote;

/// The focus ring (DESIGN_SPEC §4.7): a 2 px stroke offset 3 px outside the
/// widget, corner radius = widget radius + 3. Painted by the focused widget
/// itself as a foreground, so there is no overlay and no per-frame callback.
class FocusRingPainter extends CustomPainter {
  const FocusRingPainter({required this.radius, required this.color});

  static const double thickness = 2;
  static const double offset = 3;

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(offset);
    canvas.drawRRect(
      (radius + BorderRadius.circular(offset)).toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.radius != radius || old.color != color;
}

/// Draws the [FocusRingPainter] around any control that keeps its own focus
/// handling (a Material button, an `InkWell`, a text field): the ring shows
/// while a descendant has focus in keyboard or remote mode (DESIGN_SPEC §4.7).
class FocusRing extends StatefulWidget {
  const FocusRing({
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(RivuletRadius.small)),
    super.key,
  });

  final Widget child;
  final BorderRadius radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ring =
        _focused && focusRingVisibleFor(AdaptiveBehavior.of(context).inputMode);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: CustomPaint(
        foregroundPainter: ring
            ? FocusRingPainter(
                radius: widget.radius,
                color: RivuletTokens.of(context).colors.accent,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

/// A generic focusable/activatable control: owns its focus node, exposes
/// button semantics, and plays the press feedback of DESIGN_SPEC §5.2 —
/// scale to `RivuletFocusMetrics.pressScale` (0.97) on press-down, back on
/// release, 120 ms `easeOut` — as a paint transform, never a resize.
///
/// Focus (keyboard/remote only) paints the [FocusRingPainter] and the
/// `tintFillHover` background; pointer hover shows the same background and
/// the click cursor. The scale never changes on focus (cards do that, see
/// `FocusableCard`).
class FocusableAction extends StatefulWidget {
  const FocusableAction({
    required this.child,
    this.onActivate,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.canRequestFocus = true,
    this.skipTraversal = false,
    this.semanticLabel,
    this.minSize = 44.0,
    this.centered = false,
    this.focusRadius = const BorderRadius.all(
      Radius.circular(RivuletRadius.small),
    ),
    super.key,
  });

  final Widget child;

  /// Invoked on Select activation (key up after a non-hold press, Enter,
  /// tap, or click) — never on press-down alone.
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// False keeps the control clickable but out of focus entirely (the hero's
  /// secondary buttons until focus has entered the hero).
  final bool canRequestFocus;

  /// True keeps the control clickable and focusable by request, but skipped by
  /// arrow and Tab traversal.
  final bool skipTraversal;
  final String? semanticLabel;

  /// Minimum logical-pixel touch target on both axes.
  final double minSize;

  /// Keeps [child] at its own size, centred inside a hit area of [minSize]
  /// (a 44 px circle with a 48 px hit target). Off: the child fills it.
  final bool centered;

  /// Corner radius of the focus ring and hover background, matching the
  /// wrapped control's own shape.
  final BorderRadius focusRadius;

  @override
  State<FocusableAction> createState() => _FocusableActionState();
}

class _FocusableActionState extends State<FocusableAction>
    with SingleTickerProviderStateMixin {
  late final bool _ownsFocusNode = widget.focusNode == null;
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final AnimationController _scale = AnimationController(
    vsync: this,
    lowerBound: RivuletFocusMetrics.standard.pressScale,
    upperBound: 1,
    value: 1,
  );
  bool _focused = false;
  bool _pressed = false;
  bool _hovered = false;

  @override
  void dispose() {
    _scale.dispose();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    _scale.animateTo(
      pressed ? _scale.lowerBound : 1,
      duration: effectiveDuration(context, RivuletMotion.press),
      curve: RivuletMotion.easeOut,
    );
  }

  void _activate() {
    if (!widget.enabled) return;
    widget.onActivate?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final profile = AdaptiveBehavior.of(context);
    final mode = profile.inputMode;
    final minSize = widget.minSize
        .clamp(AdaptiveBehavior.hitTargetOf(context), double.infinity)
        .toDouble();
    final ring = _focused && focusRingVisibleFor(mode);
    final highlighted =
        ring ||
        _pressed ||
        (_hovered && mode == InputMode.pointer && widget.enabled);
    Widget body = ScaleTransition(
      scale: _scale,
      child: CustomPaint(
        foregroundPainter: ring
            ? FocusRingPainter(radius: widget.focusRadius, color: colors.accent)
            : null,
        child: AnimatedContainer(
          duration: effectiveDuration(context, RivuletMotion.fast),
          foregroundDecoration: BoxDecoration(
            color: highlighted ? colors.tintFillHover : Colors.transparent,
            borderRadius: widget.focusRadius,
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.4,
            child: widget.child,
          ),
        ),
      ),
    );
    if (widget.centered || minSize > widget.minSize) {
      body = Center(widthFactor: 1, heightFactor: 1, child: body);
    }
    // MergeSemantics: `Focus` and `GestureDetector` add their own child
    // nodes (focus/tap, no label), which fail "tappable has a label"; one
    // merged node carries the label, button flag and both actions.
    return MergeSemantics(
      child: Semantics(
        enabled: widget.enabled,
        button: true,
        label: widget.semanticLabel,
        onTap: widget.enabled ? _activate : null,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: widget.enabled && widget.canRequestFocus,
          skipTraversal: widget.skipTraversal,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (node, event) {
            if (!widget.enabled) return KeyEventResult.ignored;
            final isSelect =
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.space;
            if (!isSelect) return KeyEventResult.ignored;
            if (event is KeyDownEvent) {
              _setPressed(true);
              return KeyEventResult.handled;
            }
            if (event is KeyUpEvent) {
              final wasPressed = _pressed;
              _setPressed(false);
              if (wasPressed) _activate();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: widget.enabled
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
              onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
              onTapCancel: widget.enabled ? () => _setPressed(false) : null,
              onTap: widget.enabled ? _activate : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minSize,
                  minHeight: minSize,
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Key handler for a plain [Focus] that wraps an `InkWell`/`GestureDetector`:
/// the D-pad Select/Enter press activates [onActivate] on key up (the inner
/// widget's own activation never sees a key while the outer node holds focus).
KeyEventResult Function(FocusNode, KeyEvent) activateOnSelect(
  VoidCallback? onActivate,
) => (node, event) {
  final isSelect =
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.select;
  if (!isSelect || onActivate == null) return KeyEventResult.ignored;
  if (event is KeyUpEvent) onActivate();
  return KeyEventResult.handled;
};
