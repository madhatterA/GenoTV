import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';

/// Immutable "What did they say?" replay-window state, ported 1:1 from
/// `research/Rivulet/Rivulet/Services/Input/ReplayWindowLogic.swift`. Pure
/// value type, tested directly and driven by [SubtitleReplayController].
@immutable
class ReplayWindow {
  const ReplayWindow({
    required this.invokedAt,
    required this.priorSelection,
    this.armed = false,
  });

  /// Playback position the window reverts at — the point replay was
  /// invoked, or last extended to on a repeat invocation.
  /// `ReplayWindowLogic.swift:17-19`.
  final Duration invokedAt;

  /// Subtitle selection active before replay temporarily changed it.
  /// Restored (or left alone, if it wasn't off) when the window reverts.
  /// `ReplayWindowLogic.swift:21-24`.
  final TrackChoice priorSelection;

  /// True once a tick has been observed *before* [invokedAt] — proof the
  /// backward seek that opens the window has actually landed. Without
  /// this, a stale tick arriving before the async seek lands could revert
  /// the window immediately. `ReplayWindowLogic.swift:26-36`.
  final bool armed;

  /// `ReplayWindowLogic.swift:44-48`.
  bool shouldRevert(Duration currentPosition) =>
      armed && currentPosition > invokedAt;

  /// `ReplayWindowLogic.swift:50-56`.
  ReplayWindow observing(Duration currentPosition) {
    if (armed || currentPosition >= invokedAt) return this;
    return ReplayWindow(
      invokedAt: invokedAt,
      priorSelection: priorSelection,
      armed: true,
    );
  }

  /// `ReplayWindowLogic.swift:58-65`.
  ReplayWindow extended(Duration newInvokedAt) => ReplayWindow(
    invokedAt: newInvokedAt > invokedAt ? newInvokedAt : invokedAt,
    priorSelection: priorSelection,
    armed: armed,
  );
}

/// Drives Rivulet's subtitle-rail long-press "what did they say?" replay:
/// seek back 15s and temporarily enable a preferred non-forced subtitle,
/// restoring the prior selection once playback passes the point replay was
/// invoked from.
///
/// Source: `UniversalPlayerViewModel.replayWithCaptions()`
/// (`research/Rivulet/Rivulet/Views/Player/UniversalPlayerViewModel.swift:2946-2958`)
/// and `tickReplayWindow(at:)` (`:2971-2985`).
class SubtitleReplayController {
  SubtitleReplayController({required this.controller, this.onFailure}) {
    _subscription = controller.state.listen(_onState);
    _events = controller.events.listen((event) {
      if (event is MediaOpened || event is PlaybackFailed) cancel();
    });
  }

  /// `UniversalPlayerViewModel.swift:2958` — `seek(to: max(0, invokedAt - 15))`.
  static const Duration replayBack = Duration(seconds: 15);

  final PlaybackController controller;
  final void Function(Object error, StackTrace stack)? onFailure;
  Future<void>? _selectionOperation;
  TrackChoice? _selectionFrom;
  TrackChoice? _selectionTarget;
  TrackChoice? _restoreFrom;
  TrackChoice? _restoreTo;
  TrackChoice? _restoreOverride;
  late final StreamSubscription<PlaybackState> _subscription;
  late final StreamSubscription<PlaybackEvent> _events;
  int _generation = 0;

  ReplayWindow? _window;

  /// The subtitle selection the open window expects to see: the one this
  /// controller itself selected, or the untouched prior selection. Any
  /// other observed selection is a manual override.
  TrackChoice? _expectedSelection;
  bool _disposed = false;

  /// Whether a replay window is currently open (exposed for tests).
  ReplayWindow? get activeWindow => _window;

  /// Invoked from the subtitles rail button's long-press
  /// (`PlayerRailView.swift:162`: `onReplayLongPress`).
  Future<void> invoke() async {
    if (_disposed) return;
    final invokedAt = controller.currentState.position;
    var generation = _generation;
    try {
      final pending = _selectionOperation;
      if (pending != null) await pending;
      if (_disposed || generation != _generation) return;
      final state = controller.currentState;
      if (state.duration <= Duration.zero) return;
      final priorSelection = _window?.priorSelection ?? state.selected.subtitle;
      final revertAt = _window?.extended(invokedAt).invokedAt ?? invokedAt;
      _window = ReplayWindow(
        invokedAt: revertAt,
        priorSelection: priorSelection,
      );
      _expectedSelection = state.selected.subtitle;
      generation = ++_generation;
      final target = invokedAt - replayBack;
      await controller.seek(target < Duration.zero ? Duration.zero : target);
      if (_disposed || generation != _generation || _window == null) return;
      final current = controller.currentState;
      if (_window!.invokedAt == Duration.zero &&
          current.position == Duration.zero) {
        _window = ReplayWindow(
          invokedAt: Duration.zero,
          priorSelection: priorSelection,
          armed: true,
        );
      }
      final selectedTrack = current.tracks.subtitle
          .where((track) => track.id == current.selected.subtitle.id)
          .firstOrNull;
      if (current.selected.subtitle.mode == TrackSelectionMode.off ||
          selectedTrack == null ||
          isForcedSubtitleTrack(selectedTrack)) {
        final track = preferredNonForcedSubtitle(current.tracks.subtitle);
        if (track != null) {
          await _selectSubtitle(current, TrackChoice.specific(track.id));
        }
      }
    } catch (error, stack) {
      _reportFailure(error, stack, generation);
    }
  }

  /// Cancels any active window without reverting subtitles — mirrors
  /// `clearReplayWindow()` (`UniversalPlayerViewModel.swift:2994`), used on
  /// disposal/session change so an outgoing session's window never reverts
  /// into a new one.
  void cancel() {
    _generation++;
    _window = null;
    _expectedSelection = null;
    _selectionFrom = null;
    _selectionTarget = null;
    _restoreFrom = null;
    _restoreTo = null;
    _restoreOverride = null;
  }

  void _onState(PlaybackState state) {
    final window = _window;
    if (window == null) {
      if (_restoreFrom != null &&
          state.selected.subtitle != _restoreFrom &&
          state.selected.subtitle != _restoreTo) {
        _restoreOverride = state.selected.subtitle;
      }
      return;
    }

    // A subtitle selection this window did not itself make is a manual
    // override: it becomes authoritative and must not be reverted later.
    if (_selectionTarget != null && state.selected.subtitle == _selectionFrom) {
      _window = window.observing(state.position);
      return;
    }
    if (state.selected.subtitle == _selectionTarget) {
      _selectionFrom = null;
      _selectionTarget = null;
    }
    if (state.selected.subtitle != _expectedSelection) {
      if (_restoreFrom != null) {
        _restoreOverride = state.selected.subtitle;
        _window = null;
        _expectedSelection = null;
        _selectionFrom = null;
        _selectionTarget = null;
      } else {
        cancel();
      }
      return;
    }

    final observed = window.observing(state.position);
    _window = observed;
    if (!observed.shouldRevert(state.position)) return;

    cancel();
    if (state.selected.subtitle != observed.priorSelection) {
      final operation = _restoreSubtitle(state, observed.priorSelection);
      _selectionOperation = operation;
      unawaited(operation);
    }
  }

  Future<void> _restoreSubtitle(
    PlaybackState state,
    TrackChoice subtitle,
  ) async {
    final generation = _generation;
    _restoreFrom = state.selected.subtitle;
    _restoreTo = subtitle;
    try {
      await controller.selectTrack(
        TrackSelection(
          video: state.selected.video,
          audio: state.selected.audio,
          subtitle: subtitle,
        ),
      );
      while (!_disposed &&
          generation == _generation &&
          _restoreOverride != null) {
        final authoritative = _restoreOverride!;
        final current = controller.currentState;
        _restoreFrom = current.selected.subtitle;
        _restoreTo = authoritative;
        _restoreOverride = null;
        await controller.selectTrack(
          TrackSelection(
            video: current.selected.video,
            audio: current.selected.audio,
            subtitle: authoritative,
          ),
        );
      }
    } catch (error, stack) {
      _reportFailure(error, stack, generation);
    } finally {
      if (generation == _generation) {
        _restoreFrom = null;
        _restoreTo = null;
        _restoreOverride = null;
        _selectionOperation = null;
      }
    }
  }

  Future<void> _selectSubtitle(PlaybackState state, TrackChoice subtitle) {
    if (_window != null) {
      _selectionFrom = state.selected.subtitle;
      _selectionTarget = subtitle;
      _expectedSelection = subtitle;
    }
    final operation = _restoreSubtitle(state, subtitle);
    _selectionOperation = operation;
    return operation;
  }

  /// First non-forced subtitle track, or the first track if all are
  /// forced. `Track` (contracts) carries no dedicated forced flag, so
  /// "forced" is read off the title the same way `track_panel.dart`'s
  /// `isCommentaryOrDescriptiveTrack` reads "commentary"/"description".
  /// Source: `UniversalPlayerViewModel.preferredReplaySubtitleTrack()`
  /// (`UniversalPlayerViewModel.swift:2964-2966`).
  void _reportFailure(Object error, StackTrace stack, int generation) {
    if (_disposed) return;
    if (generation != _generation) {
      if (onFailure == null) Error.throwWithStackTrace(error, stack);
      return;
    }
    cancel();
    if (onFailure case final callback?) {
      callback(error, stack);
    } else {
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Track? preferredNonForcedSubtitle(List<Track> tracks) {
    Track? firstForced;
    for (final track in tracks) {
      if (isForcedSubtitleTrack(track)) {
        firstForced ??= track;
        continue;
      }
      return track;
    }
    return firstForced;
  }

  static bool isForcedSubtitleTrack(Track track) =>
      (track.title ?? '').toLowerCase().contains('forced');

  void dispose() {
    _disposed = true;
    cancel();
    unawaited(_subscription.cancel());
    unawaited(_events.cancel());
  }
}
