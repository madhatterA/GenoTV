import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';

class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({required this.controller}) {
    _state = controller.currentState;
    _subscription = controller.state.listen(_onState);
  }

  /// While the chrome is hidden only the position moves on screen, so
  /// position-only ticks reach the UI at 1 Hz (THRESHOLDS); the latest one is
  /// held and delivered, never dropped. Any other change is immediate.
  bool get chromeVisible => _chromeVisible;
  set chromeVisible(bool value) {
    if (_chromeVisible == value) return;
    _chromeVisible = value;
    if (value) _flush();
  }

  bool _chromeVisible = true;
  static const _hiddenInterval = Duration(seconds: 1);
  PlaybackState? _pending;
  Timer? _cooldown;

  void _onState(PlaybackState state) {
    final held = _state;
    final positionOnly =
        state.duration == held.duration &&
        state.isPlaying == held.isPlaying &&
        state.isBuffering == held.isBuffering &&
        state.isCompleted == held.isCompleted &&
        state.rate == held.rate &&
        identical(state.tracks, held.tracks) &&
        identical(state.selected, held.selected) &&
        identical(state.chapters, held.chapters) &&
        identical(state.failure, held.failure);
    if (!_chromeVisible && positionOnly && _cooldown != null) {
      _pending = state;
      return;
    }
    _emit(state);
    if (!_chromeVisible) {
      _cooldown?.cancel();
      _cooldown = Timer(_hiddenInterval, _onCooldown);
    }
  }

  void _onCooldown() {
    _cooldown = null;
    final pending = _pending;
    if (pending == null) return;
    _emit(pending);
    _cooldown = Timer(_hiddenInterval, _onCooldown);
  }

  void _flush() {
    final pending = _pending;
    if (pending != null) _emit(pending);
  }

  void _emit(PlaybackState state) {
    _pending = null;
    _state = state;
    live.value = state;
    notifyListeners();
  }

  final PlaybackController controller;

  /// Every state event, for the few widgets that show the position.
  late final ValueNotifier<PlaybackState> live = ValueNotifier(_state);
  late PlaybackState _state;
  late final StreamSubscription<PlaybackState> _subscription;

  PlaybackState get state => _state;
  Duration get position => _state.position;
  Duration get duration => _state.duration;
  bool get isPlaying => _state.isPlaying;
  bool get isBuffering => _state.isBuffering;
  PlaybackFailure? get failure => _state.failure;

  @override
  void dispose() {
    _cooldown?.cancel();
    _subscription.cancel();
    live.dispose();
    super.dispose();
  }
}

/// Hands the live [PlaybackState] to the widgets that show the position, so
/// a tick rebuilds only them and not the whole player chrome.
class LivePlaybackState
    extends InheritedNotifier<ValueNotifier<PlaybackState>> {
  const LivePlaybackState({
    required ValueNotifier<PlaybackState> live,
    required super.child,
    super.key,
  }) : super(notifier: live);

  /// The live state when a scope is above [context], else [fallback].
  static PlaybackState of(BuildContext context, PlaybackState fallback) =>
      context
          .dependOnInheritedWidgetOfExactType<LivePlaybackState>()
          ?.notifier!
          .value ??
      fallback;
}
