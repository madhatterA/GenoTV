import '../l10n/app_text.dart';
import '../l10n_gen/app_strings.dart';
import '../l10n_gen/app_strings_en.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/tinted_surface.dart';
import '../models/ui_media.dart';
import '../theme/rivulet_tokens.dart';

/// The label Rivulet shows for each marker kind.
///
/// `UiMarker`/`UiMarkerKind` (`../models/ui_media.dart`) is Part 04's own
/// skip-marker data model — the playback contract (`packages/contracts`)
/// carries chapters only, no skippable-marker concept, so this pill's marker
/// list is supplied by the caller, not read off `PlaybackState`.
String skipLabelFor(UiMarkerKind kind, {AppStrings? strings}) => switch (kind) {
  UiMarkerKind.intro => (strings ?? AppStringsEn()).player_skipIntro,
  UiMarkerKind.credits => (strings ?? AppStringsEn()).player_skipCredits,
  UiMarkerKind.commercial => (strings ?? AppStringsEn()).player_skip,
};

/// Returns the marker [position] currently falls inside (`start <= position
/// < end`), or `null`. Markers are assumed non-overlapping; the first match
/// wins if they are not.
UiMarker? activeMarkerAt(List<UiMarker> markers, Duration position) {
  for (final marker in markers) {
    if (position >= marker.start && position < marker.end) return marker;
  }
  return null;
}

/// Rivulet's floating "Skip Intro" / "Skip Credits" / "Skip" capsule.
///
/// Source: `research/Rivulet/Rivulet/Views/Player/UIKit/SkipPillButton.swift`
/// — glass pill, 26pt semibold title, 16/34 vertical/horizontal content
/// insets (`:78-80`), 1.05x focus scale (`:176`), and the Select-consumption
/// shape ported in this widget's `onKeyEvent` (`:135-163`: swallow the
/// Select key-down, act and consume on key-up, so the release that follows a
/// skip cannot also reveal the rail).
///
/// This widget renders and drives itself (fill sweep, focus, key handling);
/// it does not position itself — the caller (`PlayerScreen`) places it with
/// the raised/lowered offsets from
/// `PlayerContainerViewController.swift:650-653`
/// (`skipPillRaisedOffset = -20`, `skipPillLoweredOffset = 200`, both
/// relative to the rail's top edge) via [skipPillRaisedOffset] /
/// [skipPillLoweredOffset].
class SkipMarkerButton extends StatefulWidget {
  const SkipMarkerButton({
    required this.marker,
    required this.onSkip,
    this.position,
    this.autoSkipDuration,
    this.isPaused = false,
    this.onDirectionalPress,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// `PlayerContainerViewController.swift:650` — pill top sits 20pt ABOVE
  /// the rail's top edge while the rail is visible.
  static const double skipPillRaisedOffset = -20;

  /// `PlayerContainerViewController.swift:653` — pill top sits 200pt BELOW
  /// the rail's top edge while chrome is hidden (lower over the scrubber).
  static const double skipPillLoweredOffset = 200;

  /// `SkipPillButton.swift:79` — `.systemFont(ofSize: 26, weight: .semibold)`.
  static const double titleFontSize = 26;

  /// `SkipPillButton.swift:80` — `UIEdgeInsets(top: 16, left: 34, bottom:
  /// 16, right: 34)`.
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: 34,
    vertical: 16,
  );

  /// `SkipPillButton.swift:176` — `CGAffineTransform(scaleX: 1.05, y: 1.05)`.
  static const double focusScale = 1.05;

  final UiMarker marker;

  /// Live playback position, only used to compute the auto-fill sweep's
  /// remaining duration when the pill is first shown mid-countdown. The
  /// caller still owns show/hide (only mounting this widget while the
  /// marker is active).
  final Duration? position;

  /// Fired exactly once, on Select release or a tap, never on the
  /// press-down (`SkipPillButton.swift:135-163`'s "swallow down, act on
  /// up" shape).
  final VoidCallback onSkip;

  /// Non-null enables the auto-skip countdown fill; the pill fires
  /// [onSkip] itself, exactly once, when the fill completes (unless
  /// paused/cancelled by unmounting or a new marker).
  final Duration? autoSkipDuration;
  final bool isPaused;

  /// Up/Down while this pill holds focus. Returning `true` consumes the
  /// press (chrome hidden → reveal controls); returning `false`/`null`
  /// lets the focus engine move focus normally (chrome up → Down returns
  /// to the rail). Left/Right are never offered here — they fall through
  /// to the container's seek gestures (`SkipPillButton.swift:29`).
  final bool Function(LogicalKeyboardKey key)? onDirectionalPress;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<SkipMarkerButton> createState() => _SkipMarkerButtonState();
}

class _SkipMarkerButtonState extends State<SkipMarkerButton>
    with SingleTickerProviderStateMixin {
  late final bool _ownsFocusNode = widget.focusNode == null;
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final AnimationController _fill =
      AnimationController(
        vsync: this,
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        // Fires once per completed sweep; `stop()` (skip/cancel) and
        // unmounting never reach `completed`, so a cancelled countdown never
        // skips.
        if (status == AnimationStatus.completed && mounted) _fireSkip();
      });
  bool _focused = false;
  LogicalKeyboardKey? _selectKey;
  bool _fired = false;
  String? _pressedMarkerId;

  @override
  void initState() {
    super.initState();
    _startFillIfNeeded();
  }

  @override
  void didUpdateWidget(covariant SkipMarkerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker.id != widget.marker.id) {
      _fired = false;
    }
    if (oldWidget.marker.id != widget.marker.id ||
        oldWidget.autoSkipDuration != widget.autoSkipDuration) {
      _fill.stop();
      _fill.value = 0;
      _startFillIfNeeded();
    } else if (oldWidget.isPaused != widget.isPaused) {
      if (widget.isPaused) {
        _fill.stop();
      } else if (!_fired &&
          widget.autoSkipDuration != null &&
          widget.autoSkipDuration! > Duration.zero) {
        _fill.forward();
      }
    }
  }

  void _startFillIfNeeded() {
    final duration = widget.autoSkipDuration;
    if (_fired || duration == null || duration <= Duration.zero) return;
    _fill.duration = duration;
    if (!widget.isPaused) _fill.forward(from: 0);
  }

  void _fireSkip() {
    if (_fired) return;
    _fired = true;
    _fill.stop();
    widget.onSkip();
  }

  @override
  void dispose() {
    _fill.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  // Keep ownership of a held Select through unmount until its release.
  KeyEventResult _consumeSelectRelease(KeyEvent event) {
    if (event.logicalKey != _selectKey) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _selectKey = null;
      FocusManager.instance.removeEarlyKeyEventHandler(_consumeSelectRelease);
      if (mounted && widget.marker.id == _pressedMarkerId) _fireSkip();
      _pressedMarkerId = null;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isSelect =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
    if (isSelect) {
      if (event is KeyDownEvent) {
        // Swallow the down (`SkipPillButton.swift:135-144`): acting here
        // would hand focus back mid-press, letting the matching up land on
        // the container's tap-to-reveal gesture instead of staying
        // consumed by this pill.
        _selectKey = key;
        _pressedMarkerId = widget.marker.id;
        FocusManager.instance.addEarlyKeyEventHandler(_consumeSelectRelease);
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent &&
          (widget.onDirectionalPress?.call(key) ?? false)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Left/Right always fall through to the seek gestures owned elsewhere.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    return Semantics(
      button: true,
      label: skipLabelFor(widget.marker.kind, strings: AppStrings.of(context)),
      onTap: _fireSkip,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _handleKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _fireSkip,
          child: AnimatedScale(
            scale: _focused ? SkipMarkerButton.focusScale : 1.0,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _fill,
              builder: (context, _) => TintedSurface.overMedia(
                radius: RivuletRadius.full,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RivuletRadius.full),
                  child: Stack(
                    children: <Widget>[
                      AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: _focused
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                        padding: SkipMarkerButton.contentPadding,
                        child: AppText(
                          skipLabelFor(
                            widget.marker.kind,
                            strings: AppStrings.of(context),
                          ),
                          style: tokens.typeStyles.body.copyWith(
                            fontSize: SkipMarkerButton.titleFontSize,
                            fontWeight: FontWeight.w600,
                            color: _focused ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                      if (_fill.value > 0)
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _fill.value.clamp(0.0, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _focused
                                    ? Colors.black.withValues(alpha: 0.12)
                                    : Colors.white.withValues(alpha: 0.35),
                              ),
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
    );
  }
}
