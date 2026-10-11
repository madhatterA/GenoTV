import 'dart:async';
import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';

import '../focus/ui_command.dart';

/// Pure FF/RW shuttle grammar: click-and-hold enters shuttle at level 1,
/// clicks in the same direction bump up to the level-3 cap, clicks in the
/// opposite direction step down THROUGH zero into the opposite direction.
/// Badges show the human ladder (2x/4x/6x); actual cruise rates are
/// 15x/60x/240x realtime.
/// Source: `research/Rivulet/Rivulet/Services/Input/ShuttleGrammar.swift`.
abstract final class ShuttleGrammar {
  static const int maxLevel = 3;

  /// Badge numbers shown to the user per level (index 0 unused).
  static const List<int> multipliers = <int>[0, 2, 4, 6];

  /// Content-seconds per real-second at each level (DVR-style ladder, each
  /// level 4x the previous).
  static const List<double> ratesPerLevel = <double>[0, 15, 60, 240];

  /// Source: ShuttleGrammar.swift:31-42 (`step`).
  static int step({required int current, required bool clickForward}) {
    final clickSign = clickForward ? 1 : -1;
    if (current == 0) return clickSign;
    if ((current > 0) == clickForward) {
      return math.min(current.abs() + 1, maxLevel) * clickSign;
    }
    // Opposite direction: step toward zero, then cross into the opposite
    // direction rather than stopping on it — landing exactly on zero would
    // mean cancel-to-invocation-position, throwing away everything the user
    // just shuttled past.
    final stepped = (current.abs() - 1) * (current > 0 ? 1 : -1);
    return stepped == 0 ? clickSign : stepped;
  }

  /// Source: ShuttleGrammar.swift:44-47 (`rate`).
  static double rate(int level) =>
      ratesPerLevel[math.min(level.abs(), maxLevel)];

  /// Source: ShuttleGrammar.swift:49-53 (`badge`).
  static String? badge(int level) {
    if (level == 0) return null;
    final glyph = level > 0 ? '▶' : '◀';
    return '$glyph ${multipliers[math.min(level.abs(), maxLevel)]}x';
  }
}

/// Drives a click-and-hold FF/RW shuttle: enters on the first nudge, steps
/// through [ShuttleGrammar], previews the target position on a 100 ms ticker
/// without touching the engine, then commits (Select) or cancels (Down/Back)
/// back to the invocation state.
///
/// Source: scrub/shuttle handling in
/// `research/Rivulet/Rivulet/Views/Player/UniversalPlayerViewModel.swift`
/// (`scrubRelative`, `commitScrub`, `cancelScrub`) — reimplemented here as a
/// signed-level state machine per [ShuttleGrammar] rather than ported
/// line-for-line, since that view model also owns unrelated player state.
class ShuttleController extends ChangeNotifier {
  ShuttleController({
    required this.controller,
    this.previewInterval = const Duration(milliseconds: 100),
  });

  final PlaybackController controller;
  final Duration previewInterval;

  int _level = 0;
  Duration? _invocationPosition;
  bool _wasPlayingAtInvocation = false;
  Duration _previewPosition = Duration.zero;
  Timer? _ticker;

  bool get isActive => _invocationPosition != null;
  int get level => _level;
  Duration get previewPosition => _previewPosition;
  String? get badge => ShuttleGrammar.badge(_level);

  void handleCommand(UiCommand command) {
    switch (command.type) {
      case UiCommandType.scrubNudgeForward:
        _nudge(forward: true);
      case UiCommandType.scrubNudgeBackward:
        _nudge(forward: false);
      case UiCommandType.selectDown:
        if (isActive) commit();
      case UiCommandType.directionDown:
      case UiCommandType.menuBack:
        if (isActive) cancel();
      default:
        break;
    }
  }

  void _nudge({required bool forward}) {
    if (!isActive) {
      final state = controller.currentState;
      _invocationPosition = state.position;
      _wasPlayingAtInvocation = state.isPlaying;
      _previewPosition = state.position;
      controller.pause();
      _startTicker();
    }
    _level = ShuttleGrammar.step(current: _level, clickForward: forward);
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(previewInterval, (_) => _tick());
  }

  void _tick() {
    if (!isActive || _level == 0) return;
    final signedRate = ShuttleGrammar.rate(_level) * _level.sign;
    final deltaMs = (signedRate * previewInterval.inMilliseconds).round();
    final duration = controller.currentState.duration;
    _previewPosition = _clamp(
      _previewPosition + Duration(milliseconds: deltaMs),
      duration,
    );
    notifyListeners();
  }

  /// Seeks to the previewed position, then restores play/pause as it was at
  /// invocation.
  Future<void> commit() async {
    if (!isActive) return;
    _ticker?.cancel();
    _ticker = null;
    final target = _previewPosition;
    final resumePlaying = _wasPlayingAtInvocation;
    _reset();
    await controller.seek(target);
    if (resumePlaying) await controller.play();
  }

  /// Discards the preview and restores play/pause as it was at invocation,
  /// without seeking.
  Future<void> cancel() async {
    if (!isActive) return;
    _ticker?.cancel();
    _ticker = null;
    final resumePlaying = _wasPlayingAtInvocation;
    _reset();
    if (resumePlaying) await controller.play();
  }

  void _reset() {
    _level = 0;
    _invocationPosition = null;
    _wasPlayingAtInvocation = false;
    notifyListeners();
  }

  static Duration _clamp(Duration value, Duration duration) {
    if (value < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
