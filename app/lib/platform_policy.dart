import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:platform_services/platform_services.dart';

/// How a session picks a display mode, from the Display settings.
final class DisplayMatchOptions {
  const DisplayMatchOptions({
    this.matchResolution = true,
    this.whitelist = DisplayModeWhitelist.all,
    this.forcedRefreshHz,
    this.rematchOnChange = false,
  });

  /// Switch to the content's resolution too; false changes refresh rate only.
  final bool matchResolution;

  /// Only these modes may be chosen.
  final DisplayModeWhitelist whitelist;

  /// Refresh rate to target instead of the content's frame rate.
  final double? forcedRefreshHz;

  /// Match again, releasing the previous lease, when the content frame rate
  /// changes during the session ("Always").
  final bool rematchOnChange;
}

/// The platform resources leased for one playback session.
///
/// This is deliberately an app-owned coordinator. Platform services report
/// capabilities and own native calls; this class only decides when to lease
/// them and guarantees reverse-order cleanup.
typedef KeepAwakeAcquire = Future<Future<void> Function()> Function();
typedef MediaSessionClear = Future<void> Function();

final class PlatformPolicy {
  PlatformPolicy({
    required this.capabilities,
    required this.displayModes,
    required this.audio,
    required this.events,
    required this.mediaCommands,
    required this.acquireKeepAwake,
    required this.clearMediaSession,
    required this.diagnostics,
    this.displayModeMatchingEnabled = false,
    this.displayOptions = const DisplayMatchOptions(),
    this.passthroughEnabled = false,
  });

  final PlatformCapabilities capabilities;
  final DisplayModeService displayModes;
  final AudioOutputService audio;
  final Stream<PlatformEvent> events;
  final Stream<MediaSessionCommand> mediaCommands;
  final KeepAwakeAcquire acquireKeepAwake;
  final MediaSessionClear clearMediaSession;
  final DiagnosticsCollector diagnostics;
  final bool displayModeMatchingEnabled;
  final DisplayMatchOptions displayOptions;
  final bool passthroughEnabled;

  final Map<String, String> _displayDiagnostics = {};
  final Map<String, String> _audioDiagnostics = {};
  final Map<String, String> _policyDiagnostics = {};
  CapabilityReport? _capabilityReport;
  DisplayModeLease? _displayLease;
  double? _matchedFps;
  Future<void> Function()? _releaseKeepAwake;
  // These long-lived subscriptions are cancelled by [stop] on every path.
  // ignore: cancel_subscriptions
  StreamSubscription<PlatformEvent>? _eventSubscription;
  // ignore: cancel_subscriptions
  StreamSubscription<MediaSessionCommand>? _mediaSubscription;
  PlaybackController? _controller;
  bool _resumeAfterInterruption = false;
  bool _active = false;

  Future<void> start({
    required PlaybackController controller,
    double? contentFps,
    int? width,
    int? height,
    AudioStreamSpec? audioSpec,
  }) async {
    if (_active) throw StateError('platform policy already started');
    _active = true;
    _controller = controller;
    _eventSubscription = events.listen(_onPlatformEvent);
    _mediaSubscription = mediaCommands.listen(_onMediaCommand);
    try {
      final report = await capabilities.probe();
      _capabilityReport = report;
      _recordPolicy('capabilities', 'probed');

      if (contentFps != null) {
        await matchDisplay(
          contentFps: contentFps,
          width: width,
          height: height,
        );
      } else {
        _recordDisplay(
          'displayMode',
          displayModeMatchingEnabled ? 'unknown-content-fps' : 'disabled',
        );
      }

      if (passthroughEnabled && audioSpec != null) {
        if (!report.audioPassthrough) {
          _recordAudio('passthrough', 'unsupported');
        } else {
          final negotiation = await audio.negotiate(audioSpec);
          _recordAudio(
            'passthrough',
            negotiation.passthrough ? 'granted' : 'fallback',
          );
          if (negotiation.fallbackReason != null) {
            _recordAudio('passthroughFallback', negotiation.fallbackReason!);
          }
          _recordAudio('audioDevice', negotiation.deviceId);
        }
      } else {
        _recordAudio(
          'passthrough',
          passthroughEnabled ? 'unknown-content-spec' : 'disabled',
        );
      }

      _releaseKeepAwake = await acquireKeepAwake();
      _recordPolicy('keepAwake', 'leased');
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  /// Leases the display mode matching [contentFps]; released by [stop]. A
  /// no-op when matching is off or the policy is stopped, and while a lease
  /// is held unless [DisplayMatchOptions.rematchOnChange] and the frame rate
  /// changed.
  Future<void> matchDisplay({
    required double contentFps,
    int? width,
    int? height,
  }) async {
    if (!_active) return;
    if (!displayModeMatchingEnabled) {
      _recordDisplay('displayMode', 'disabled');
      return;
    }
    if (_displayLease != null) {
      if (!displayOptions.rematchOnChange || _matchedFps == contentFps) return;
      final previous = _displayLease!;
      _displayLease = null;
      await previous.release();
    }
    if (!(_capabilityReport?.displayModeSwitching ?? false)) {
      _recordDisplay('displayMode', 'unsupported');
      return;
    }
    final options = displayOptions;
    final fps = options.forcedRefreshHz ?? contentFps;
    final matchWidth = options.matchResolution ? width : null;
    final matchHeight = options.matchResolution ? height : null;
    if (options.whitelist.invalid.isNotEmpty) {
      _recordDisplay('whitelistInvalid', options.whitelist.invalid.join(','));
    }
    final DisplayModeLease? lease;
    if (identical(options.whitelist, DisplayModeWhitelist.all)) {
      lease = await displayModes.matchFor(
        contentFps: fps,
        width: matchWidth,
        height: matchHeight,
      );
    } else {
      final modes = await displayModes.availableModes();
      final match = ModeMatcher.match(
        contentFps: fps,
        modes: options.whitelist.filter(modes),
        current: modes.where((mode) => mode.isCurrent).firstOrNull,
        width: matchWidth,
        height: matchHeight,
      );
      // The service picks the closest mode to the cadence it is given, so
      // handing it the chosen mode's own geometry selects exactly that mode.
      lease = match == null
          ? null
          : await displayModes.matchFor(
              contentFps: match.mode.refreshHz,
              width: match.mode.width,
              height: match.mode.height,
            );
    }
    if (!_active) {
      // Stopped while matching: nobody else will release this lease.
      await lease?.release();
      return;
    }
    _displayLease = lease;
    _matchedFps = lease == null ? null : contentFps;
    _recordDisplay('displayMode', lease == null ? 'unavailable' : 'leased');
  }

  Future<void> stop() async {
    if (!_active &&
        _displayLease == null &&
        _releaseKeepAwake == null &&
        _controller == null) {
      return;
    }
    _active = false;
    final eventSubscription = _eventSubscription;
    _eventSubscription = null;
    final mediaSubscription = _mediaSubscription;
    _mediaSubscription = null;
    Object? firstError;
    StackTrace? firstStack;
    try {
      await eventSubscription?.cancel();
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    try {
      await mediaSubscription?.cancel();
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    final releaseKeepAwake = _releaseKeepAwake;
    _releaseKeepAwake = null;
    if (releaseKeepAwake != null) {
      try {
        await releaseKeepAwake();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    final displayLease = _displayLease;
    _displayLease = null;
    if (displayLease != null) {
      try {
        await displayLease.release();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    try {
      await clearMediaSession();
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    _controller = null;
    _matchedFps = null;
    _resumeAfterInterruption = false;
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  void _onPlatformEvent(PlatformEvent event) {
    final controller = _controller;
    if (controller == null) return;
    switch (event.type) {
      case PlatformEventType.audioInterruptionBegan:
        _resumeAfterInterruption =
            event.lossKind != 'permanent' &&
            event.shouldResume &&
            controller.currentState.isPlaying;
        unawaited(controller.pause());
      case PlatformEventType.becameNoisy:
      case PlatformEventType.appBackgrounded:
        _resumeAfterInterruption = false;
        unawaited(controller.pause());
      case PlatformEventType.audioInterruptionEnded:
      case PlatformEventType.appForegrounded:
        if (event.shouldResume || _resumeAfterInterruption) {
          _resumeAfterInterruption = false;
          unawaited(controller.play());
        }
      case PlatformEventType.audioRouteChanged:
      case PlatformEventType.mediaCommand:
      case PlatformEventType.unknown:
        break;
    }
  }

  void _onMediaCommand(MediaSessionCommand command) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(_applyMediaCommand(controller, command));
  }

  Future<void> _applyMediaCommand(
    PlaybackController controller,
    MediaSessionCommand command,
  ) async {
    switch (command.type) {
      case MediaSessionCommandType.play:
        await controller.play();
      case MediaSessionCommandType.pause:
        await controller.pause();
      case MediaSessionCommandType.togglePlay:
        if (controller.currentState.isPlaying) {
          await controller.pause();
        } else {
          await controller.play();
        }
      case MediaSessionCommandType.seekTo:
        if (command.position != null) await controller.seek(command.position!);
      case MediaSessionCommandType.skipForward:
        await controller.seek(
          controller.currentState.position + const Duration(seconds: 30),
        );
      case MediaSessionCommandType.skipBackward:
        final position =
            controller.currentState.position - const Duration(seconds: 10);
        await controller.seek(
          position < Duration.zero ? Duration.zero : position,
        );
      case MediaSessionCommandType.stop:
        await controller.pause();
      case MediaSessionCommandType.unknown:
        break;
    }
  }

  void _recordDisplay(String key, String value) {
    _displayDiagnostics[key] = value;
    _refreshDiagnostics();
  }

  void _recordAudio(String key, String value) {
    _audioDiagnostics[key] = value;
    _refreshDiagnostics();
  }

  void _recordPolicy(String key, String value) {
    _policyDiagnostics[key] = value;
    _refreshDiagnostics();
  }

  void _refreshDiagnostics() {
    diagnostics.collect(
      capabilities: _capabilityReport,
      display: _displayDiagnostics,
      audio: _audioDiagnostics,
      playback: _policyDiagnostics,
    );
  }
}
