import 'dart:async';

import 'package:contracts/contracts.dart';

import '../focus/ui_command.dart';

/// Skip-length choices exposed in Settings → Playback → Skip Length.
/// Source: `SkipInterval` (research/Rivulet/Rivulet/Views/Settings/SettingsModels.swift:107-118).
const List<int> kAllowedTapSeekSeconds = <int>[5, 10, 15, 30];

/// Default tap-seek step, matching `SkipInterval.defaultValue`.
/// Source: SettingsModels.swift:115.
const int kDefaultTapSeekSeconds = 30;

/// Fixed J/L "big jump" step used when no chapter exists to snap to.
/// Source: `InputConfig.jumpSeekSeconds` (research/Rivulet/Rivulet/Config/InputConfig.swift:35).
const int kJumpSeekSeconds = 30;

/// Backward chapter jump ignores a boundary within this window of the
/// current position (repeated presses step chapter-by-chapter instead of
/// re-landing on the one just crossed).
/// Source: `ChapterNavigator.swift:14-16`.
const Duration kChapterBackExclusion = Duration(seconds: 2);

/// Window over which a burst of step-seek presses collapses into one
/// controller seek call.
/// Source: `InputConfig.seekCoalesceInterval` (InputConfig.swift:15).
const Duration kSeekCoalesceInterval = Duration(milliseconds: 50);

/// Normalizes tap/jump/chapter seek intents into calls on [PlaybackController.seek].
///
/// [InputRouter] (`src/focus/input_router.dart`) already dedupes and coalesces
/// *key-sourced* step-seek bursts before they reach here. This controller adds
/// its own 50 ms burst coalescer on top because pointer/touch sources call
/// [handleCommand] directly (see the doc comment on `UiCommand`), bypassing
/// the router's key-repeat coalescer entirely — so a fast run of on-screen
/// tap-seek button presses must still collapse to one controller call here.
class SeekController {
  SeekController({
    required this.controller,
    this.tapSeekSeconds = kDefaultTapSeekSeconds,
  }) : assert(
         kAllowedTapSeekSeconds.contains(tapSeekSeconds),
         'tapSeekSeconds must be one of $kAllowedTapSeekSeconds',
       );

  final PlaybackController controller;
  final int tapSeekSeconds;

  Duration _pendingDelta = Duration.zero;
  Timer? _coalesceTimer;

  /// Feed one normalized command. Commands this controller does not own are
  /// ignored so it can share an [UiCommand] stream with [ShuttleController]
  /// and wheel handling.
  void handleCommand(UiCommand command) {
    switch (command.type) {
      case UiCommandType.stepSeekForward:
        _queueRelative(Duration(seconds: tapSeekSeconds * command.repeatCount));
      case UiCommandType.stepSeekBackward:
        _queueRelative(
          Duration(seconds: -tapSeekSeconds * command.repeatCount),
        );
      case UiCommandType.jumpSeekForward:
        chapterJump(forward: true);
      case UiCommandType.jumpSeekBackward:
        chapterJump(forward: false);
      default:
        break;
    }
  }

  void _queueRelative(Duration delta) {
    _pendingDelta += delta;
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(kSeekCoalesceInterval, _flush);
  }

  Future<void> _flush() async {
    _coalesceTimer = null;
    if (_pendingDelta == Duration.zero) return;
    final delta = _pendingDelta;
    _pendingDelta = Duration.zero;
    final state = controller.currentState;
    await controller.seek(_clamp(state.position + delta, state.duration));
  }

  /// Forward selects the first chapter boundary greater than the current
  /// position. Backward selects the previous boundary, excluding one within
  /// [kChapterBackExclusion] of the current position (so a repeat press
  /// steps chapter-by-chapter instead of re-landing on the boundary just
  /// crossed). With no chapters, falls back to a fixed 30 s jump.
  /// Source: `ChapterNavigator.snapTarget` (ChapterNavigator.swift:16-24).
  Future<void> chapterJump({required bool forward}) async {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _pendingDelta = Duration.zero;
    final state = controller.currentState;
    final starts = state.chapters.map((c) => c.start).toList();
    final snapped = chapterTarget(
      from: state.position,
      chapterStarts: starts,
      forward: forward,
    );
    final target =
        snapped ??
        state.position +
            Duration(seconds: forward ? kJumpSeekSeconds : -kJumpSeekSeconds);
    await controller.seek(_clamp(target, state.duration));
  }

  /// Pure chapter-snap targeting, exposed for direct table-testing.
  static Duration? chapterTarget({
    required Duration from,
    required List<Duration> chapterStarts,
    required bool forward,
  }) {
    final sorted = List<Duration>.of(chapterStarts)..sort();
    if (forward) {
      for (final start in sorted) {
        if (start > from) return start;
      }
      return null;
    }
    Duration? candidate;
    final cutoff = from - kChapterBackExclusion;
    for (final start in sorted) {
      if (start < cutoff) candidate = start;
    }
    return candidate;
  }

  static Duration _clamp(Duration value, Duration duration) {
    if (value < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  void dispose() {
    _coalesceTimer?.cancel();
  }
}
