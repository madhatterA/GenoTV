import 'package:core/core.dart';
import 'package:media_kit/media_kit.dart';

/// Process-wide media_kit initialization.
final class EngineBootstrap {
  EngineBootstrap._();

  static bool _initialized = false;

  static void ensureInitialised({AppLogger? logger}) {
    if (_initialized) return;
    MediaKit.ensureInitialized();
    _initialized = true;
    logger?.info('media engine initialized', data: const {'backend': 'libmpv'});
  }
}
