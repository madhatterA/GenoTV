import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerHoverEvent, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/app_haptics.dart';

/// Resolves taps through Flutter's gesture arena before toggling chrome.
class PlayerGestureSurface extends StatefulWidget {
  const PlayerGestureSurface({
    required this.child,
    this.overlay,
    required this.chromeVisible,
    required this.onToggleChrome,
    required this.onRevealChrome,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    this.onScrubBackward,
    this.onScrubForward,
    this.onScrubCommit,
    this.onScrubCancel,
    this.onToggleStats,
    this.onKeySeek,
    this.onKeyVolume,
    this.onToggleMute,
    this.onToggleFullscreen,
    this.onToggleSubtitles,
    this.onVolumeSwipe,
    this.onBrightnessSwipe,
    this.onSwipeEnd,
    this.onPinch,
    this.scrubActive = false,
    this.enabled = true,
    this.onTvKey,
    super.key,
  });

  final Widget child;
  final Widget? overlay;
  final bool chromeVisible;
  final bool enabled;

  /// TV: sees every key first (from the surface or any control inside it);
  /// `surfaceFocused` says whether the surface itself holds primary focus.
  final KeyEventResult Function(LogicalKeyboardKey key, bool surfaceFocused)?
  onTvKey;
  final VoidCallback onToggleChrome;
  final VoidCallback onRevealChrome;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final VoidCallback? onScrubBackward;
  final VoidCallback? onScrubForward;
  final VoidCallback? onScrubCommit;
  final VoidCallback? onScrubCancel;

  /// Desktop keys (null on TV/phone): Left/Right seek, Up/Down volume
  /// (+1 / -1 step), M mute, F fullscreen, C subtitles. They act with the
  /// controls hidden too. While [scrubActive] the arrows keep scrubbing.
  final void Function(bool forward)? onKeySeek;
  final void Function(int direction)? onKeyVolume;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleSubtitles;
  final bool scrubActive;

  /// Phone only (null elsewhere): a vertical swipe on the right half calls
  /// [onVolumeSwipe], on the left half [onBrightnessSwipe], with the change
  /// as a fraction of the full range; [onSwipeEnd] fires when it lifts. Swipes
  /// starting within [_edgeGuard] of the top or bottom are left to the OS.
  /// A two-finger pinch calls [onPinch] once with true (out) or false (in).
  final void Function(double delta)? onVolumeSwipe;
  final void Function(double delta)? onBrightnessSwipe;
  final VoidCallback? onSwipeEnd;
  final void Function(bool zoomIn)? onPinch;

  /// The "i" key shows or hides the stats overlay; null leaves the key alone.
  final VoidCallback? onToggleStats;

  @override
  State<PlayerGestureSurface> createState() => _PlayerGestureSurfaceState();
}

const double _edgeGuard = 40;

enum _Swipe { none, volume, brightness }

class _PlayerGestureSurfaceState extends State<PlayerGestureSurface> {
  _Swipe _swipe = _Swipe.none;
  bool _swipeDecided = false;
  Offset _swipeTravel = Offset.zero;
  double _swipeFromX = 0;
  bool _swipeAllowed = false;
  double _pinchScale = 1;
  int _maxPointers = 0;

  bool get _wantsScale =>
      widget.enabled &&
      (widget.onVolumeSwipe != null ||
          widget.onBrightnessSwipe != null ||
          widget.onPinch != null);

  void _scaleStart(ScaleStartDetails d) {
    final size = MediaQuery.sizeOf(context);
    _swipe = _Swipe.none;
    _swipeDecided = false;
    _swipeTravel = Offset.zero;
    _pinchScale = 1;
    _maxPointers = d.pointerCount;
    _swipeFromX = d.localFocalPoint.dx;
    _swipeAllowed =
        d.localFocalPoint.dy > _edgeGuard &&
        d.localFocalPoint.dy < size.height - _edgeGuard;
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    final size = MediaQuery.sizeOf(context);
    if (d.pointerCount > _maxPointers) _maxPointers = d.pointerCount;
    _pinchScale = d.scale;
    if (_maxPointers > 1) {
      _swipe = _Swipe.none;
      return;
    }
    if (!_swipeAllowed) return;
    _swipeTravel += d.focalPointDelta;
    double? delta;
    if (!_swipeDecided) {
      if (_swipeTravel.distance < kTouchSlop) return;
      _swipeDecided = true;
      if (_swipeTravel.dy.abs() > _swipeTravel.dx.abs()) {
        _swipe = _swipeFromX < size.width / 2
            ? (widget.onBrightnessSwipe != null
                  ? _Swipe.brightness
                  : _Swipe.none)
            : (widget.onVolumeSwipe != null ? _Swipe.volume : _Swipe.none);
      }
      // The travel so far (up to the first decided update) counts too.
      delta = -_swipeTravel.dy;
    }
    // A full swipe over 60% of the height covers the whole range.
    delta = (delta ?? -d.focalPointDelta.dy) / (size.height * 0.6);
    switch (_swipe) {
      case _Swipe.volume:
        widget.onVolumeSwipe!(delta);
      case _Swipe.brightness:
        widget.onBrightnessSwipe!(delta);
      case _Swipe.none:
        break;
    }
  }

  void _scaleEnd(ScaleEndDetails d) {
    if (_swipe != _Swipe.none) widget.onSwipeEnd?.call();
    if (_maxPointers > 1 && (_pinchScale > 1.15 || _pinchScale < 0.85)) {
      widget.onPinch?.call(_pinchScale > 1);
    }
    _swipe = _Swipe.none;
    _maxPointers = 0;
  }

  double? _doubleTapX;
  bool _doubleClick = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'player-surface');

  @override
  void initState() {
    super.initState();
    // TV: when no control took focus on arrival (the controls start hidden or
    // unfocusable), the surface must, or no remote key reaches the handler.
    FocusManager.instance.addListener(_keepFocusInPlayer);
    if (widget.onTvKey != null) {
      // Two frames: a control's own autofocus is applied after the first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_focusNode.hasFocus) _focusNode.requestFocus();
        });
      });
      FocusManager.instance.addListener(_reclaimLostFocus);
    }
  }

  DateTime? _lastMouseReveal;

  void _mouseMoved(PointerHoverEvent event) {
    final now = DateTime.now();
    final last = _lastMouseReveal;
    // Every hover event restarts the hide timer, but not every frame rebuilds.
    if (widget.chromeVisible &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastMouseReveal = now;
    widget.onRevealChrome();
  }

  /// The player page covers the app but the pages underneath stay in the tree
  /// and can still request focus (a row rebuilding, say). A key then lands on
  /// a poster behind the video (Space opens it over the player, Esc does
  /// nothing), so focus that moves into a covered page comes straight back.
  void _keepFocusInPlayer() {
    final primary = FocusManager.instance.primaryFocus?.context;
    if (primary == null || !mounted) return;
    final mine = ModalRoute.of(context);
    final theirs = ModalRoute.of(primary);
    if (mine == null || !mine.isCurrent || theirs == null) return;
    if (identical(mine, theirs)) return;
    scheduleMicrotask(() {
      if (mounted && !_focusNode.hasFocus) _focusNode.requestFocus();
    });
  }

  /// TV: a focused control that disappears (hidden, disposed, excluded) must
  /// never leave the remote with nothing to talk to; the surface takes over.
  void _reclaimLostFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    scheduleMicrotask(() {
      final now = FocusManager.instance.primaryFocus;
      if (mounted && (now == null || now is FocusScopeNode)) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(PlayerGestureSurface old) {
    super.didUpdateWidget(old);
    // Controls that just disappeared must not keep the D-pad.
    if (old.chromeVisible && !widget.chromeVisible && widget.onTvKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimLostFocus);
    FocusManager.instance.removeListener(_keepFocusInPlayer);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    autofocus: widget.onTvKey == null,
    skipTraversal: widget.onTvKey != null,
    onKeyEvent: (node, event) {
      if (!widget.enabled) return KeyEventResult.ignored;
      // Desktop: holding Left/Right (the OS repeats the key) scrubs.
      if (event is KeyRepeatEvent &&
          widget.onKeySeek != null &&
          (node.hasPrimaryFocus || !widget.chromeVisible) &&
          (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight)) {
        final nudge = event.logicalKey == LogicalKeyboardKey.arrowRight
            ? widget.onScrubForward
            : widget.onScrubBackward;
        if (nudge == null) return KeyEventResult.ignored;
        nudge();
        return KeyEventResult.handled;
      }
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final tvResult = widget.onTvKey?.call(
        event.logicalKey,
        node.hasPrimaryFocus,
      );
      if (tvResult != null && tvResult != KeyEventResult.ignored) {
        return tvResult;
      }
      if (event.logicalKey == LogicalKeyboardKey.space) {
        widget.onPlayPause();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyI &&
          widget.onToggleStats != null) {
        widget.onToggleStats!();
        return KeyEventResult.handled;
      }
      if (widget.onKeySeek != null &&
          (node.hasPrimaryFocus || !widget.chromeVisible)) {
        final keyboard = HardwareKeyboard.instance;
        if (!keyboard.isControlPressed &&
            !keyboard.isMetaPressed &&
            !keyboard.isAltPressed) {
          final key = event.logicalKey;
          final bool handled;
          if (!widget.scrubActive &&
              (key == LogicalKeyboardKey.arrowLeft ||
                  key == LogicalKeyboardKey.arrowRight)) {
            widget.onKeySeek!(key == LogicalKeyboardKey.arrowRight);
            handled = true;
          } else if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            widget.onKeyVolume?.call(
              key == LogicalKeyboardKey.arrowUp ? 1 : -1,
            );
            handled = widget.onKeyVolume != null;
          } else if (key == LogicalKeyboardKey.keyM &&
              widget.onToggleMute != null) {
            widget.onToggleMute!();
            handled = true;
          } else if (key == LogicalKeyboardKey.keyF &&
              widget.onToggleFullscreen != null) {
            widget.onToggleFullscreen!();
            handled = true;
          } else if (key == LogicalKeyboardKey.keyC &&
              widget.onToggleSubtitles != null) {
            widget.onToggleSubtitles!();
            handled = true;
          } else {
            handled = false;
          }
          if (handled) return KeyEventResult.handled;
        }
      }
      if (!widget.chromeVisible &&
          <LogicalKeyboardKey>{
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
          }.contains(event.logicalKey)) {
        widget.onRevealChrome();
        return KeyEventResult.handled;
      }
      if (widget.chromeVisible && node.hasPrimaryFocus) {
        final callback = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => widget.onScrubBackward,
          LogicalKeyboardKey.arrowRight => widget.onScrubForward,
          LogicalKeyboardKey.enter => widget.onScrubCommit,
          LogicalKeyboardKey.escape => widget.onScrubCancel,
          _ => null,
        };
        if (callback != null) {
          callback();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
    child: MouseRegion(
      // A moving mouse wakes the hidden controls and keeps them up (desktop).
      onHover: widget.enabled ? _mouseMoved : null,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.enabled ? widget.onToggleChrome : null,
            onScaleStart: _wantsScale ? _scaleStart : null,
            onScaleUpdate: _wantsScale ? _scaleUpdate : null,
            onScaleEnd: _wantsScale ? _scaleEnd : null,
            onDoubleTapDown: widget.enabled
                ? (details) {
                    _doubleTapX = details.globalPosition.dx;
                    _doubleClick = details.kind == PointerDeviceKind.mouse;
                  }
                : null,
            onDoubleTap: widget.enabled
                ? () {
                    if (_doubleClick && widget.onToggleFullscreen != null) {
                      widget.onToggleFullscreen!();
                      _doubleTapX = null;
                      return;
                    }
                    final width = MediaQuery.sizeOf(context).width;
                    final x = _doubleTapX;
                    if (x == null) return;
                    if (x < width / 3 || x > width * 2 / 3) {
                      AppHaptics.light(context);
                    }
                    if (x < width / 3) widget.onSeekBackward();
                    if (x > width * 2 / 3) widget.onSeekForward();
                    _doubleTapX = null;
                  }
                : null,
            onDoubleTapCancel: widget.enabled ? () => _doubleTapX = null : null,
            child: widget.child,
          ),
          ?widget.overlay,
        ],
      ),
    ),
  );
}
