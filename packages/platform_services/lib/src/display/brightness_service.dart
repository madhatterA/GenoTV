import 'package:flutter/services.dart';

import '../channel/platform_channel.dart';

/// The app window's screen brightness (phones only). The OS brightness is
/// never changed: iOS sets the screen level and remembers the original,
/// Android overrides the window's level. [restore] hands control back.
final class BrightnessService {
  BrightnessService({required this.channel});

  final PlatformChannel channel;

  /// The current level 0..1, or null where the platform has no such control.
  Future<double?> current() async {
    final map = asMap(await _invoke(PlatformMethods.brightnessGet));
    return boolValue(map['supported']) ? doubleValue(map['level']) : null;
  }

  Future<void> set(double level) => _invoke(PlatformMethods.brightnessSet, {
    'level': level.clamp(0.0, 1.0),
  });

  /// Back to the system brightness.
  Future<void> restore() => _invoke(PlatformMethods.brightnessRestore);

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await channel.invoke(method, arguments);
    } on PlatformException catch (error, stack) {
      throw mapPlatformError(error, stack);
    }
  }
}
