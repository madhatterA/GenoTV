import 'dart:ffi';
import 'dart:io';

import 'package:core/core.dart';

const int _rlimitNofile = 8; // same value on macOS, Linux and Android
const int _wantedSoftLimit = 4096;

final class _RLimit extends Struct {
  @Uint64()
  external int soft;
  @Uint64()
  external int hard;
}

typedef _LimitC = Int32 Function(Int32, Pointer<_RLimit>);
typedef _LimitDart = int Function(int, Pointer<_RLimit>);

/// Raises the process open-file soft limit to min(hard limit, 4096) and logs
/// old -> new. Never lowers it. A GUI app on macOS starts at 256, which
/// libtorrent peers, its file pool, sockets and mpv share. POSIX (macOS now;
/// Linux/Android/iOS reuse it in their Phases). Windows has no RLIMIT_NOFILE
/// and tvOS is not checked yet: both are no-ops here until their Phases.
/// Returns the soft limit in force afterwards, or null where not applicable.
int? raiseOpenFileLimit(AppLogger logger) {
  if (!(Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS)) {
    return null;
  }
  final libc = DynamicLibrary.process();
  final get = libc.lookupFunction<_LimitC, _LimitDart>('getrlimit');
  final set = libc.lookupFunction<_LimitC, _LimitDart>('setrlimit');
  final malloc = libc.lookupFunction<Pointer<Void> Function(IntPtr),
      Pointer<Void> Function(int)>('malloc');
  final free = libc.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final raw = malloc(sizeOf<_RLimit>());
  final limit = raw.cast<_RLimit>();
  try {
    if (get(_rlimitNofile, limit) != 0) {
      logger.warn('getrlimit(NOFILE) failed', error: 'errno ${_errno(libc)}');
      return null;
    }
    final old = limit.ref.soft;
    final target = limit.ref.hard < _wantedSoftLimit
        ? limit.ref.hard
        : _wantedSoftLimit;
    if (old >= target) {
      logger.info('Open file limit $old (unchanged, wanted $target)');
      return old;
    }
    limit.ref.soft = target;
    if (set(_rlimitNofile, limit) != 0) {
      logger.warn(
        'setrlimit(NOFILE) failed; staying at $old',
        error: 'errno ${_errno(libc)}',
      );
      return old;
    }
    logger.info('Open file limit raised $old -> $target');
    return target;
  } finally {
    free(raw);
  }
}

int _errno(DynamicLibrary libc) {
  final name = Platform.isMacOS || Platform.isIOS
      ? '__error'
      : Platform.isAndroid
      ? '__errno'
      : '__errno_location';
  return libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        name,
      )()
      .value;
}
