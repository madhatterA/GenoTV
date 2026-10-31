import '../platform/siri_remote.dart';

/// Siri Remote touch-surface scrubbing (Infuse style): a horizontal swipe moves
/// a preview position, lifting the finger commits it.
class SwipeScrub {
  SwipeScrub({required this.currentPosition, required this.duration});

  final Duration Function() currentPosition;
  final Duration Function() duration;

  /// Seconds moved by dragging across the whole pad width (x from -1 to 1).
  static const double secondsPerPad = 240;

  /// Drag below this (in x units) is a resting finger, not a scrub.
  static const double deadZone = 0.15;

  double? _startX;
  Duration _base = Duration.zero;
  Duration? _preview;

  /// Where a release would seek to; null when no scrub is in progress.
  Duration? get preview => _preview;

  /// Feeds one touch. Returns what changed: [SwipeScrubEvent.update] while the
  /// preview moves, [SwipeScrubEvent.commit] on release after a scrub (read
  /// [preview] before the next touch), [SwipeScrubEvent.cancel] when it ends
  /// without one.
  SwipeScrubEvent? add(SiriTouch touch) {
    switch (touch.phase) {
      case 'started':
        _startX = touch.x;
        _base = currentPosition();
        _preview = null;
        return null;
      case 'move':
        final start = _startX;
        if (start == null) return null;
        final dx = touch.x - start;
        if (_preview == null && dx.abs() < deadZone) return null;
        final total = duration();
        var target = _base + Duration(seconds: (dx * secondsPerPad).round());
        if (target < Duration.zero) target = Duration.zero;
        if (total > Duration.zero && target > total) target = total;
        _preview = target;
        return SwipeScrubEvent.update;
      case 'ended':
        final scrubbed = _preview != null;
        _startX = null;
        return scrubbed ? SwipeScrubEvent.commit : null;
      // A physical click is a button press, never a scrub: the finger drifts
      // while it presses, and that drift must not seek or hide the controls.
      case 'click_s' || 'click_e' || 'cancelled':
        final scrubbed = _preview != null;
        _startX = null;
        _preview = null;
        return scrubbed ? SwipeScrubEvent.cancel : null;
    }
    return null;
  }

  /// Forget the preview after a commit has been applied.
  void clear() => _preview = null;
}

enum SwipeScrubEvent { update, commit, cancel }
