import 'dart:async';

import 'package:flutter/services.dart';

import '../navigation/back_dispatcher.dart';
import '../theme/rivulet_tokens.dart';
import 'ui_command.dart';

/// Translates raw hardware key events into [UiCommand]s: one deterministic
/// pipeline shared by D-pad, keyboard, and gamepad-style key sources.
/// Pointer/touch widgets skip the key-mapping step and call [emit] directly
/// with the semantic command they already know they mean — see step 4 of
/// `planning/part-04-ui/chapter-01-app-shell/phase-03-focus-system.md`.
///
/// Timing constants source: `research/Rivulet/Rivulet/Config/InputConfig.swift`.
/// Tap-vs-hold state machine source (per-direction hold timer that fires
/// once and suppresses the matching tap): `DirectionalPressDetector.swift`.
/// This router tracks one such state machine per physical key rather than
/// Rivulet's single shared slot — a real keyboard can hold both arrow keys
/// independently, unlike a single remote directional pad.
final class InputRouter {
  InputRouter({
    required this.onCommand,
    this.backDispatcher,
    RivuletMotion motion = RivuletMotion.standard,
  }) : holdThreshold = motion.holdThreshold,
       seekCoalesceInterval = motion.seekCoalesce,
       actionDedupeWindow = motion.actionDedupe,
       transportDedupeWindow = motion.transportDedupe,
       scrubNudgeDedupeWindow = motion.scrubNudgeDedupe;

  /// Called with every command that survives dedupe and (for [UiCommandType.menuBack])
  /// is not consumed by [backDispatcher].
  final void Function(UiCommand command) onCommand;

  /// When set, [UiCommandType.menuBack] is offered to the dispatcher first;
  /// the newest registered handler gets first refusal, and only an
  /// unconsumed Back reaches [onCommand]. See `back_dispatcher.dart`.
  final BackDispatcher? backDispatcher;

  // Timing values come from `RivuletMotion`, already cited there to
  // `research/Rivulet/Rivulet/Config/InputConfig.swift` (holdThreshold:14,
  // seekCoalesce:15, actionDedupe:16, transportDedupe:17, scrubNudgeDedupe:28)
  // — kept as one source of truth instead of a second set of literals here.
  final Duration holdThreshold;
  final Duration seekCoalesceInterval;
  final Duration actionDedupeWindow;
  final Duration transportDedupeWindow;
  final Duration scrubNudgeDedupeWindow;

  static final Set<LogicalKeyboardKey> _holdableKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  static final Set<LogicalKeyboardKey> _selectKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.space,
  };

  final Set<LogicalKeyboardKey> _down = <LogicalKeyboardKey>{};
  final Map<LogicalKeyboardKey, Timer> _holdTimers =
      <LogicalKeyboardKey, Timer>{};
  final Set<LogicalKeyboardKey> _holdFired = <LogicalKeyboardKey>{};

  final Map<UiCommandType, Duration> _lastEmitted = <UiCommandType, Duration>{};

  final Map<UiCommandType, Timer> _coalesceTimers = <UiCommandType, Timer>{};
  final Map<UiCommandType, int> _coalesceCounts = <UiCommandType, int>{};
  final Map<UiCommandType, Duration> _coalesceTimestamps =
      <UiCommandType, Duration>{};
  final Map<UiCommandType, CommandSource> _coalesceSources =
      <UiCommandType, CommandSource>{};

  /// Feed one physical key transition. [timestamp] is monotonic and
  /// caller-supplied — production code passes real elapsed time, tests pass
  /// controlled values, so dedupe math never depends on wall-clock timing.
  void handleKeyEvent(
    LogicalKeyboardKey key, {
    required bool down,
    required Duration timestamp,
    CommandSource source = CommandSource.keyboard,
  }) {
    if (down) {
      // Key-repeat (OS auto-repeat while the key is held) must never
      // restart the hold timer — only a transition from up to down does.
      if (!_down.add(key)) return;
      if (_holdableKeys.contains(key)) {
        _holdFired.remove(key);
        _holdTimers[key]?.cancel();
        _holdTimers[key] = Timer(holdThreshold, () {
          _holdFired.add(key);
          _holdTimers.remove(key);
          final forward = key == LogicalKeyboardKey.arrowRight;
          emit(
            forward
                ? UiCommandType.scrubNudgeForward
                : UiCommandType.scrubNudgeBackward,
            source: source,
            timestamp: timestamp + holdThreshold,
          );
        });
        return;
      }
      _emitImmediate(key, down: true, source: source, timestamp: timestamp);
      return;
    }

    // Key up.
    _down.remove(key);
    if (_holdableKeys.contains(key)) {
      _holdTimers.remove(key)?.cancel();
      // Never emit tap after a completed hold.
      if (!_holdFired.remove(key)) {
        final forward = key == LogicalKeyboardKey.arrowRight;
        _coalesceStepSeek(forward, source, timestamp);
      }
      return;
    }
    _emitImmediate(key, down: false, source: source, timestamp: timestamp);
  }

  void _emitImmediate(
    LogicalKeyboardKey key, {
    required bool down,
    required CommandSource source,
    required Duration timestamp,
  }) {
    if (key == LogicalKeyboardKey.arrowUp) {
      if (down)
        emit(UiCommandType.directionUp, source: source, timestamp: timestamp);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (down)
        emit(UiCommandType.directionDown, source: source, timestamp: timestamp);
      return;
    }
    if (_selectKeys.contains(key)) {
      emit(
        down ? UiCommandType.selectDown : UiCommandType.selectUp,
        source: source,
        timestamp: timestamp,
      );
      return;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      if (down)
        emit(UiCommandType.menuBack, source: source, timestamp: timestamp);
      return;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (down)
        emit(UiCommandType.playPause, source: source, timestamp: timestamp);
      return;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      if (down)
        emit(
          UiCommandType.jumpSeekBackward,
          source: source,
          timestamp: timestamp,
        );
      return;
    }
    if (key == LogicalKeyboardKey.keyL) {
      if (down)
        emit(
          UiCommandType.jumpSeekForward,
          source: source,
          timestamp: timestamp,
        );
      return;
    }
    if (key == LogicalKeyboardKey.keyI) {
      if (down) emit(UiCommandType.info, source: source, timestamp: timestamp);
      return;
    }
  }

  void _coalesceStepSeek(
    bool forward,
    CommandSource source,
    Duration timestamp,
  ) {
    final type = forward
        ? UiCommandType.stepSeekForward
        : UiCommandType.stepSeekBackward;
    _coalesceCounts[type] = (_coalesceCounts[type] ?? 0) + 1;
    _coalesceTimestamps[type] = timestamp;
    _coalesceSources[type] = source;
    _coalesceTimers[type]?.cancel();
    _coalesceTimers[type] = Timer(seekCoalesceInterval, () {
      _coalesceTimers.remove(type);
      final count = _coalesceCounts.remove(type) ?? 1;
      final ts = _coalesceTimestamps.remove(type) ?? timestamp;
      final src = _coalesceSources.remove(type) ?? source;
      emit(type, source: src, timestamp: ts, repeatCount: count);
    });
  }

  /// Entry point for a command already known semantically — pointer/touch
  /// activation, or a key mapping above. Applies the same dedupe rules and
  /// Back-priority routing regardless of where the command came from.
  void emit(
    UiCommandType type, {
    required CommandSource source,
    required Duration timestamp,
    int repeatCount = 1,
  }) {
    final cls = dedupeClassOf(type);
    if (cls != DedupeClass.none) {
      final window = switch (cls) {
        DedupeClass.action => actionDedupeWindow,
        DedupeClass.transport => transportDedupeWindow,
        DedupeClass.scrubNudge => scrubNudgeDedupeWindow,
        DedupeClass.none => Duration.zero,
      };
      final last = _lastEmitted[type];
      if (last != null && timestamp >= last && (timestamp - last) <= window) {
        return; // duplicate within the locked window — dropped
      }
    }
    _lastEmitted[type] = timestamp;

    if (type == UiCommandType.menuBack &&
        backDispatcher != null &&
        backDispatcher!.dispatch()) {
      return; // the newest visible consumer took first refusal
    }
    onCommand(
      UiCommand(
        type,
        source: source,
        timestamp: timestamp,
        repeatCount: repeatCount,
      ),
    );
  }

  /// Releases all pending timers. Call from the owning widget's `dispose`.
  void dispose() {
    for (final timer in _holdTimers.values) {
      timer.cancel();
    }
    for (final timer in _coalesceTimers.values) {
      timer.cancel();
    }
    _holdTimers.clear();
    _coalesceTimers.clear();
  }
}
