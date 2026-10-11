import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'lt_bindings.dart';

class LtNativeException implements Exception {
  const LtNativeException(this.operation, this.message);
  final String operation;
  final String message;
  @override
  String toString() => 'libtorrent $operation failed: $message';
}

/// Owns one native session. Calls are synchronous and alerts are drained by a
/// Dart timer, so no libtorrent worker thread ever calls Dart.
final class LtFfiSession {
  LtFfiSession({
    DynamicLibrary? library,
    this._alertInterval = const Duration(milliseconds: 100),
  }) : _allocator = calloc {
    _library = library ?? openLibrary();
    _bindings = LtBindings(_library);
    _handle = _bindings.create();
    if (_handle == nullptr) {
      throw const LtNativeException(
        'create session',
        'native session returned null',
      );
    }
    _timer = Timer.periodic(_alertInterval, (_) => _drainAlerts());
  }

  late final DynamicLibrary _library;
  late final LtBindings _bindings;
  final Allocator _allocator;
  final Duration _alertInterval;
  late final Pointer<Void> _handle;
  late final Timer _timer;
  final StreamController<LtAlertEvent> _alerts =
      StreamController<LtAlertEvent>.broadcast();
  // Must be >= libtorrent's own alert_queue_size (lt_shim.cpp: 20000). A
  // single native transport_lt_pop_alerts() call drains libtorrent's entire
  // pending-alert queue in one C++ pop_alerts() and then truncates silently
  // at this buffer's capacity -- any native alert beyond that cap is
  // discarded with no drop signal Dart can observe (found via a real 8 KiB
  // piece-length burst that produced ~12,900 alerts in a single drain tick
  // and silently lost ~3,000 of them while reporting zero drops; see
  // bug_history.md). Sizing this to match alert_queue_size means the native
  // queue itself can never hand a single pop_alerts() call more than this
  // buffer holds -- libtorrent's own alerts_dropped_alert (kind 10, already
  // forwarded below) is the only path a real drop can occur through now.
  static const int _alertCap = 20000;
  late final Pointer<LtAlert> _alertRecords = _allocator.allocate<LtAlert>(
    sizeOf<LtAlert>() * _alertCap,
  );
  late final Pointer<Utf8> _alertMessages = _allocator.allocate<Utf8>(
    1024 * 1024,
  );
  bool _disposed = false;

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

  Stream<LtAlertEvent> get alerts => _alerts.stream;
  Pointer<Void> get nativeHandle => _handle;
  bool get isDisposed => _disposed;

  /// Applies libtorrent `settings_pack` entries by name (e.g.
  /// `download_rate_limit`) to the running session.
  void applySettings(Map<String, String> settings) {
    _checkOpen();
    if (settings.isEmpty) return;
    final block = settings.entries.map((e) => '${e.key}=${e.value}').join('\n');
    if (_nativeSet(_bindings.sessionSet, _handle, block) < 0) {
      throw LtNativeException('apply settings', error);
    }
  }

  /// The session's current value of one `settings_pack` entry.
  String setting(String name) {
    _checkOpen();
    return _nativeGet(_bindings.sessionGet, _handle, name, () => error);
  }

  LtTorrent addMagnet(
    String magnet, {
    required String savePath,
    bool payloadPaused = false,
  }) {
    _checkOpen();
    // Pinned libtorrent parses x.pe without percent-decoding. Keep all
    // original query fields and supply decoded endpoints via Dart's URI API.
    final uri = Uri.parse(magnet);
    final peers = uri.queryParametersAll['x.pe'] ?? const <String>[];
    final nativeMagnet =
        '$magnet${peers.where((peer) => !peer.contains('&') && !peer.contains('=')).map((peer) => '&x.pe=$peer').join()}';
    final m = nativeMagnet.toNativeUtf8(allocator: _allocator);
    final p = savePath.toNativeUtf8(allocator: _allocator);
    try {
      final h = _bindings.addMagnet(
        _handle,
        m,
        utf8.encode(nativeMagnet).length,
        p,
        utf8.encode(savePath).length,
        payloadPaused ? 1 : 0,
      );
      return _torrent(h, savePath);
    } finally {
      _allocator.free(m);
      _allocator.free(p);
    }
  }

  LtTorrent addTorrent(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  }) {
    _checkOpen();
    final bytes = _allocator.allocate<Uint8>(data.length);
    bytes.asTypedList(data.length).setAll(0, data);
    final p = savePath.toNativeUtf8(allocator: _allocator);
    try {
      final h = _bindings.addTorrent(
        _handle,
        bytes,
        data.length,
        p,
        utf8.encode(savePath).length,
        payloadPaused ? 1 : 0,
      );
      return _torrent(h, savePath);
    } finally {
      _allocator.free(bytes);
      _allocator.free(p);
    }
  }

  LtTorrent loadResume(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  }) {
    _checkOpen();
    final bytes = _allocator.allocate<Uint8>(data.length);
    bytes.asTypedList(data.length).setAll(0, data);
    final p = savePath.toNativeUtf8(allocator: _allocator);
    try {
      final h = _bindings.loadResume(
        _handle,
        bytes,
        data.length,
        p,
        utf8.encode(savePath).length,
        payloadPaused ? 1 : 0,
      );
      return _torrent(h, savePath);
    } finally {
      _allocator.free(bytes);
      _allocator.free(p);
    }
  }

  LtTorrent _torrent(Pointer<Void> h, String savePath) {
    if (h == nullptr) throw LtNativeException('add torrent', error);
    return LtTorrent._(this, h, savePath);
  }

  void _drainAlerts() {
    if (_disposed) return;
    final count = _bindings.popAlerts(
      _handle,
      _alertRecords,
      _alertCap,
      _alertMessages,
      1024 * 1024,
    );
    if (count < 0) return;
    var messageOffset = 0;
    for (var i = 0; i < count; i++) {
      final record = _alertRecords[i];
      final message = record.messageLength <= 0
          ? ''
          : (_alertMessages.cast<Uint8>() + messageOffset)
                .cast<Utf8>()
                .toDartString(length: record.messageLength);
      messageOffset += record.messageLength;
      _alerts.add(
        LtAlertEvent(
          record.kind,
          piece: record.piece,
          peers: record.peers,
          errorCode: record.errorCode,
          message: message,
          torrent: record.torrent,
        ),
      );
    }
  }

  void _checkOpen() {
    if (_disposed) throw StateError('libtorrent session is closed');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer.cancel();
    // Retire native handles before closing the alert stream. Pending
    // LtTorrent.close() futures use the registry's post-destroy state to
    // resolve session-owned teardown instead of receiving a bare "No element"
    // from Stream.first.
    _bindings.destroy(_handle);
    _allocator.free(_alertRecords);
    _allocator.free(_alertMessages);
    await _alerts.close();
  }

  static DynamicLibrary openLibrary() {
    if (Platform.isMacOS) {
      try {
        return DynamicLibrary.open('libtransport_lt_shim.dylib');
      } catch (_) {
        for (final path in <String>[
          '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/libtransport_lt_shim.dylib',
          '${Directory.current.path}/macos/libs/libtransport_lt_shim.dylib',
          '${Directory.current.path}/packages/transport/macos/libs/libtransport_lt_shim.dylib',
          '${Directory.current.path}/../packages/transport/macos/libs/libtransport_lt_shim.dylib',
        ]) {
          if (File(path).existsSync()) return DynamicLibrary.open(path);
        }
        rethrow;
      }
    }
    if (Platform.isLinux || Platform.isAndroid) {
      return DynamicLibrary.open('libtransport_lt_shim.so');
    }
    if (Platform.isWindows) return DynamicLibrary.open('transport_lt_shim.dll');
    if (Platform.isIOS) return DynamicLibrary.process();
    throw UnsupportedError('libtorrent FFI is not bundled on this platform');
  }
}

final class LtAlertEvent {
  const LtAlertEvent(
    this.kind, {
    this.piece = -1,
    this.peers = -1,
    this.errorCode = 0,
    this.message = '',
    this.torrent = 0,
  });
  final int kind;
  final int piece;
  final int peers;
  final int errorCode;
  final String message;
  final int torrent;
}

final class LtTorrent {
  LtTorrent._(this.session, this.nativeHandle, this.savePath);
  final LtFfiSession session;
  final Pointer<Void> nativeHandle;
  final String savePath;
  bool _closed = false;
  bool get isClosed => _closed;
  LtBindings get _b => session._bindings;
  Allocator get _a => session._allocator;
  void _check() {
    if (_closed || session.isDisposed) {
      throw StateError('libtorrent torrent is closed');
    }
  }

  bool get metadataReady {
    _check();
    return _b.metadataReady(nativeHandle) != 0;
  }

  int get fileCount {
    _check();
    return _b.fileCount(nativeHandle);
  }

  int get pieceLength {
    _check();
    return _b.pieceLength(nativeHandle);
  }

  int get pieceCount {
    _check();
    return _b.pieceCount(nativeHandle);
  }

  String get infoHash {
    _check();
    final out = _a.allocate<Utf8>(41);
    try {
      final length = _b.infoHash(nativeHandle, out, 41);
      if (length < 0) throw LtNativeException('info hash', session.error);
      return out.toDartString(length: length);
    } finally {
      _a.free(out);
    }
  }

  bool pieceAvailable(int piece) {
    _check();
    return _b.pieceAvailable(nativeHandle, piece) != 0;
  }

  Uint8List pieceBitfield() {
    _check();
    final p = _a.allocate<Uint8>(pieceCount);
    try {
      final n = _b.copyBitfield(nativeHandle, p, pieceCount);
      if (n < 0) throw LtNativeException('piece bitfield', session.error);
      return Uint8List.fromList(p.asTypedList(n));
    } finally {
      _a.free(p);
    }
  }

  LtTorrentFile file(int index) {
    _check();
    final info = _a.allocate<LtFileInfo>(sizeOf<LtFileInfo>());
    final path = _a.allocate<Utf8>(4096);
    try {
      final n = _b.fileInfo(nativeHandle, index, info, path, 4096);
      if (n < 0) throw LtNativeException('file info', session.error);
      return LtTorrentFile(
        info.ref.offset,
        info.ref.size,
        path.cast<Utf8>().toDartString(length: n),
        info.ref.isPad != 0,
      );
    } finally {
      _a.free(info);
      _a.free(path);
    }
  }

  int read(int fileIndex, int offset, Uint8List output) {
    _check();
    final p = _a.allocate<Uint8>(output.length);
    try {
      final n = _b.read(nativeHandle, fileIndex, offset, p, output.length);
      if (n < 0) throw LtNativeException('read', session.error);
      output.setAll(0, p.asTypedList(n));
      return n;
    } finally {
      _a.free(p);
    }
  }

  void prioritizeFiles(List<int> priorities) {
    _check();
    final p = _a.allocate<Uint8>(priorities.length);
    try {
      p.asTypedList(priorities.length).setAll(0, priorities);
      if (_b.prioritizeFiles(nativeHandle, p, priorities.length) != 0) {
        throw LtNativeException('prioritize files', session.error);
      }
    } finally {
      _a.free(p);
    }
  }

  int filePriority(int index) {
    _check();
    final priority = _b.filePriority(nativeHandle, index);
    if (priority < 0) throw LtNativeException('file priority', session.error);
    return priority;
  }

  void setPiecePriority(int piece, int priority) {
    _check();
    if (_b.setPiecePriority(nativeHandle, piece, priority) != 0) {
      throw LtNativeException('piece priority', session.error);
    }
  }

  void initializeDownload(int fileIndex, int firstPiece, int endPiece) {
    _check();
    if (_b.initializeDownload(
          session._handle,
          nativeHandle,
          fileIndex,
          firstPiece,
          endPiece,
        ) !=
        0) {
      throw LtNativeException('initial download window', session.error);
    }
  }

  /// Forgets the downloaded [pieces] (ascending) and frees their disk blocks.
  /// The torrent is re-added in place; this handle stays valid.
  void evictPieces(List<int> pieces) {
    _check();
    if (pieces.isEmpty) return;
    final p = _a.allocate<Int32>(pieces.length * sizeOf<Int32>());
    try {
      p.asTypedList(pieces.length).setAll(0, pieces);
      if (_b.evictPieces(session._handle, nativeHandle, p, pieces.length) !=
          pieces.length) {
        throw LtNativeException('evict pieces', session.error);
      }
    } finally {
      _a.free(p);
    }
  }

  /// Applies per-torrent options: `download_limit`, `upload_limit`,
  /// `max_connections`, `pex` (0/1), `tracker` (one URL per call).
  void applyOptions(Map<String, String> options) {
    _check();
    if (options.isEmpty) return;
    final block = options.entries.map((e) => '${e.key}=${e.value}').join('\n');
    if (_nativeSet(_b.torrentSet, nativeHandle, block) < 0) {
      throw LtNativeException('apply torrent options', session.error);
    }
  }

  /// Adds tracker URLs to the torrent.
  void addTrackers(List<String> urls) {
    _check();
    for (final url in urls) {
      applyOptions({'tracker': url});
    }
  }

  /// The torrent's current value of one option (`tracker`: newline-joined).
  String option(String name) {
    _check();
    return _nativeGet(_b.torrentGet, nativeHandle, name, () => session.error);
  }

  void setPieceDeadline(int piece, int deadlineMs) {
    _check();
    if (_b.setPieceDeadline(nativeHandle, piece, deadlineMs) != 0) {
      throw LtNativeException('piece deadline', session.error);
    }
  }

  void clearPieceDeadlines() {
    _check();
    if (_b.clearPieceDeadlines(nativeHandle) != 0) {
      throw LtNativeException('clear deadlines', session.error);
    }
  }

  LtTorrentStatus get status {
    _check();
    final peers = _a.allocate<Int32>(sizeOf<Int32>());
    final state = _a.allocate<Int32>(sizeOf<Int32>());
    final done = _a.allocate<Int64>(sizeOf<Int64>());
    final total = _a.allocate<Int64>(sizeOf<Int64>());
    final rate = _a.allocate<Int32>(sizeOf<Int32>());
    try {
      if (_b.status(nativeHandle, peers, state, done, total, rate) != 0) {
        throw LtNativeException('status', session.error);
      }
      return LtTorrentStatus(
        peers.value,
        state.value,
        done.value,
        total.value,
        rate.value,
      );
    } finally {
      for (final p in [peers, state, done, total, rate]) {
        _a.free(p);
      }
    }
  }

  /// Live counters; read on demand (the stats popover), never polled here.
  LtTorrentStats get stats {
    _check();
    final out = calloc<LtStatsStruct>();
    try {
      if (_b.stats(nativeHandle, out) != 0) {
        throw LtNativeException('stats', session.error);
      }
      return LtTorrentStats(
        totalUpload: out.ref.totalUpload,
        distributedCopies: out.ref.distributedCopies,
        uploadRate: out.ref.uploadRate,
        seeds: out.ref.numSeeds,
        peers: out.ref.numPeers,
        swarmSeeds: out.ref.numComplete,
        swarmPeers: out.ref.numIncomplete,
        piecesHave: out.ref.numPieces,
      );
    } finally {
      calloc.free(out);
    }
  }

  Uint8List saveResume({int capacity = 1024 * 1024}) {
    _check();
    final p = _a.allocate<Uint8>(capacity);
    try {
      final n = _b.saveResume(nativeHandle, p, capacity);
      if (n < 0) {
        throw LtNativeException('save resume', 'resume data needs ${-n} bytes');
      }
      return Uint8List.fromList(p.asTypedList(n));
    } finally {
      _a.free(p);
    }
  }

  Future<void> close({Duration timeout = const Duration(seconds: 15)}) {
    if (_closeFuture != null) return _closeFuture!;
    _closed = true;
    if (session.isDisposed) return _closeFuture = Future<void>.value();
    _b.closeTorrent(nativeHandle);
    final deadline = DateTime.now().add(timeout);
    return _closeFuture = _awaitRemoval(deadline);
  }

  Future<void>? _closeFuture;

  Future<void> _awaitRemoval(DateTime deadline) async {
    while (true) {
      // The native side flips this only while handling the matching
      // torrent_removed_alert (or after the owning session has completed its
      // authoritative teardown). A Dart timer must not treat remove request
      // submission as completion.
      if (_b.closeComplete(nativeHandle) != 0) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw LtNativeException(
          'close torrent',
          'timed out waiting for torrent_removed_alert',
        );
      }
      try {
        await session.alerts.first.timeout(remaining);
      } on TimeoutException {
        throw LtNativeException(
          'close torrent',
          'timed out waiting for torrent_removed_alert',
        );
      } on StateError {
        // Session disposal closes the alert stream only after native session
        // teardown; re-check the registry before deciding this is an error.
        if (_b.closeComplete(nativeHandle) != 0) return;
        rethrow;
      }
    }
  }
}

final class LtTorrentStats {
  const LtTorrentStats({
    required this.totalUpload,
    required this.distributedCopies,
    required this.uploadRate,
    required this.seeds,
    required this.peers,
    required this.swarmSeeds,
    required this.swarmPeers,
    required this.piecesHave,
  });
  final int totalUpload;
  final double distributedCopies;
  final int uploadRate;
  final int seeds;
  final int peers;

  /// Tracker scrape totals; -1 when the tracker sent none.
  final int swarmSeeds;
  final int swarmPeers;
  final int piecesHave;
}

final class LtTorrentFile {
  const LtTorrentFile(this.offset, this.size, this.path, this.isPad);
  final int offset;
  final int size;
  final String path;
  final bool isPad;
}

final class LtTorrentStatus {
  const LtTorrentStatus(
    this.peers,
    this.state,
    this.downloaded,
    this.total,
    this.downloadRate,
  );
  final int peers;
  final int state;
  final int downloaded;
  final int total;
  final int downloadRate;
}

int _nativeSet(LtSet fn, Pointer<Void> handle, String block) {
  final p = block.toNativeUtf8();
  try {
    return fn(handle, p, utf8.encode(block).length);
  } finally {
    calloc.free(p);
  }
}

String _nativeGet(
  LtGet fn,
  Pointer<Void> handle,
  String name,
  String Function() error,
) {
  final n = name.toNativeUtf8();
  const capacity = 4096;
  final out = calloc.allocate<Utf8>(capacity);
  try {
    final length = fn(handle, n, utf8.encode(name).length, out, capacity);
    if (length < 0) throw LtNativeException('read $name', error());
    return out.toDartString(length: length.clamp(0, capacity - 1));
  } finally {
    calloc.free(n);
    calloc.free(out);
  }
}
