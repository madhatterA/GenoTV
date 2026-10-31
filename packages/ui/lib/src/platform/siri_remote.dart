import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One touch-surface event of the Siri Remote, x and y in [-1, 1].
@immutable
class SiriTouch {
  const SiriTouch(this.phase, this.x, this.y);

  /// `started`, `move`, `ended`, `cancelled`, `loc`, `click_s` or `click_e`.
  final String phase;
  final double x;
  final double y;
}

/// The Siri Remote touch surface (tvOS engine plugin, channels `flutter/tv_remote`
/// and `flutter/tv_remote_touches`; research: flutter-tvos
/// `packages/flutter_tvos/lib/src/rcu`). The engine turns swipes into arrow keys;
/// [start] switches that off so only click-pad presses move focus, and the raw
/// touches stay available on [touches] for the player to scrub with.
class SiriRemote {
  SiriRemote({
    MethodChannel? button,
    BasicMessageChannel<dynamic>? touchChannel,
    this.retryDelay = const Duration(milliseconds: 100),
  }) : _button =
           button ??
           const MethodChannel('flutter/tv_remote', JSONMethodCodec()),
       _touchChannel =
           touchChannel ??
           const BasicMessageChannel<dynamic>(
             'flutter/tv_remote_touches',
             JSONMessageCodec(),
           );

  final MethodChannel _button;
  final BasicMessageChannel<dynamic> _touchChannel;
  final Duration retryDelay;
  final StreamController<SiriTouch> _touches =
      StreamController<SiriTouch>.broadcast();

  /// The engine's own "continuous swipe" auto-repeat starts after this many
  /// same-direction moves; no touch surface produces this many.
  static const int swipeNeverMoves = 1 << 30;

  Stream<SiriTouch> get touches => _touches.stream;

  /// Ships the tuning to the engine (swipes off, other values the engine's
  /// defaults). The engine registers its handler a moment after launch, so a
  /// missing plugin is retried; it also holds touches back until this lands.
  Future<void> start({int attempts = 50}) async {
    _touchChannel.setMessageHandler(_onTouch);
    for (var attempt = 0; ; attempt++) {
      try {
        await _button.invokeMethod<void>('configure', <String, dynamic>{
          'shortSwipeThreshold': 0.3,
          'fastSwipeThreshold': 0.5,
          'dpadDeadZone': 0.5,
          'continuousSwipeMoveThreshold': swipeNeverMoves,
          'keyRepeatInitialDelayMs': 400,
          'keyRepeatIntervalMs': 80,
        });
        return;
      } on MissingPluginException {
        if (attempt + 1 >= attempts) rethrow;
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<dynamic> _onTouch(dynamic message) async {
    if (message is Map && message['type'] is String) {
      _touches.add(
        SiriTouch(
          message['type'] as String,
          (message['x'] as num?)?.toDouble() ?? 0,
          (message['y'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return null;
  }

  void dispose() {
    _touchChannel.setMessageHandler(null);
    unawaited(_touches.close());
  }
}
