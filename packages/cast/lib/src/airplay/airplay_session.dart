import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/cast_device.dart';
import '../core/cast_media.dart';
import '../core/cast_session.dart';
import '../utils/logger.dart';

/// An AirPlay session, played by the one native AVPlayer (Apple platforms
/// only; mpv stays the local engine). Unlike Chromecast and DLNA there is no
/// device list: [loadMedia] prepares the player paused, the user picks the
/// AirPlay device in the system route picker, and [externalPlaybackStream]
/// reports when a device took over (true) or was lost (false).
class AirPlaySession extends CastSession {
  /// macOS only for now; iOS is a later pass.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Platform view type of the system route picker (AVRoutePickerView).
  static const String routePickerViewType = 'cast/airplay-route-picker';

  AirPlaySession({MethodChannel? channel, Stream<dynamic>? events})
    : _channel = channel ?? const MethodChannel('cast/airplay'),
      _events =
          events ??
          const EventChannel('cast/airplay/events').receiveBroadcastStream(),
      super(
        CastDevice(
          id: 'airplay',
          name: 'AirPlay',
          protocol: CastProtocol.airplay,
          address: InternetAddress.loopbackIPv4,
          port: 0,
        ),
      );

  final MethodChannel _channel;
  final Stream<dynamic> _events;
  StreamSubscription<dynamic>? _sub;
  final StreamController<bool> _external = StreamController<bool>.broadcast();
  bool _externalActive = false;

  /// True while an AirPlay device is playing.
  bool get externalActive => _externalActive;

  /// Emits only when the AirPlay route is gained or lost.
  Stream<bool> get externalPlaybackStream => _external.stream;

  @override
  Future<void> connect() async {
    await super.connect();
    _sub = _events.listen(
      _onSnapshot,
      onError: (Object e) => CastLogger.error('AirPlay events failed: $e'),
    );
  }

  void _onSnapshot(dynamic raw) {
    final s = (raw as Map).cast<String, Object?>();
    updatePosition(Duration(milliseconds: s['positionMs'] as int? ?? 0));
    updateDuration(Duration(milliseconds: s['durationMs'] as int? ?? 0));
    if (s['error'] case final String e) CastLogger.error('AirPlay: $e');
    // The state comes from AVPlayer, not from commands, so it is mirrored
    // rather than walked through the command state machine.
    stateMachine.forceState(switch (s['state']) {
      'playing' => SessionState.playing,
      'paused' => SessionState.paused,
      'buffering' => SessionState.buffering,
      'loading' => SessionState.loading,
      _ => SessionState.idle,
    });
    final ext = s['external'] as bool? ?? false;
    if (ext != _externalActive) {
      _externalActive = ext;
      _external.add(ext);
    }
  }

  @override
  Future<void> loadMedia(CastMedia media) async {
    stateMachine.transitionTo(SessionState.loading);
    await _channel.invokeMethod<void>('prepare', {
      'url': media.url,
      'startMs': media.startPosition?.inMilliseconds ?? 0,
    });
  }

  @override
  Future<void> play() => _channel.invokeMethod<void>('play');

  @override
  Future<void> pause() => _channel.invokeMethod<void>('pause');

  @override
  Future<void> seek(Duration position) => _channel.invokeMethod<void>('seek', {
    'positionMs': position.inMilliseconds,
  });

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// AirPlay volume is the device's own; the app does not set it.
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSubtitle(CastSubtitle? subtitle) async {}

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await stop();
    stateMachine.transitionTo(SessionState.disconnected);
  }

  @override
  void dispose() {
    _external.close();
    super.dispose();
  }
}
