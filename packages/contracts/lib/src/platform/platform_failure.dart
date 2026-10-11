import 'package:core/core.dart';

/// Platform-capability failures, `platform.*` prefix
/// (`planning/CONTRACTS.md` §0 registry, owned by Part 05).
///
/// Lives in `packages/contracts`, not `packages/platform_services`: fields
/// of `PlatformCapabilities`/`DisplayModeService`/`AudioOutputService`
/// callers need to name it.
final class PlatformFailure extends AppFailure {
  const PlatformFailure.unsupported({super.cause, super.stack})
      : super(code: _unsupported, message: 'Not supported on this platform');

  const PlatformFailure.permissionDenied({super.cause, super.stack})
      : super(code: _permissionDenied, message: 'Permission was denied');

  const PlatformFailure.displaySwitchFailed({required super.cause, super.stack})
      : super(code: _displaySwitchFailed, message: 'Failed to switch the display mode');

  const PlatformFailure.audioDeviceLost({super.cause, super.stack})
      : super(code: _audioDeviceLost, message: 'The audio output device was lost');

  const PlatformFailure.probeFailed({required super.cause, super.stack})
      : super(code: _probeFailed, message: 'Failed to probe platform capabilities');

  static const String _unsupported = 'platform.unsupported';
  static const String _permissionDenied = 'platform.permission_denied';
  static const String _displaySwitchFailed = 'platform.display.switch_failed';
  static const String _audioDeviceLost = 'platform.audio.device_lost';
  static const String _probeFailed = 'platform.probe.failed';
}
