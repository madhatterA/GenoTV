import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

final class LocalTransportFailure extends AppFailure {
  const LocalTransportFailure.notFound({required super.cause})
    : super(
        code: 'transport.local.not_found',
        message: 'Local file was not found',
      );
  const LocalTransportFailure.notReadable({required super.cause})
    : super(
        code: 'transport.local.not_readable',
        message: 'Local file is not readable',
      );
  const LocalTransportFailure.empty({required super.cause})
    : super(code: 'transport.local.empty', message: 'Local file is empty');
  const LocalTransportFailure.unsupportedUri({required super.cause})
    : super(
        code: 'transport.local.unsupported_uri',
        message: 'Content URI is not supported',
      );
}

class LocalFileHandle implements StreamHandle {
  LocalFileHandle._(this._file, this._size) {
    _status = SourceStatus(
      state: SourceState.ready,
      available: RangeSet.empty().add(ByteRange(0, _size - 1)),
      totalBytes: _size,
      bytesPerSecond: 0,
      peersOrConnections: 0,
    );
  }

  final File _file;
  final int _size;
  late final SourceStatus _status;
  bool _disposed = false;

  static Future<LocalFileHandle> open(Uri uri) async {
    if (uri.scheme != 'file') {
      throw LocalTransportFailure.unsupportedUri(cause: uri);
    }
    final file = File(uri.toFilePath());
    if (!await file.exists()) {
      throw LocalTransportFailure.notFound(cause: file.path);
    }
    if (await FileSystemEntity.isDirectory(file.path)) {
      throw LocalTransportFailure.notReadable(cause: 'directory: ${file.path}');
    }
    late int size;
    try {
      size = await file.length();
    } catch (error) {
      throw LocalTransportFailure.notReadable(cause: error);
    }
    if (size <= 0) throw LocalTransportFailure.empty(cause: file.path);
    return LocalFileHandle._(file, size);
  }

  @override
  Uri get playbackUri {
    _check();
    return _file.uri;
  }

  @override
  int get totalBytes {
    _check();
    return _size;
  }

  @override
  Stream<SourceStatus> get status {
    if (_disposed) return const Stream<SourceStatus>.empty();
    return Stream<SourceStatus>.value(_status);
  }

  @override
  Future<void> seekHint(int byteOffset) async {
    _check();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  void _check() {
    if (_disposed) throw StateError('stream handle is disposed');
  }
}
