import 'dart:io' show Platform;

import 'platform_channel.dart';

enum PlatformKind { android, ios, macos, windows, unsupported }

/// The only file in this package that reads [Platform.is*].
final class PlatformDispatch {
  const PlatformDispatch({PlatformKind? kind, PlatformKind? platform})
    : kind = kind ?? platform;

  /// Optional override used by tests and embedders running a platform shim.
  final PlatformKind? kind;

  PlatformKind get resolved => kind ?? current;

  static PlatformKind get current {
    if (Platform.isAndroid) return PlatformKind.android;
    if (Platform.isIOS) return PlatformKind.ios;
    if (Platform.isMacOS) return PlatformKind.macos;
    if (Platform.isWindows) return PlatformKind.windows;
    return PlatformKind.unsupported;
  }

  static PlatformChannel channel({PlatformChannel? override}) =>
      override ?? MethodPlatformChannel();
}
