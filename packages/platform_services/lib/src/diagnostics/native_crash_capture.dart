import 'package:flutter/foundation.dart';

import '../channel/platform_channel.dart';

/// Installs the in-process native recorder after the previous pending file is read.
final class NativeCrashCapture {
  NativeCrashCapture({PlatformChannel? channel})
    : _channel = channel ?? MethodPlatformChannel();

  final PlatformChannel _channel;

  Future<void> install(String path) async {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'A crash file path is required');
    }
    await _channel.invoke('crash.install', {'path': path});
  }

  Future<void> uninstall() async {
    await _channel.invoke('crash.uninstall');
  }

  Future<void> abortForProof() async {
    if (!kDebugMode) throw StateError('Crash proof requires a debug build');
    await _channel.invoke('crash.proof.abort');
  }
}
