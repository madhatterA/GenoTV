import 'package:contracts/contracts.dart';

/// mpv reads HLS playlists itself; there is no local byte transport.
final class DirectUrlHandle implements StreamHandle {
  DirectUrlHandle(this._uri);

  final Uri _uri;
  bool _disposed = false;
  final SourceStatus _ready = SourceStatus(
    state: SourceState.ready,
    available: RangeSet.empty(),
    totalBytes: null,
    bytesPerSecond: 0,
    peersOrConnections: 0,
  );

  @override
  Uri get playbackUri {
    _check();
    return _uri;
  }

  @override
  int? get totalBytes {
    _check();
    return null;
  }

  @override
  Stream<SourceStatus> get status =>
      _disposed ? const Stream.empty() : Stream.value(_ready);
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
