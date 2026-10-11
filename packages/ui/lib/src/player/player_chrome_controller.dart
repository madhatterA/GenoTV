import 'dart:async';

import 'package:flutter/foundation.dart';

/// The player chrome's explicit modes (phase file step 3).
///
/// [hidden] and [rail] are the two "plain player" states — Back from either
/// starts the exit fade. Every other mode is transient: Back closes it and
/// returns to [rail].
enum ChromeMode {
  hidden,
  rail,
  scrubbing,
  shuttle,
  panel,
  error,
  postVideo,
  exiting,
}

/// The three tiers of the paused presentation, ported from
/// `UniversalPlayerViewModel.PausePresentation`
/// (`research/Rivulet/Rivulet/Views/Player/UniversalPlayerViewModel.swift:122-127`):
/// [frame] is the live paused frame (no overlay), [ambient] adds the dim
/// after `pausedPosterDelay`, [dimmed] deepens it after `pausedPosterDimDelay`.
enum PausePresentation { frame, ambient, dimmed }

/// Drives [ChromeMode] and [PausePresentation] for `PlayerScreen`.
///
/// Never keyed by playback position and never recreated across a rebuild —
/// `PlayerScreen` owns exactly one instance per session (Decisions table:
/// "Surface lifetime — Create once per opened media session",
/// `PlayerContainerViewController.swift`, one container per player push).
class PlayerChromeController extends ChangeNotifier {
  // The public parameter name (`onExit`) can't match the private field
  // directly (`this._onExit` would make callers pass `_onExit:`, which
  // isn't a valid external name), so this can't use an initializing formal.
  // ignore: prefer_initializing_formals
  PlayerChromeController({VoidCallback? onExit}) : _onExit = onExit;

  /// Chrome auto-hide while playing.
  /// `UniversalPlayerViewModel.swift:392`: `controlsHideDelay: TimeInterval = 5`.
  static const Duration hideDelay = Duration(seconds: 5);

  /// Paused ambient tier.
  /// `UniversalPlayerViewModel.swift:411`: `pausedPosterDelay: TimeInterval = 10.0`.
  static const Duration pausedAmbientDelay = Duration(seconds: 10);

  /// Paused deep-dim tier (OLED burn-in guard).
  /// `UniversalPlayerViewModel.swift:413`: `pausedPosterDimDelay: TimeInterval = 120.0`.
  static const Duration pausedDimDelay = Duration(seconds: 120);

  /// Exit fade before the exit callback fires.
  /// `PlayerContainerViewController.swift:511`: `exitFadeDuration: TimeInterval = 0.4`.
  static const Duration exitFadeDuration = Duration(milliseconds: 400);

  /// Re-dismiss guard after a mode change (phase file step 5: "Block
  /// re-dismiss for 300 ms after mode change"). Not a Rivulet-sourced
  /// value — no matching constant was found in the cited player sources;
  /// this is a Part 04 debounce against an errant double-press.
  static const Duration dismissBlockDuration = Duration(milliseconds: 300);

  final VoidCallback? _onExit;

  ChromeMode _mode = ChromeMode.rail;
  bool _isPlaying = false;
  PausePresentation _pausePresentation = PausePresentation.frame;
  bool _exitCalled = false;

  /// False for [dismissBlockDuration] after entering [ChromeMode.error].
  /// Timer-driven (not a `DateTime.now()` diff) so it advances on the same
  /// fake clock as every other timer here under `tester.pump(duration)`
  /// (TRAPS: "Timers in tests: fake time via testWidgets + tester.pump,
  /// never real clocks" — a wall-clock diff would never move under a
  /// fake-async test pump).
  bool _dismissBlocked = false;

  Timer? _hideTimer;
  Timer? _ambientTimer;
  Timer? _dimTimer;
  Timer? _exitTimer;
  Timer? _dismissGuardTimer;

  ChromeMode get mode => _mode;
  bool get visible => _mode != ChromeMode.hidden;
  bool get isPlaying => _isPlaying;
  PausePresentation get pausePresentation => _pausePresentation;

  bool get _isTransient => switch (_mode) {
    ChromeMode.scrubbing ||
    ChromeMode.shuttle ||
    ChromeMode.panel ||
    ChromeMode.error ||
    ChromeMode.postVideo => true,
    ChromeMode.hidden || ChromeMode.rail || ChromeMode.exiting => false,
  };

  /// Any handled input reveals/resets chrome (step 4), except while
  /// post-video owns the screen — it consumes its own input and is closed
  /// explicitly (`PlayerContainerViewController.swift:412-416`: "Post-video
  /// owns the screen while it is up, so it owns focus").
  void reveal() {
    if (_mode == ChromeMode.exiting || _mode == ChromeMode.postVideo) return;
    if (_mode == ChromeMode.hidden) _setMode(ChromeMode.rail);
    _pausePresentation = PausePresentation.frame;
    _restartHideTimer();
    _restartAmbientTimers();
    notifyListeners();
  }

  void toggle() {
    if (_mode == ChromeMode.hidden) {
      reveal();
    } else if (_mode == ChromeMode.rail) {
      _hideTimer?.cancel();
      _cancelAmbientTimers();
      _setMode(ChromeMode.hidden);
    }
  }

  /// Feed from the controller's `isPlaying`. Hide-after-5s only runs while
  /// playing; the paused ambient/dim tiers only run while paused (step 4).
  void setPlaying(bool playing) {
    if (_isPlaying == playing) return;
    _isPlaying = playing;
    if (playing) {
      _cancelAmbientTimers();
      _pausePresentation = PausePresentation.frame;
      _restartHideTimer();
    } else {
      _hideTimer?.cancel();
      if (_mode == ChromeMode.hidden) _setMode(ChromeMode.rail);
      _restartAmbientTimers();
    }
    notifyListeners();
  }

  void enterScrubbing() => _enterTransient(ChromeMode.scrubbing);
  void enterShuttle() => _enterTransient(ChromeMode.shuttle);
  void openPanel() => _enterTransient(ChromeMode.panel);
  void enterPostVideo() => _enterTransient(ChromeMode.postVideo);

  void exitScrubbing() {
    if (_mode == ChromeMode.scrubbing) _returnToRail();
  }

  void exitShuttle() {
    if (_mode == ChromeMode.shuttle) _returnToRail();
  }

  void closePanel() {
    if (_mode == ChromeMode.panel) _returnToRail();
  }

  void exitPostVideo() {
    if (_mode == ChromeMode.postVideo) _returnToRail();
  }

  void showError() {
    _hideTimer?.cancel();
    _cancelAmbientTimers();
    _setMode(ChromeMode.error);
    _dismissBlocked = true;
    _dismissGuardTimer?.cancel();
    _dismissGuardTimer = Timer(dismissBlockDuration, () {
      _dismissBlocked = false;
      notifyListeners();
    });
  }

  /// False for [dismissBlockDuration] after entering [ChromeMode.error]
  /// (pitfall: "Block re-dismiss for 300 ms after mode change").
  bool get canDismissError => _mode == ChromeMode.error && !_dismissBlocked;

  void dismissError() {
    if (!canDismissError) return;
    _returnToRail();
  }

  /// Retrying re-enters loading/rail presentation; the retry action itself
  /// (re-opening the source) is Part 02/07's — this only clears chrome mode.
  void retryFromError() {
    if (_mode != ChromeMode.error) return;
    _returnToRail();
  }

  /// Back closes the current transient mode; from the plain player (rail or
  /// hidden) it starts the exit fade (step 6). Returns true when the press
  /// was consumed (always, except a blocked error dismiss, which still
  /// consumes the press without acting).
  bool handleBack() {
    if (_mode == ChromeMode.exiting) return true;
    if (_isTransient) {
      if (_mode == ChromeMode.error) {
        dismissError();
      } else {
        _returnToRail();
      }
      return true;
    }
    requestExit();
    return true;
  }

  /// 400 ms fade, then the exit callback fires exactly once
  /// (`PlayerContainerViewController.swift:511-573`).
  void requestExit() {
    if (_mode == ChromeMode.exiting) return;
    _hideTimer?.cancel();
    _cancelAmbientTimers();
    _setMode(ChromeMode.exiting);
    _exitTimer = Timer(exitFadeDuration, _fireExit);
  }

  void _fireExit() {
    if (_exitCalled) return;
    _exitCalled = true;
    _onExit?.call();
  }

  void _enterTransient(ChromeMode mode) {
    if (_mode == ChromeMode.exiting || _mode == mode) return;
    _hideTimer?.cancel();
    _cancelAmbientTimers();
    _setMode(mode);
  }

  void _returnToRail() {
    _setMode(ChromeMode.rail);
    _pausePresentation = PausePresentation.frame;
    _restartHideTimer();
    _restartAmbientTimers();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_mode != ChromeMode.rail || !_isPlaying) return;
    _hideTimer = Timer(hideDelay, () {
      if (_mode != ChromeMode.rail || !_isPlaying) return;
      _setMode(ChromeMode.hidden);
      notifyListeners();
    });
  }

  void _restartAmbientTimers() {
    _cancelAmbientTimers();
    if (_mode != ChromeMode.rail || _isPlaying) return;
    _ambientTimer = Timer(pausedAmbientDelay, () {
      if (_isPlaying) return;
      _pausePresentation = PausePresentation.ambient;
      notifyListeners();
    });
    _dimTimer = Timer(pausedDimDelay, () {
      if (_isPlaying) return;
      _pausePresentation = PausePresentation.dimmed;
      notifyListeners();
    });
  }

  void _cancelAmbientTimers() {
    _ambientTimer?.cancel();
    _dimTimer?.cancel();
  }

  void _setMode(ChromeMode mode) {
    _mode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ambientTimer?.cancel();
    _dimTimer?.cancel();
    _exitTimer?.cancel();
    _dismissGuardTimer?.cancel();
    super.dispose();
  }
}
