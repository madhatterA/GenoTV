import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:playback/playback.dart' show HdrPolicy;

/// Keeps one paused engine (and its audio output) between player routes.
/// Kodi macOS 1.13: awake for one idle minute; zero while the app is unfocused.
final class AudioDeviceKeepAlive with WidgetsBindingObserver {
  static const idleLimit = Duration(minutes: 1);

  AudioDeviceKeepAlive({
    required this.settings,
    required this.create,
    required this.hdrPolicy,
    required this.logger,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _changes = settings.changes.listen((_) {
      if (!enabled || _retainedPolicy != hdrPolicy()) {
        unawaited(
          _discard().catchError((Object error, StackTrace stack) {
            logger.error(
              'releasing retained audio device failed',
              error: error,
              stack: stack,
            );
          }),
        );
      }
    });
  }

  final SettingsValues settings;
  final PlaybackController Function(HdrPolicy) create;
  final HdrPolicy Function() hdrPolicy;
  final AppLogger logger;
  final _policies = <PlaybackController, HdrPolicy>{};
  late final StreamSubscription<SettingDef> _changes;
  PlaybackController? _retained;
  HdrPolicy? _retainedPolicy;
  Future<void> _releasing = Future<void>.value();
  bool _disposed = false;

  Timer? _idle;

  bool get _focused {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _expire();
  }

  void _expire() => unawaited(
    _discard().catchError((Object error, StackTrace stack) {
      logger.error(
        'releasing retained audio device failed',
        error: error,
        stack: stack,
      );
    }),
  );

  bool get enabled =>
      settings.read(settingById('audio.deviceKeepAlive')) == true;

  PlaybackController acquire() {
    if (_disposed) throw StateError('audio device retention is disposed');
    final policy = hdrPolicy();
    if (enabled && _retained != null && _retainedPolicy == policy) {
      final controller = _retained!;
      _idle?.cancel();
      _retained = null;
      _retainedPolicy = null;
      return controller;
    }
    final controller = create(policy);
    _policies[controller] = policy;
    return controller;
  }

  Future<void> release(PlaybackController controller) async {
    if (!_disposed &&
        enabled &&
        _focused &&
        _policies[controller] == hdrPolicy()) {
      await controller.pause();
      await _discard();
      // A setting can change while pause/disposal is awaiting the engine.
      if (!_disposed &&
          enabled &&
          _focused &&
          _policies[controller] == hdrPolicy()) {
        _idle = Timer(idleLimit, _expire);
        _retained = controller;
        _retainedPolicy = _policies[controller];
        return;
      }
    }
    _policies.remove(controller);
    await controller.dispose();
  }

  Future<void> _discard() {
    _idle?.cancel();
    final controller = _retained;
    _retained = null;
    _retainedPolicy = null;
    if (controller != null) {
      _policies.remove(controller);
      _releasing = _releasing.then((_) => controller.dispose());
    }
    return _releasing;
  }

  Future<void> dispose() async {
    _disposed = true;
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _changes.cancel();
    await _discard();
  }
}
