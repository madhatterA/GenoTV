import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'lt_ffi_session.dart';

/// Dart-facing owner for a real libtorrent session and its torrent handles.
/// Native alerts are polled on the Dart timer owned by [LtFfiSession].
final class TorrentSession {
  TorrentSession({DynamicLibrary? library, String? savePath})
    : _native = LtFfiSession(library: library),
      defaultSavePath = savePath;

  final LtFfiSession _native;
  final String? defaultSavePath;
  bool _started = false;
  LtFfiSession get native => _native;
  bool get isStarted => _started && !_native.isDisposed;
  Stream<LtAlertEvent> get alerts => _native.alerts;

  Future<void> start() async {
    if (_native.isDisposed) throw StateError('torrent session is closed');
    _started = true;
  }

  LtTorrent addMagnet(
    String magnet, {
    String? savePath,
    bool payloadPaused = false,
  }) {
    _requireStarted();
    return _native.addMagnet(
      magnet,
      savePath: savePath ?? defaultSavePath ?? _defaultPath(),
      payloadPaused: payloadPaused,
    );
  }

  LtTorrent addTorrent(
    Uint8List torrent, {
    String? savePath,
    bool payloadPaused = false,
  }) {
    _requireStarted();
    return _native.addTorrent(
      torrent,
      savePath: savePath ?? defaultSavePath ?? _defaultPath(),
      payloadPaused: payloadPaused,
    );
  }

  LtTorrent loadResume(
    Uint8List resume, {
    String? savePath,
    bool payloadPaused = false,
  }) {
    _requireStarted();
    return _native.loadResume(
      resume,
      savePath: savePath ?? defaultSavePath ?? _defaultPath(),
      payloadPaused: payloadPaused,
    );
  }

  Future<void> dispose() async {
    if (!_started && _native.isDisposed) return;
    _started = false;
    await _native.dispose();
  }

  void _requireStarted() {
    if (!isStarted) throw StateError('torrent session has not been started');
  }

  String _defaultPath() => '.';
}
