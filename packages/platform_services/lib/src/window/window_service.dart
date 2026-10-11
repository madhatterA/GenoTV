import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';

import '../channel/platform_channel.dart';

/// The app window's mode. The one place the Fullscreen / Windowed setting
/// reaches the OS; the native side owns the actual window.
final class WindowService {
  WindowService({required this.channel});

  final PlatformChannel channel;
  Future<void> _pending = Future<void>.value();

  /// Puts the window into or out of native fullscreen. A platform without a
  /// window to switch, or a failing switch, throws a typed [PlatformFailure].
  Future<void> setFullscreen(bool enabled) {
    // Preserve each caller's failure while letting the next request proceed.
    final next = _pending.then(
      (_) => _applyFullscreen(enabled),
      onError: (Object error, StackTrace stack) => _applyFullscreen(enabled),
    );
    _pending = next;
    return next;
  }

  Future<void> _applyFullscreen(bool enabled) async {
    final Object? result;
    try {
      result = await channel.invoke(PlatformMethods.windowFullscreen, {
        'enabled': enabled,
      });
    } on PlatformException catch (error, stack) {
      throw mapPlatformError(error, stack);
    }
    final map = asMap(result);
    if (!boolValue(map['supported'])) {
      throw PlatformFailure.unsupported(
        cause: stringValue(map['reason']) ?? 'window.fullscreen not supported',
      );
    }
  }
}
