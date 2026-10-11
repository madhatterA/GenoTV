import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../torrent/lt_ffi_session.dart';

typedef _PunchNative = Int32 Function(Pointer<Utf8>, Int32, Int64, Int64);
typedef _Punch = int Function(Pointer<Utf8>, int, int, int);
typedef _FreeNative = Int64 Function(Pointer<Utf8>, Int32);
typedef _Free = int Function(Pointer<Utf8>, int);
typedef _AllocatedNative = Int64 Function(Pointer<Utf8>, Int32, Int64, Int64);
typedef _Allocated = int Function(Pointer<Utf8>, int, int, int);

class FsNativeException implements Exception {
  const FsNativeException(this.operation, this.path, this.code);
  final String operation;
  final String path;
  final int code;
  @override
  String toString() => 'FsNativeException: $operation $path failed ($code)';
}

/// Disk-block helpers from the native shim (`fs_shim.c`): the one place that
/// knows how each OS frees blocks inside a file and measures what a file
/// really occupies.
class FsNative {
  FsNative([DynamicLibrary? library]) {
    final lib = library ?? LtFfiSession.openLibrary();
    _punch = lib.lookupFunction<_PunchNative, _Punch>(
      'transport_lt_fs_punch_hole',
    );
    _free = lib.lookupFunction<_FreeNative, _Free>(
      'transport_lt_fs_free_bytes',
    );
    _allocated = lib.lookupFunction<_AllocatedNative, _Allocated>(
      'transport_lt_fs_allocated_bytes',
    );
  }

  late final _Punch _punch;
  late final _Allocated _allocated;
  late final _Free _free;

  /// Bytes still available to the app on the volume that holds [path].
  int freeBytes(String path) {
    final bytes = _withPath(path, (p, n) => _free(p, n));
    if (bytes < 0) throw FsNativeException('free bytes', path, bytes);
    return bytes;
  }

  /// Frees the disk blocks of [length] bytes at [offset] without changing the
  /// file size. The range is rounded inward to whole volume blocks.
  void punchHole(String path, int offset, int length) {
    final code = _withPath(path, (p, n) => _punch(p, n, offset, length));
    if (code != 0) throw FsNativeException('punch hole', path, code);
  }

  /// Bytes the file really occupies in `[offset, offset + length)`; the whole
  /// file when [length] is null.
  int allocatedBytes(String path, {int offset = 0, int? length}) {
    final bytes = _withPath(
      path,
      (p, n) => _allocated(p, n, offset, length ?? -1),
    );
    if (bytes < 0) throw FsNativeException('allocated bytes', path, bytes);
    return bytes;
  }

  T _withPath<T>(String path, T Function(Pointer<Utf8>, int) body) {
    final p = path.toNativeUtf8();
    try {
      return body(p, utf8.encode(path).length);
    } finally {
      malloc.free(p);
    }
  }
}
