import 'dart:io' show Platform;

import 'platform_channel.dart';

enum PlatformKind { android, ios, tvos, macos, windows, unsupported }

/// The only file in this package that reads [Platform.is*].
final class PlatformDispatch {
  const PlatformDispatch({PlatformKind? kind, PlatformKind? platform})
    : kind = kind ?? platform;

  /// Optional override used by tests and embedders running a platform shim.
  final PlatformKind? kind;

  PlatformKind get resolved => kind ?? current;

  static PlatformKind get current =>
      fromOperatingSystem(Platform.operatingSystem);

  /// flutter-tvos reports `tvos` here while [Platform.isIOS] is also true, so
  /// the OS name (not `isIOS`) decides.
  static PlatformKind fromOperatingSystem(String os) => switch (os) {
    'android' => PlatformKind.android,
    'tvos' => PlatformKind.tvos,
    'ios' => PlatformKind.ios,
    'macos' => PlatformKind.macos,
    'windows' => PlatformKind.windows,
    _ => PlatformKind.unsupported,
  };

  static PlatformChannel channel({PlatformChannel? override}) =>
      override ?? MethodPlatformChannel();
}
