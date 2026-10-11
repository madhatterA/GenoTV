import 'package:flutter/services.dart';
import 'package:contracts/contracts.dart';

/// Namespaced calls shared by Dart and every native implementation.
abstract final class PlatformMethods {
  static const channelName = 'platform_services';
  static const eventsChannelName = 'platform_services/events';
  static const version = 'capabilities.version';
  static const probe = 'capabilities.probe';
  static const displayModes = 'display.modes';
  static const displayApply = 'display.apply';
  static const displayRestore = 'display.restore';
  static const audioDevices = 'audio.devices';
  static const audioNegotiate = 'audio.negotiate';
  static const windowFullscreen = 'window.fullscreen';
  static const lifecycleKeepAwake = 'lifecycle.keepAwake';
  static const lifecycleReleaseAwake = 'lifecycle.releaseKeepAwake';
  static const mediaSessionUpdate = 'lifecycle.mediaSession.update';
  static const mediaSessionClear = 'lifecycle.mediaSession.clear';
}

/// The sole Dart/native transport. Payloads are maps/lists of primitives:
/// modes `{width,height,refreshHz,isCurrent}`, devices `{id,name,kind,isCurrent}`;
/// negotiation `{codec,channels,sampleRate,bitDepth,requestedPassthrough}`;
/// capability reports use the [CapabilityReport] field names.
abstract interface class PlatformChannel {
  Future<Object?> invoke(String method, [Object? arguments]);

  Stream<Object?> get events;

  Future<void> dispose() async {}
}

final class MethodPlatformChannel implements PlatformChannel {
  MethodPlatformChannel({MethodChannel? methods, EventChannel? eventChannel})
    : _methods = methods ?? const MethodChannel(PlatformMethods.channelName),
      _events =
          (eventChannel ??
                  const EventChannel(PlatformMethods.eventsChannelName))
              .receiveBroadcastStream();

  final MethodChannel _methods;
  final Stream<Object?> _events;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) =>
      _methods.invokeMethod<Object?>(method, arguments);

  @override
  Stream<Object?> get events => _events;

  @override
  Future<void> dispose() async {}
}

PlatformFailure mapPlatformError(Object error, [StackTrace? stack]) {
  if (error is PlatformException) {
    switch (error.code) {
      case 'platform.permission_denied':
        return PlatformFailure.permissionDenied(cause: error, stack: stack);
      case 'platform.display.switch_failed':
        return PlatformFailure.displaySwitchFailed(cause: error, stack: stack);
      case 'platform.audio.device_lost':
        return PlatformFailure.audioDeviceLost(cause: error, stack: stack);
      case 'platform.probe.failed':
        return PlatformFailure.probeFailed(cause: error, stack: stack);
      case 'platform.unsupported':
      default:
        return PlatformFailure.unsupported(cause: error, stack: stack);
    }
  }
  return PlatformFailure.probeFailed(cause: error, stack: stack);
}

Map<String, Object?> asMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : const {};

String? stringValue(Object? value) => value is String ? value : null;

bool boolValue(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;

double? doubleValue(Object? value) => value is num ? value.toDouble() : null;

int? intValue(Object? value) => value is num ? value.toInt() : null;
