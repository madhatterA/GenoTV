import 'dart:io';

import 'package:core/core.dart';

import 'aria2_backend.dart';
import 'ffi/aria2_ffi_backend.dart';

enum TransportPlatform { windows, macos, linux, android, ios }

/// Returns the in-process libaria2 [Aria2Backend] for every platform (owner
/// decision: no aria2c program). A platform whose libaria2 is not built yet
/// fails at `start()` with a `TransportFailure` naming the missing library.
Aria2Backend createHttpBackend({
  TransportPlatform? platform,
  AppLogger? logger,
}) {
  final resolved = platform ?? currentTransportPlatform();
  logger?.info(
    'http backend selected',
    data: {'backend': 'Aria2FfiBackend', 'platform': resolved.name},
  );
  return Aria2FfiBackend(logger: logger);
}

TransportPlatform currentTransportPlatform() {
  if (Platform.isWindows) return TransportPlatform.windows;
  if (Platform.isLinux) return TransportPlatform.linux;
  if (Platform.isAndroid) return TransportPlatform.android;
  if (Platform.isIOS) return TransportPlatform.ios;
  return TransportPlatform.macos;
}
