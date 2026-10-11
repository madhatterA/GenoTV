import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

final _caches = <Directory>[];

Directory _newCache() {
  final dir = Directory.systemTemp.createTempSync('cleanup-cache-');
  _caches.add(dir);
  return dir;
}

void main() {
  tearDownAll(() {
    for (final dir in _caches) {
      dir.deleteSync(recursive: true);
    }
  });

  test('native torrent inputs use UTF-8 byte lengths', () async {
    final libraryPath =
        '${Directory.current.path}/macos/libs/libtransport_lt_shim.dylib';
    final cache = await Directory.systemTemp.createTemp('transport-utf8-测试-');
    final session = TorrentSession(
      library: DynamicLibrary.open(libraryPath),
      savePath: cache.path,
    );
    try {
      await session.start();
      expect(
        () => session.addMagnet('not-a-magnet-é', savePath: cache.path),
        throwsA(isA<Exception>()),
      );
    } finally {
      await session.dispose();
      await cache.delete(recursive: true);
    }
  });

  test('successful open transfers ownership until handle disposal', () async {
    final torrentSource = _FakeSparseSource();
    final session = _FakeTorrentSession(
      torrent: _FakeTorrent(source: torrentSource),
    );
    final source = _source(session);

    final handle = await source.open(_magnet());
    expect(torrentSource.disposeCount, 0);
    expect(session.torrent.closeCount, 0);
    await handle.dispose();
    expect(torrentSource.disposeCount, 1);
    expect(session.torrent.closeCount, 1);
    await source.dispose();
    expect(torrentSource.disposeCount, 1);
    expect(session.torrent.closeCount, 1);
  });

  test('metadata failure closes the attached torrent once', () async {
    final session = _FakeTorrentSession(
      torrent: _FakeTorrent(metadataError: StateError('metadata failed')),
    );
    final source = _source(session);

    await expectLater(source.open(_magnet()), throwsA(isA<StateError>()));
    expect(session.torrent.closeCount, 1);
    await source.dispose();
    expect(session.torrent.closeCount, 1);
  });

  test('file selection failure closes the attached torrent once', () async {
    final session = _FakeTorrentSession(
      torrent: _FakeTorrent(files: const <TorrentFile>[]),
    );
    final source = _source(session);

    await expectLater(source.open(_magnet()), throwsA(isA<TransportFailure>()));
    expect(session.torrent.closeCount, 1);
    await source.dispose();
    expect(session.torrent.closeCount, 1);
  });

  test('source construction failure closes the torrent once', () async {
    final torrentSource = _FakeSparseSource();
    final session = _FakeTorrentSession(
      torrent: _FakeTorrent(
        source: torrentSource,
        sourceError: StateError('source failed'),
      ),
    );
    final source = _source(session);

    await expectLater(source.open(_magnet()), throwsA(isA<StateError>()));
    expect(session.torrent.closeCount, 1);
    await source.dispose();
    expect(torrentSource.disposeCount, 0);
    expect(session.torrent.closeCount, 1);
  });

  test('metadata that never arrives throws torrentNoMetadata after the real timeout (Phase 08)', () async {
    // torrentMetadataTimeout (stream_source_impl.dart) is a real 60s constant,
    // not injectable -- this test genuinely waits it out to prove the 5th
    // torrent TransportFailure code (torrentNoMetadata) is reachable through
    // its actual trigger path, not just constructible with the right shape.
    final torrentSource = _FakeSparseSource();
    final session = _FakeTorrentSession(
      torrent: _FakeTorrent(source: torrentSource, neverReady: true),
    );
    final source = _source(session);
    await expectLater(
      source.open(_magnet()),
      throwsA(
        isA<TransportFailure>().having(
          (f) => f.code,
          'code',
          'transport.torrent.no_metadata',
        ),
      ),
    );
    await source.dispose();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('range registration failure disposes the torrent and server', () async {
    final torrentSource = _FakeSparseSource();
    final session = _FakeTorrentSession(
      torrent: _FakeTorrent(source: torrentSource),
    );
    RangeServer? server;
    final source = _source(
      session,
      rangeServerFactory: (logger) async {
        server = await RangeServer.start(logger: logger);
        await server!.close();
        return server!;
      },
    );

    await expectLater(source.open(_magnet()), throwsA(isA<StateError>()));
    expect(torrentSource.disposeCount, 1);
    expect(session.torrent.closeCount, 1);
    expect(server, isNotNull);
    await source.dispose();
    expect(torrentSource.disposeCount, 1);
    expect(session.torrent.closeCount, 1);
  });
}

StreamSourceImpl _source(
  _FakeTorrentSession session, {
  RangeServerFactory? rangeServerFactory,
}) => StreamSourceImpl(
  logger: MemoryLogger(),
  cacheDir: _newCache(),
  torrentSessionFactory: (_) async => session,
  rangeServerFactory: rangeServerFactory,
);

SourceSpec _magnet() => SourceSpec(
  kind: SourceKind.torrentMagnet,
  uri: Uri.parse('magnet:?xt=urn:btih:cleanup-test'),
);

final class _FakeTorrentSession implements TorrentSessionAdapter {
  _FakeTorrentSession({required this.torrent});
  final _FakeTorrent torrent;
  int disposeCount = 0;

  @override
  Future<void> start() async {}

  @override
  Future<TorrentHandleAdapter> addMagnet(
    String magnet, {
    required String savePath,
    bool payloadPaused = false,
  }) async => torrent;

  @override
  Future<TorrentHandleAdapter> addTorrent(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  }) async => torrent;

  @override
  Future<TorrentHandleAdapter> loadResume(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  }) async => torrent;

  @override
  Future<void> dispose() async => disposeCount++;
}

final class _FakeTorrent implements TorrentHandleAdapter {
  _FakeTorrent({
    this.files = const <TorrentFile>[
      TorrentFile(path: 'fixture.mp4', offset: 0, length: 4096),
    ],
    this.source,
    this.metadataError,
    this.sourceError,
    this.neverReady = false,
  });
  final bool neverReady;
  @override
  final List<TorrentFile> files;
  final TorrentSourceAdapter? source;
  final Object? metadataError;
  final Object? sourceError;
  int closeCount = 0;

  @override
  bool get metadataReady {
    final error = metadataError;
    if (error != null) throw error;
    return !neverReady;
  }

  @override
  int get pieceLength => 1024;

  @override
  TorrentSourceAdapter createSource({
    required int fileIndex,
    required PieceMapper mapper,
  }) {
    final error = sourceError;
    if (error != null) throw error;
    return source ?? _FakeSparseSource();
  }

  @override
  Uint8List saveResume() => Uint8List(0);

  @override
  void setPieceDeadline(int piece, int deadlineMs) {}

  @override
  void setPiecePriority(int piece, int priority) {}

  @override
  void prioritizeFiles(List<int> priorities) {}

  @override
  void clearPieceDeadlines() {}

  @override
  Future<void> close() async => closeCount++;
}

final class _FakeSparseSource implements TorrentSourceAdapter {
  int disposeCount = 0;

  @override
  int? get totalBytes => 4096;

  @override
  RangeSet get available => RangeSet.empty();

  @override
  SourceStatus get currentStatus => SourceStatus(
    state: SourceState.buffering,
    available: available,
    totalBytes: totalBytes,
    bytesPerSecond: 0,
    peersOrConnections: 0,
  );

  @override
  Future<void> seekHint(int byteOffset) async {}

  @override
  Future<void> waitFor(ByteRange range) async {}

  @override
  Stream<List<int>> read(ByteRange range) async* {}

  @override
  void releaseDemand(Object token) {}

  @override
  Future<void> dispose() async => disposeCount++;
}
