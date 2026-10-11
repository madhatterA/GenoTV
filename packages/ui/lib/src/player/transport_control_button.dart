import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/rivulet_tokens.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';

/// Circular icon button for the rail's action row. Idle: translucent dark
/// circle, white glyph. Focused: solid white circle, black glyph, scaled up
/// (`RivuletFocusMetrics.railFocusScale`, 1.15).
///
/// Source: `research/Rivulet/Rivulet/Views/Player/UIKit/TransportControlButton.swift`
/// — default diameter 64 (`:18`), focus scale 1.15 + white bg/black icon
/// swap (`:137-145`), long-press threshold 600 ms (`:34`, `Timer.scheduledTimer`
/// at `:107`): a press held past the threshold fires [onLongPress] and
/// suppresses [onPress]; released before it fires [onPress] instead
/// (`:99-128`).
class TransportControlButton extends StatefulWidget {
  const TransportControlButton({
    required this.icon,
    required this.semanticLabel,
    this.onPress,
    this.onLongPress,
    this.diameter = defaultDiameter,
    this.iconSize = 25,
    this.focusNode,
    this.autofocus = false,
    this.touchTargetEnabled = true,
    super.key,
  });

  /// `TransportControlButton.swift:18` — `static let diameter: CGFloat = 64`.
  static const double defaultDiameter = 64;

  /// `TransportControlButton.swift:34` — `longPressThreshold: TimeInterval = 0.6`.
  static const Duration longPressThreshold = Duration(milliseconds: 600);

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final double diameter;
  final double iconSize;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool touchTargetEnabled;

  @override
  State<TransportControlButton> createState() => _TransportControlButtonState();
}

class _TransportControlButtonState extends State<TransportControlButton> {
  final _touchPortal = OverlayPortalController()..show();
  final _touchLink = LayerLink();
  late final bool _ownsFocusNode = widget.focusNode == null;
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _focused = false;
  bool _down = false;
  Timer? _longPressTimer;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  // A `Timer` (not `DateTime.now()` deltas) — `tester.pump(duration)` in
  // widget tests advances Flutter's fake clock, which every `Timer` obeys,
  // but never the real wall clock, so a `DateTime.now()` comparison would
  // silently never see the threshold elapse under test (see
  // `player_chrome_controller.dart`'s doc comment for the same trap hit and
  // fixed in phase-01). Mirrors `TransportControlButton.swift:99-128`'s own
  // `Timer.scheduledTimer` approach directly.
  void _beginPress() {
    if (widget.onLongPress == null) {
      widget.onPress?.call();
      return;
    }
    _down = true;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(TransportControlButton.longPressThreshold, () {
      if (!_down) return;
      _down = false;
      widget.onLongPress?.call();
    });
  }

  void _endPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (_down) {
      _down = false;
      widget.onPress?.call(); // released before the threshold: normal press.
    }
  }

  void _cancelPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _down = false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final scale = _focused ? tokens.focus.railFocusScale : 1.0;
    final enabled = widget.onPress != null || widget.onLongPress != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : RivuletMotion.press;
    final highContrast = MediaQuery.highContrastOf(context);
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: widget.onPress,
      onLongPress: widget.onLongPress,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (!enabled) return KeyEventResult.ignored;
          final isSelect =
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.space;
          if (!isSelect) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            _beginPress();
            return KeyEventResult.handled;
          }
          if (event is KeyUpEvent) {
            _endPress();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: enabled ? (_) => _beginPress() : null,
          onTapUp: enabled ? (_) => _endPress() : null,
          onTapCancel: enabled ? _cancelPress : null,
          child: AnimatedScale(
            scale: scale,
            duration: duration,
            curve: RivuletMotion.easeOut,
            child: AnimatedContainer(
              duration: duration,
              curve: RivuletMotion.easeOut,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _focused ? Colors.white : colors.railButtonIdle,
                border: highContrast
                    ? Border.all(color: colors.textPrimary, width: 2)
                    : null,
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _focused ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    // The transparent target follows the existing circle without changing
    // the player's measured layout or painting outside its original size.
    if (!widget.touchTargetEnabled ||
        !enabled ||
        AdaptiveBehavior.of(context).formFactor != FormFactor.phone ||
        widget.diameter >= RivuletSizes.touchHitTarget) {
      return button;
    }
    return OverlayPortal(
      controller: _touchPortal,
      overlayChildBuilder: (context) {
        return Positioned.fill(
          child: Align(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
              link: _touchLink,
              targetAnchor: Alignment.center,
              followerAnchor: Alignment.center,
              showWhenUnlinked: false,
              child: Semantics(
                container: true,
                button: true,
                enabled: enabled,
                label: widget.semanticLabel,
                onTap: widget.onPress,
                onLongPress: widget.onLongPress,
                child: GestureDetector(
                  key: ValueKey('phone-hit-${widget.semanticLabel}'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTapDown: (_) => _beginPress(),
                  onTapUp: (_) => _endPress(),
                  onTapCancel: _cancelPress,
                  child: const SizedBox.square(
                    dimension: RivuletSizes.touchHitTarget,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _touchLink,
        child: ExcludeSemantics(child: button),
      ),
    );
  }
}
