import 'dart:convert';
import 'dart:ffi';

import 'package:contracts/contracts.dart';
import 'package:ffi/ffi.dart';

import '../aria2_availability.dart';
import 'aria2_ffi_bindings.dart';

final class Aria2FfiException implements Exception {
  const Aria2FfiException(this.operation, this.message, [this.code]);
  final String operation;
  final String message;
  final int? code;

  @override
  String toString() => 'aria2 $operation failed: $message';
}

final class Aria2FfiStatus {
  Aria2FfiStatus({
    required this.state,
    required this.errorCode,
    required this.connections,
    required this.pieceLength,
    required this.pieceCount,
    required this.totalLength,
    required this.completedLength,
    required this.downloadRate,
    required List<int> bitfield,
  }) : bitfield = List<int>.unmodifiable(bitfield);

  final int state;
  final int errorCode;
  final int connections;
  final int pieceLength;
  final int pieceCount;
  final int totalLength;
  final int completedLength;
  final int downloadRate;
  final List<int> bitfield;

  // aria2 reports errorCode -1 while a download is still running; only the
  // DOWNLOAD_ERROR state (4) is a failure.
  Aria2FfiException? get failure => state != 4 || errorCode == 0
      ? null
      : Aria2FfiException(
          'download',
          'native error code $errorCode',
          errorCode,
        );

  RangeSet get available {
    if (totalLength <= 0 || pieceLength <= 0) return RangeSet.empty();
    return rangesFromBitfield(
      _hexBitfield(bitfield),
      pieceLength: pieceLength,
      totalBytes: totalLength,
    );
  }
}

String _hexBitfield(List<int> bytes) {
  const digits = '0123456789abcdef';
  final result = StringBuffer();
  for (final byte in bytes) {
    result
      ..write(digits[(byte >> 4) & 0xf])
      ..write(digits[byte & 0xf]);
  }
  return result.toString();
}

final class Aria2FfiSession implements Finalizable {
  Aria2FfiSession(DynamicLibrary library) : this._(Aria2FfiBindings(library));

  Aria2FfiSession._(this._bindings)
    : _allocator = calloc,
      _handle = _bindings.create() {
    if (_handle == nullptr) {
      throw const Aria2FfiException(
        'create session',
        'native session returned null',
      );
    }
    _finalizer = NativeFinalizer(_bindings.destroyAddress.cast());
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  final Aria2FfiBindings _bindings;
  final Allocator _allocator;
  final Pointer<Void> _handle;
  late final NativeFinalizer _finalizer;
  bool _disposed = false;

  Pointer<Void> get nativeHandle => _handle;
  bool get isDisposed => _disposed;

  String get error {
    if (_disposed) return 'session closed';
    final buffer = _allocator.allocate<Utf8>(1024);
    try {
      final length = _bindings.lastError(_handle, buffer, 1024);
      return buffer.toDartString(length: length.clamp(0, 1023));
    } finally {
      _allocator.free(buffer);
    }
  }

  int addUri(
    Uri uri, {
    required String directory,
    String? output,
    Map<String, String> headers = const <String, String>{},
    Map<String, String> options = const <String, String>{},
  }) {
    _checkOpen();
    final uriPointer = uri.toString().toNativeUtf8(allocator: _allocator);
    final directoryPointer = directory.toNativeUtf8(allocator: _allocator);
    final outputPointer = (output ?? '').toNativeUtf8(allocator: _allocator);
    final headerBlock = headers.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    final headersPointer = headerBlock.toNativeUtf8(allocator: _allocator);
    final effectiveOptions = <String, String>{
      'file-allocation': 'none',
      ...options,
    };
    final optionBlock = effectiveOptions.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
    final optionsPointer = optionBlock.toNativeUtf8(allocator: _allocator);
    final gidPointer = _allocator.allocate<Uint64>(sizeOf<Uint64>());
    try {
      final result = _bindings.addUri(
        _handle,
        uriPointer,
        utf8.encode(uri.toString()).length,
        directoryPointer,
        utf8.encode(directory).length,
        outputPointer,
        utf8.encode(output ?? '').length,
        headersPointer,
        utf8.encode(headerBlock).length,
        optionsPointer,
        utf8.encode(optionBlock).length,
        gidPointer,
      );
      if (result != 0) _throwNative('add URI', result);
      return gidPointer.value;
    } finally {
      _allocator.free(uriPointer);
      _allocator.free(directoryPointer);
      _allocator.free(outputPointer);
      _allocator.free(headersPointer);
      _allocator.free(optionsPointer);
      _allocator.free(gidPointer);
    }
  }

  Aria2FfiStatus status(int gid) {
    _checkOpen();
    final statusPointer = _allocator.allocate<Aria2DownloadStatus>(
      sizeOf<Aria2DownloadStatus>(),
    );
    Pointer<Uint8> bitfieldPointer = nullptr;
    var capacity = 0;
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        if (bitfieldPointer != nullptr) _allocator.free(bitfieldPointer);
        bitfieldPointer = capacity == 0
            ? nullptr
            : _allocator.allocate<Uint8>(capacity);
        final result = _bindings.status(
          _handle,
          gid,
          statusPointer,
          bitfieldPointer,
          capacity,
        );
        if (result != 0 && result != -2) _throwNative('status', result);
        final required = statusPointer.ref.bitfieldLength;
        if (result == -2) {
          if (required <= capacity || required < 0) {
            throw const Aria2FfiException(
              'status',
              'native bitfield capacity did not increase',
              -2,
            );
          }
          capacity = required;
          continue;
        }
        if (required < 0 || required > capacity) {
          throw Aria2FfiException(
            'status',
            'native bitfield length $required exceeds capacity $capacity',
          );
        }
        return Aria2FfiStatus(
          state: statusPointer.ref.state,
          errorCode: statusPointer.ref.errorCode,
          connections: statusPointer.ref.connections,
          pieceLength: statusPointer.ref.pieceLength,
          pieceCount: statusPointer.ref.pieceCount,
          totalLength: statusPointer.ref.totalLength,
          completedLength: statusPointer.ref.completedLength,
          downloadRate: statusPointer.ref.downloadRate,
          bitfield: required == 0
              ? const <int>[]
              : List<int>.from(bitfieldPointer.asTypedList(required)),
        );
      }
      throw const Aria2FfiException(
        'status',
        'native bitfield capacity changed repeatedly',
      );
    } finally {
      if (bitfieldPointer != nullptr) _allocator.free(bitfieldPointer);
      _allocator.free(statusPointer);
    }
  }

  int poll() {
    _checkOpen();
    final result = _bindings.poll(_handle);
    if (result < 0) _throwNative('poll', result);
    return result;
  }

  void changeOption(int gid, String name, String value) {
    _checkOpen();
    final namePointer = name.toNativeUtf8(allocator: _allocator);
    final valuePointer = value.toNativeUtf8(allocator: _allocator);
    try {
      final result = _bindings.changeOption(
        _handle,
        gid,
        namePointer,
        utf8.encode(name).length,
        valuePointer,
        utf8.encode(value).length,
      );
      if (result != 0) _throwNative('change option', result);
    } finally {
      _allocator.free(namePointer);
      _allocator.free(valuePointer);
    }
  }

  /// The download's current value of one aria2 option.
  String option(int gid, String name) {
    _checkOpen();
    final namePointer = name.toNativeUtf8(allocator: _allocator);
    const capacity = 4096;
    final out = _allocator.allocate<Utf8>(capacity);
    try {
      final length = _bindings.getOption(
        _handle,
        gid,
        namePointer,
        utf8.encode(name).length,
        out,
        capacity,
      );
      if (length < 0) _throwNative('get option', length);
      return out.toDartString(length: length.clamp(0, capacity - 1));
    } finally {
      _allocator.free(namePointer);
      _allocator.free(out);
    }
  }

  void remove(int gid) {
    _checkOpen();
    final result = _bindings.remove(_handle, gid);
    if (result != 0) _throwNative('remove', result);
  }

  void setPaused(int gid, {required bool paused}) {
    _checkOpen();
    final result = _bindings.setPaused(_handle, gid, paused ? 1 : 0);
    if (result != 0) _throwNative('set paused', result);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_handle);
  }

  void _checkOpen() {
    if (_disposed) throw StateError('aria2 session is closed');
  }

  Never _throwNative(String operation, int code) {
    throw Aria2FfiException(operation, error, code);
  }
}
