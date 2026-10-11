import 'dart:async';

import 'package:contracts/contracts.dart';

/// Debounces noisy native buffering flags. A short assertion is required to
/// enter buffering; clearing it is slower so one cache update cannot flash the
/// spinner while playback is otherwise healthy.
final class BufferingDebouncer {
  BufferingDebouncer({
    required this.onChanged,
    this.enterDelay = const Duration(milliseconds: 200),
    this.exitDelay = const Duration(seconds: 2),
  });

  final void Function(bool buffering) onChanged;
  final Duration enterDelay;
  final Duration exitDelay;
  Timer? _timer;
  bool _value = false;
  bool _candidate = false;

  bool get value => _value;

  void update({required bool engineBuffering, required bool isPlaying}) {
    final desired = isPlaying && engineBuffering;
    if (desired == _value) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (desired == _candidate && _timer != null) return;
    _candidate = desired;
    _timer?.cancel();
    final delay = desired ? enterDelay : exitDelay;
    if (delay == Duration.zero) {
      _commit(desired);
      return;
    }
    _timer = Timer(delay, () => _commit(desired));
  }

  void _commit(bool value) {
    _timer = null;
    _value = value;
    onChanged(value);
  }

  void dispose() => _timer?.cancel();
}

/// Buffer state is derived from the engine's decoded cache only. The
/// downloader's byte availability lives on a separate source status in Part
/// 03 and is a different number; this file never sees it.
PlaybackState applyEngineBuffer(
  PlaybackState state, {
  required bool engineBuffering,
  required Duration buffer,
}) => applyBuffered(applyBuffering(state, engineBuffering), buffer);

PlaybackState applyBuffering(PlaybackState state, bool buffering) =>
    state.copyWith(isBuffering: state.isPlaying && buffering);

PlaybackState applyBuffered(PlaybackState state, Duration buffer) {
  // media_kit's buffer is the absolute demuxer-cache position, not the
  // duration ahead of the play head.
  final ahead = buffer - state.position;
  final remaining = state.duration - state.position;
  final maximum = remaining.isNegative ? Duration.zero : remaining;
  final safe = ahead.isNegative ? Duration.zero : ahead;
  return state.copyWith(bufferedAhead: safe > maximum ? maximum : safe);
}

/// mpv `cache-buffering-state` (0-100, percent of the cache needed before
/// playback resumes) as 0..1; null when mpv gives no number.
double? bufferingProgressFromMpv(String raw) {
  final percent = double.tryParse(raw);
  return percent == null ? null : (percent / 100).clamp(0.0, 1.0);
}
