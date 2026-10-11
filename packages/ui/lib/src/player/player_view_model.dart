import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';

class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({required this.controller}) {
    _state = controller.currentState;
    _subscription = controller.state.listen((state) {
      _state = state;
      notifyListeners();
    });
  }

  final PlaybackController controller;
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
    _subscription.cancel();
    super.dispose();
  }
}
