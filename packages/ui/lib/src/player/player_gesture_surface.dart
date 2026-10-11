import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// The "i" key shows or hides the stats overlay; null leaves the key alone.
  final VoidCallback? onToggleStats;

  @override
  State<PlayerGestureSurface> createState() => _PlayerGestureSurfaceState();
}

class _PlayerGestureSurfaceState extends State<PlayerGestureSurface> {
  double? _doubleTapX;
  final FocusNode _focusNode = FocusNode(debugLabel: 'player-surface');

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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    autofocus: widget.onTvKey == null,
    skipTraversal: widget.onTvKey != null,
    onKeyEvent: (node, event) {
      if (!widget.enabled || event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }
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
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.enabled ? widget.onToggleChrome : null,
          onDoubleTapDown: widget.enabled
              ? (details) => _doubleTapX = details.globalPosition.dx
              : null,
          onDoubleTap: widget.enabled
              ? () {
                  final width = MediaQuery.sizeOf(context).width;
                  final x = _doubleTapX;
                  if (x == null) return;
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
  );
}
