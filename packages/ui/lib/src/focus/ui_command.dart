/// The normalized command vocabulary every physical input source funnels
/// into. Raw D-pad/keyboard/gamepad/pointer/touch events are translated to
/// one of these by [InputRouter] (or, for pointer/touch, constructed
/// directly by the widget the user activated) so that dedupe, hold
/// detection, and action handlers never branch on the originating device.
///
/// Source: `research/Rivulet/Rivulet/Services/Input/` — Rivulet's
/// `PlaybackInputAction` plays the same normalizing role for its remote,
/// GameController, and keyboard sources.
library;

/// The physical/logical origin of a [UiCommand]. Carried for diagnostics and
/// for dedupe rules that are cross-source by design (see
/// [UiCommandType.scrubNudgeForward]/[UiCommandType.scrubNudgeBackward]).
enum CommandSource { keyboard, remote, gamepad, pointer, touch }

/// Semantic command emitted by [InputRouter] or a pointer/touch handler.
enum UiCommandType {
  directionUp,
  directionDown,
  directionLeft,
  directionRight,
  selectDown,
  selectUp,
  playPause,
  menuBack,
  info,
  stepSeekForward,
  stepSeekBackward,
  jumpSeekForward,
  jumpSeekBackward,
  scrubNudgeForward,
  scrubNudgeBackward,
  scrubCommit,
  scrubCancel,
}

/// Directional movement commands are never deduped or coalesced — see
/// [InputRouter]. Everything else is either a "transport" command (dedupe
/// window `InputConfig.transportDedupeWindow`, 350 ms — playback control
/// should not double-fire when two sources report the same physical press),
/// a "scrub nudge" (cross-source dedupe window
/// `InputConfig.scrubNudgeDedupeWindow`, 250 ms — see the doc comment on
/// that constant), or a plain "action" (dedupe window
/// `InputConfig.actionDedupeWindow`, 80 ms).
///
/// Source: `research/Rivulet/Rivulet/Config/InputConfig.swift:16-28`.
enum DedupeClass { none, action, transport, scrubNudge }

DedupeClass dedupeClassOf(UiCommandType type) {
  switch (type) {
    case UiCommandType.directionUp:
    case UiCommandType.directionDown:
    case UiCommandType.directionLeft:
    case UiCommandType.directionRight:
      return DedupeClass.none;
    case UiCommandType.playPause:
      return DedupeClass.transport;
    case UiCommandType.scrubNudgeForward:
    case UiCommandType.scrubNudgeBackward:
      return DedupeClass.scrubNudge;
    case UiCommandType.selectDown:
    case UiCommandType.selectUp:
    case UiCommandType.menuBack:
    case UiCommandType.info:
    case UiCommandType.stepSeekForward:
    case UiCommandType.stepSeekBackward:
    case UiCommandType.jumpSeekForward:
    case UiCommandType.jumpSeekBackward:
    case UiCommandType.scrubCommit:
    case UiCommandType.scrubCancel:
      return DedupeClass.action;
  }
}

/// A normalized command. [timestamp] is monotonic and caller-supplied (real
/// wall time in production, fake/advanced time in tests) — dedupe windows
/// are measured against it, never against `DateTime.now()`, so tests never
/// need to sleep.
final class UiCommand {
  const UiCommand(
    this.type, {
    required this.source,
    required this.timestamp,
    this.repeatCount = 1,
  });

  final UiCommandType type;
  final CommandSource source;
  final Duration timestamp;

  /// For a coalesced burst of identical step-seek presses (see
  /// [InputRouter]'s 50 ms coalescer), the number of presses folded into
  /// this one emission. 1 for every other command.
  final int repeatCount;

  @override
  String toString() =>
      'UiCommand($type, source: $source, t: $timestamp, x$repeatCount)';

  @override
  bool operator ==(Object other) =>
      other is UiCommand &&
      other.type == type &&
      other.source == source &&
      other.timestamp == timestamp &&
      other.repeatCount == repeatCount;

  @override
  int get hashCode => Object.hash(type, source, timestamp, repeatCount);
}
