import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'cache/cache_budget.dart';
import 'cache/fs_native.dart';
import 'http/aria2_backend.dart';
import 'direct/direct_url_handle.dart';
import 'http/http_backend_factory.dart';
import 'http/http_sparse_source.dart';
import 'http/range_support_probe.dart';
import 'local/local_file_handle.dart';
import 'server/range_server.dart';
import 'server/sparse_source.dart';
import 'torrent/media_file_selector.dart';
import 'torrent/lt_ffi_session.dart';
import 'torrent/piece_mapper.dart';
import 'torrent/torrent_metadata.dart';
import 'torrent/torrent_options.dart';
import 'torrent/torrent_session.dart';
import 'torrent/torrent_sparse_source.dart';

/// `TRANSPORT_LT_ALERT_TRACKER_ERROR` in lt_shim.h.
const int _ltAlertTrackerError = 5;

const Duration torrentMetadataTimeout = Duration(seconds: 60);
const Duration _seedDuration = Duration(minutes: 30);
const Duration _seedRatioCheck = Duration(seconds: 10);

typedef RangeServerFactory = Future<RangeServer> Function(AppLogger logger);
typedef TorrentSessionAdapterFactory = Future<TorrentSessionAdapter> Function(
  String savePath,
);

abstract interface class TorrentSessionAdapter {
  Future<void> start();
  Future<TorrentHandleAdapter> addMagnet(
    String magnet, {
    required String savePath,
    bool payloadPaused = false,
  });
  Future<TorrentHandleAdapter> addTorrent(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  });
  Future<TorrentHandleAdapter> loadResume(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  });
  Future<void> dispose();
}

abstract interface class TorrentHandleAdapter {
  bool get metadataReady;
  List<TorrentFile> get files;
  int get pieceLength;
  TorrentSourceAdapter createSource({
    required int fileIndex,
    required PieceMapper mapper,
  });
  Uint8List saveResume();
  void setPiecePriority(int piece, int priority);
  void setPieceDeadline(int piece, int deadlineMs);
  void prioritizeFiles(List<int> priorities);
  void clearPieceDeadlines();
  Future<void> close();
}

abstract interface class TorrentSourceAdapter implements SparseSource {
  Future<void> seekHint(int byteOffset);
  SourceStatus get currentStatus;
  Future<void> dispose();
}

int _fnv1a(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return hash.toUnsigned(64);
}

class StreamSourceImpl implements StreamSource {
  StreamSourceImpl({
    required AppLogger logger,
    required this.cacheDir,
    this._state,
    TorrentSessionAdapterFactory? torrentSessionFactory,
    RangeServerFactory? rangeServerFactory,
  }) : _logger = logger.scoped('transport'),
       _torrentSessionFactory =
           torrentSessionFactory ?? _nativeTorrentSessionFactory,
       _rangeServerFactory =
           rangeServerFactory ??
           ((logger) => RangeServer.start(logger: logger)) {
    _startupExpiry = _budgetObject().expire().catchError((
      Object error,
      StackTrace stack,
    ) {
      _logger.error('Cache expiry failed', error: error, stack: stack);
    });
  }

  final AppLogger _logger;
  final Directory cacheDir;
  final TransportStateRepository? _state;
  final TorrentSessionAdapterFactory _torrentSessionFactory;
  final RangeServerFactory _rangeServerFactory;
  final Map<SourceSpec, Future<_SharedOpen>> _opens =
      <SourceSpec, Future<_SharedOpen>>{};
  // Cache files of the streams that are open right now; clearCache keeps them.
  final Map<SourceSpec, String> _openFiles = <SourceSpec, String>{};
  CacheBudget? _budget;
  late final Future<void> _startupExpiry;
  RangeServer? _server;
  Aria2Backend? _httpBackend;
  final Map<String, Future<void> Function()> _seeding = {};
  TransportOptions? _latestOptions;
  TorrentSessionAdapter? _torrentSession;
  bool _disposed = false;

  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async {
    if (_disposed) throw StateError('stream source is disposed');
    final existing = _opens[spec];
    if (existing != null) return (await existing).acquire();
    final opening = _open(spec, options);
    _opens[spec] = opening;
    try {
      return (await opening).acquire();
    } catch (error) {
      if (identical(_opens[spec], opening)) unawaited(_opens.remove(spec));
      if (spec.kind == SourceKind.httpUrl && error is TransportFailure) {
        final failed = _SharedOpen(
          _FailedHandle(spec.uri, error),
          onClose: () => _remove(spec),
        );
        _opens[spec] = Future<_SharedOpen>.value(failed);
        return failed.acquire();
      }
      rethrow;
    }
  }

  Future<_SharedOpen> _open(SourceSpec spec, TransportOptions options) async {
    if (spec.kind == SourceKind.localFile) {
      return _SharedOpen(
        await LocalFileHandle.open(spec.uri),
        onClose: () => _remove(spec),
      );
    }
    if (spec.kind == SourceKind.hlsUrl) {
      return _SharedOpen(
        DirectUrlHandle(spec.uri),
        onClose: () => _remove(spec),
      );
    }
    if (spec.kind != SourceKind.httpUrl) return _openTorrent(spec, options);
    await cacheDir.create(recursive: true);
    // First, so expiry and the limit apply before this item's own entry is
    // looked up.
    final budget = await _cacheBudget(options);
    final key = deriveSourceKey(spec);
    DownloadRecord? previous;
    try {
      previous = await _state?.get(key);
    } catch (error, stack) {
      throw TransportFailure.engineUnavailable(
        cause: 'transport state repository failed: $error',
        stack: stack,
      );
    }
    // A complete copy on disk is served without asking the origin.
    final probe = await _completeOnDisk(previous)
        ? RangeProbeResult(
            uri: spec.uri,
            totalBytes: previous!.totalBytes,
            validator: previous.validator,
            supported: true,
          )
        : await RangeSupportProbe(options: options).probe(spec);
    if (previous?.validator != null &&
        probe.validator != null &&
        previous!.validator != probe.validator) {
      throw TransportFailure.httpValidatorChanged(
        cause: 'cached validator differs from upstream',
      );
    }
    // The key embeds the full (signed, often >255 char) URL, so it cannot be a
    // file name: use a 64-bit FNV-1a hash of it. A stored path with an over-long name (written by a
    // build that used the raw key) is ignored.
    final stored = previous?.filePath;
    final path = stored != null && stored.split('/').last.length <= 200
        ? stored
        : '${cacheDir.path}/${_fnv1a(key).toRadixString(16)}.partial';
    final backend = _httpBackend ??= createHttpBackend(logger: _logger);
    if (await File('$path.evicted').exists()) {
      await _discardPartial(spec, path);
    }
    _openFiles[spec] = path;
    final total = probe.totalBytes;
    final initialAhead = total != null && total + budget.openUsed <= budget.limit
        ? total
        : (budget.limit -
                  budget.backWindow -
                  budget.batchFor(16 * 1024 * 1024) -
                  budget.openUsed)
              .clamp(0, budget.limit);
    final jobId = await backend.addDownload(
      spec,
      path,
      options: options,
      totalBytes: total,
      initialWindow: total != null && total > 0 && initialAhead > 0
          ? ByteRange(0, (initialAhead - 1).clamp(0, total - 1))
          : null,
    );
    try {
      await _save(
        spec,
        path: path,
        total: probe.totalBytes,
        validator: probe.validator,
      );
    } catch (_) {
      _openFiles.remove(spec);
      await backend.remove(jobId);
      rethrow;
    }
    final initial = await backend.status(jobId);
    final initialAvailable = initial.available;
    final source = HttpSparseSource(
      file: File(path),
      totalBytes: probe.totalBytes,
      available: initialAvailable,
      backend: backend,
      jobId: jobId,
    );
    source.enableCacheLimit(budget: budget, fs: budget.fs, logger: _logger);
    source.startMonitoring();
    final server = _server ??= await RangeServer.start(logger: _logger);
    final playbackUri = server.register(
      source,
      filename: spec.uri.pathSegments.isEmpty
          ? 'stream'
          : spec.uri.pathSegments.last,
    );
    return _SharedOpen(
      _RemoteHandle(
        playbackUri,
        source,
        onSeek: source.seekHint,
        onDispose: () async {
          server.unregister(playbackUri);
          await source.dispose();
          await backend.remove(jobId);
          await _save(
            spec,
            path: path,
            total: source.totalBytes,
            validator: probe.validator,
          );
        },
      ),
      onClose: () => _remove(spec),
    );
  }

  Future<_SharedOpen> _openTorrent(
    SourceSpec spec,
    TransportOptions options,
  ) async {
    await cacheDir.create(recursive: true);
    // Before the torrent exists, so limiting starts the moment its metadata
    // arrives instead of after a burst of download.
    final budget = await _cacheBudget(options);
    final session = _torrentSession ??= await _startTorrentSession();
    final key = deriveSourceKey(spec);
    _latestOptions = options;
    await _stopSeeding(key);
    if (session is _NativeTorrentSessionAdapter) {
      try {
        session.apply(options);
      } catch (error, stack) {
        throw TransportFailure.engineUnavailable(cause: error, stack: stack);
      }
    }
    Uint8List? resume;
    try {
      resume = await _state?.torrentResumeData(key);
      if (resume != null && resume.isEmpty) resume = null;
    } catch (error, stack) {
      throw TransportFailure.engineUnavailable(
        cause: 'torrent resume repository failed: $error',
        stack: stack,
      );
    }
    late final TorrentHandleAdapter torrent;
    try {
      torrent = resume != null
          ? await session.loadResume(
              resume,
              savePath: cacheDir.path,
              payloadPaused: true,
            )
          : spec.kind == SourceKind.torrentMagnet
          ? await session.addMagnet(
              spec.uri.toString(),
              savePath: cacheDir.path,
              payloadPaused: true,
            )
          : await session.addTorrent(
              await File(spec.uri.toFilePath()).readAsBytes(),
              savePath: cacheDir.path,
              payloadPaused: true,
            );
    } catch (error, stack) {
      throw TransportFailure.torrentNoMetadata(cause: error, stack: stack);
    }
    if (torrent is _NativeTorrentHandleAdapter) {
      try {
        torrent.configure(options);
      } catch (error, stack) {
        await torrent.close();
        throw TransportFailure.engineUnavailable(cause: error, stack: stack);
      }
    }
    TorrentSourceAdapter? source;
    RangeServer? server;
    Uri? playbackUri;
    var serverCreated = false;
    var transferred = false;
    try {
      final deadline = DateTime.now().add(torrentMetadataTimeout);
      // Tracker failures during the wait explain a missing-metadata failure
      // (e.g. UDP trackers blackholed by a VPN/proxy), so keep them.
      var trackerFailures = 0;
      String? lastTrackerFailure;
      final trackerWatch = session is _NativeTorrentSessionAdapter
          ? session._session.alerts
                .where((a) => a.kind == _ltAlertTrackerError)
                .listen((a) {
                  trackerFailures++;
                  lastTrackerFailure = a.message;
                })
          : null;
      try {
        while (!torrent.metadataReady && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } finally {
        await trackerWatch?.cancel();
      }
      if (!torrent.metadataReady) {
        throw TransportFailure.torrentNoMetadata(
          cause: trackerFailures == 0
              ? 'metadata did not arrive'
              : 'metadata did not arrive; $trackerFailures tracker announce '
                    'failures, last: $lastTrackerFailure',
        );
      }
      final files = torrent.files;
      final selected = const MediaFileSelector().select(
        TorrentMetadata(files: files, pieceLength: torrent.pieceLength),
        fileHint: spec.fileHint,
        seasonNumber: spec.seasonNumber,
        episodeNumber: spec.episodeNumber,
        episodeTitle: spec.episodeTitle,
      );
      final fileIndex = files.indexOf(selected);
      final filePath = '${cacheDir.path}/${selected.path}';
      await _save(
        spec,
        path: filePath,
        total: selected.length,
        validator: null,
      );
      _openFiles[spec] = filePath;
      final mapper = PieceMapper(
        pieceLength: torrent.pieceLength,
        fileOffsetInTorrent: selected.offset,
        fileLength: selected.length,
      );
      source = torrent.createSource(fileIndex: fileIndex, mapper: mapper);
      if (source is _NativeTorrentSourceAdapter) {
        source.enableCacheLimit(
          budget: budget,
          logger: _logger,
          filePath: filePath,
        );
      } else {
        torrent.prioritizeFiles(<int>[
          for (var i = 0; i < files.length; i++) i == fileIndex ? 7 : 0,
        ]);
      }
      if (_server == null) {
        server = await _rangeServerFactory(_logger);
        _server = server;
        serverCreated = true;
      } else {
        server = _server;
      }
      final registeredUri = server!.register(source, filename: selected.path);
      playbackUri = registeredUri;
      final handle = _SharedOpen(
        _RemoteHandle(
          registeredUri,
          source,
          onSeek: source.seekHint,
          statusProvider: () => source!.currentStatus,
          onDispose: () async {
            _logger.info('torrent stream released: playback session ended');
            server!.unregister(registeredUri);
            try {
              final state = _state;
              if (state != null) {
                await state.putTorrentResumeData(key, torrent.saveResume());
                await _save(
                  spec,
                  path: filePath,
                  total: selected.length,
                  validator: null,
                );
              }
            } finally {
              await source!.dispose();
              final seeding = (_latestOptions ?? options).seeding;
              if (torrent is _NativeTorrentHandleAdapter &&
                  seeding != SeedingMode.off) {
                _keepSeeding(key, torrent, seeding);
              } else {
                await torrent.close();
              }
            }
          },
        ),
        onClose: () => _remove(spec),
      );
      transferred = true;
      return handle;
    } finally {
      if (!transferred) {
        try {
          if (source != null) await source.dispose();
        } finally {
          try {
            await torrent.close();
          } finally {
            if (playbackUri != null) server?.unregister(playbackUri);
            if (serverCreated && server != null) {
              if (identical(_server, server)) _server = null;
              await server.close();
            }
          }
        }
      }
    }
  }

  /// After a stream closes, a torrent may keep seeding (ratio 1.0, or 30
  /// minutes) before it leaves the session.
  void _keepSeeding(
    String key,
    _NativeTorrentHandleAdapter torrent,
    SeedingMode mode,
  ) {
    late final Timer timer;
    Future<void> stop() async {
      timer.cancel();
      _seeding.remove(key);
      _logger.info('seeding torrent closed');
      try {
        await torrent.close();
      } catch (error, stack) {
        _logger.warn(
          'Seeding torrent close failed',
          error: error,
          stack: stack,
        );
      }
    }

    void check() {
      try {
        if (torrent.seededRatioReached) unawaited(stop());
      } catch (_) {
        unawaited(stop());
      }
    }

    timer = mode == SeedingMode.duration
        ? Timer(_seedDuration, () => unawaited(stop()))
        : Timer.periodic(_seedRatioCheck, (_) => check());
    _seeding[key] = stop;
  }

  /// Applies the live settings (rate caps, connection limit, seeding mode) to
  /// the running session and open streams; the rest wait for the next open.
  Future<void> applyGlobalOptions(TransportOptions options) async {
    if (_disposed) return;
    _latestOptions = options;
    final session = _torrentSession;
    if (session is _NativeTorrentSessionAdapter) session.apply(options);
    await _httpBackend?.updateOptions(options);
  }

  /// The running libtorrent session, for reading its settings back.
  LtFfiSession? get nativeTorrentSession {
    final session = _torrentSession;
    return session is _NativeTorrentSessionAdapter
        ? session._session.native
        : null;
  }

  /// Torrents currently kept seeding after their stream closed.
  int get seedingCount => _seeding.length;

  Future<void> _stopSeeding(String key) async => _seeding[key]?.call();

  Future<TorrentSessionAdapter> _startTorrentSession() async {
    try {
      final session = await _torrentSessionFactory(cacheDir.path);
      await session.start();
      return session;
    } catch (error, stack) {
      throw TransportFailure.engineUnavailable(cause: error, stack: stack);
    }
  }

  Future<void> _save(
    SourceSpec spec, {
    required String path,
    required int? total,
    required String? validator,
  }) async {
    final state = _state;
    if (state == null) return;
    final key = deriveSourceKey(spec);
    try {
      await state.upsert(
        DownloadRecord(
          sourceKey: key,
          kind: spec.kind,
          filePath: path,
          totalBytes: total ?? spec.expectedBytes,
          validator: validator,
          lastUsedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (error, stack) {
      _logger.error('Transport persistence failed', error: error, stack: stack);
      throw TransportFailure.engineUnavailable(
        cause: 'transport state repository failed: $error',
        stack: stack,
      );
    }
  }

  void _remove(SourceSpec spec) {
    if (_opens[spec] is Future<_SharedOpen>) _opens.remove(spec);
    _openFiles.remove(spec);
  }

  @override
  Future<int> clearCache() async {
    if (_disposed) throw StateError('stream source is disposed');
    for (final stop in List.of(_seeding.values)) {
      await stop();
    }
    return _budgetObject().clear();
  }

  /// The record's file holds every byte of the item (aria2 coverage file).
  Future<bool> _completeOnDisk(DownloadRecord? record) async {
    final path = record?.filePath;
    final total = record?.totalBytes;
    if (path == null || total == null || total <= 0) return false;
    final file = File(path);
    final control = File('$path.aria2');
    if (!await file.exists() ||
        await file.length() < total ||
        !await control.exists() ||
        await File('$path.evicted').exists()) {
      return false;
    }
    try {
      final coverage =
          jsonDecode(await control.readAsString()) as Map<String, dynamic>;
      var have = RangeSet.empty();
      for (final pair in coverage['ranges'] as List) {
        have = have.add(ByteRange(pair[0] as int, pair[1] as int));
      }
      return coverage['total'] == total &&
          have.containsRange(ByteRange(0, total - 1));
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  Future<void> _discardPartial(SourceSpec spec, String path) async {
    for (final name in [path, '$path.aria2', '$path.evicted']) {
      final file = File(name);
      if (await file.exists()) await file.delete();
    }
    await _state?.delete(deriveSourceKey(spec));
  }

  CacheBudget _budgetObject() {
    try {
      return _budget ??= CacheBudget(
        dir: cacheDir,
        fs: FsNative(),
        logger: _logger,
        state: _state,
        openNames: _openNames,
        openKeys: () => {for (final s in _opens.keys) deriveSourceKey(s)},
      );
    } catch (error, stack) {
      throw TransportFailure.engineUnavailable(cause: error, stack: stack);
    }
  }

  /// Top-level cache entries (and aria2 control files) of the open streams.
  Set<String> _openNames() {
    final names = <String>{};
    for (final path in {
      ..._openFiles.values,
      ...?_httpBackend?.activeWindowPaths,
    }) {
      if (!path.startsWith('${cacheDir.path}/')) continue;
      final top = path.substring(cacheDir.path.length + 1).split('/').first;
      names
        ..add(top)
        ..add('$top.aria2')
        ..add('$top.evicted');
    }
    return names;
  }

  /// The cache budget with the limit of the stream being opened. Closed
  /// streams are trimmed first so the new one starts inside the limit.
  Future<CacheBudget> _cacheBudget(TransportOptions options) async {
    final budget = _budgetObject();
    await cacheDir.create(recursive: true);
    await _startupExpiry;
    await budget.expire();
    budget.limit = resolveCacheLimit(
      options,
      budget.fs.freeBytes(cacheDir.path),
    );
    await budget.makeRoom(force: true);
    return budget;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final stop in List.of(_seeding.values)) {
      await stop();
    }
    final opens = List<Future<_SharedOpen>>.of(_opens.values);
    _opens.clear();
    for (final opening in opens) {
      try {
        await (await opening).dispose();
      } catch (error, stack) {
        _logger.warn(
          'Transport handle close failed',
          error: error,
          stack: stack,
        );
      }
    }
    await _server?.close();
    _server = null;
    await _httpBackend?.stop();
    _httpBackend = null;
    await _torrentSession?.dispose();
    _torrentSession = null;
  }
}

Future<TorrentSessionAdapter> _nativeTorrentSessionFactory(
  String savePath,
) async => _NativeTorrentSessionAdapter(TorrentSession(savePath: savePath));

final class _NativeTorrentSessionAdapter implements TorrentSessionAdapter {
  _NativeTorrentSessionAdapter(this._session);
  final TorrentSession _session;

  @override
  Future<void> start() => _session.start();

  @override
  Future<TorrentHandleAdapter> addMagnet(
    String magnet, {
    required String savePath,
    bool payloadPaused = false,
  }) async => _NativeTorrentHandleAdapter(
    _session.addMagnet(
      magnet,
      savePath: savePath,
      payloadPaused: payloadPaused,
    ),
  );

  @override
  Future<TorrentHandleAdapter> addTorrent(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  }) async => _NativeTorrentHandleAdapter(
    _session.addTorrent(data, savePath: savePath, payloadPaused: payloadPaused),
  );

  @override
  Future<TorrentHandleAdapter> loadResume(
    Uint8List data, {
    required String savePath,
    bool payloadPaused = false,
  }) async => _NativeTorrentHandleAdapter(
    _session.loadResume(data, savePath: savePath, payloadPaused: payloadPaused),
  );

  @override
  Future<void> dispose() => _session.dispose();

  late final String _defaultUserAgent = _session.native.setting('user_agent');

  /// Session-wide settings; applied on every open so a changed setting also
  /// reaches torrents that are already running.
  void apply(TransportOptions o) =>
      applyTorrentSessionOptions(_session.native, o, _defaultUserAgent);
}

final class _NativeTorrentHandleAdapter implements TorrentHandleAdapter {
  _NativeTorrentHandleAdapter(this._torrent);
  final LtTorrent _torrent;

  @override
  bool get metadataReady => _torrent.metadataReady;

  /// Per-torrent limits, peer cap, PEX and the extra trackers.
  void configure(TransportOptions o) => configureTorrent(_torrent, o);

  bool get seededRatioReached =>
      int.parse(_torrent.option('total_upload')) >=
      int.parse(_torrent.option('total_download'));

  @override
  List<TorrentFile> get files => [
    for (var i = 0; i < _torrent.fileCount; i++)
      () {
        final file = _torrent.file(i);
        return TorrentFile(
          path: file.path,
          offset: file.offset,
          length: file.size,
        );
      }(),
  ];

  @override
  int get pieceLength => _torrent.pieceLength;

  @override
  TorrentSourceAdapter createSource({
    required int fileIndex,
    required PieceMapper mapper,
  }) => _NativeTorrentSourceAdapter(
    TorrentSparseSource.fromNative(
      torrent: _torrent,
      fileIndex: fileIndex,
      mapper: mapper,
    ),
  );

  @override
  Uint8List saveResume() => _torrent.saveResume();

  @override
  void setPiecePriority(int piece, int priority) =>
      _torrent.setPiecePriority(piece, priority);

  @override
  void setPieceDeadline(int piece, int deadlineMs) =>
      _torrent.setPieceDeadline(piece, deadlineMs);

  @override
  void prioritizeFiles(List<int> priorities) =>
      _torrent.prioritizeFiles(priorities);

  @override
  void clearPieceDeadlines() => _torrent.clearPieceDeadlines();

  @override
  Future<void> close() async {
    await _torrent.close();
  }
}

final class _NativeTorrentSourceAdapter
    implements TorrentSourceAdapter, TransportStatsProvider {
  _NativeTorrentSourceAdapter(this._source);
  final TorrentSparseSource _source;

  @override
  int get totalBytes => _source.totalBytes;

  void enableCacheLimit({
    required CacheBudget budget,
    required AppLogger logger,
    required String filePath,
  }) => _source.enableCacheLimit(
    budget: budget,
    logger: logger,
    filePath: filePath,
  );

  @override
  RangeSet get available => _source.available;

  @override
  SourceStatus get currentStatus => _source.currentStatus;

  @override
  Future<TransportStats> readStats() => _source.readStats();

  @override
  Future<void> seekHint(int byteOffset) => _source.seekHint(byteOffset);

  @override
  Future<void> waitFor(ByteRange range) => _source.waitFor(range);

  @override
  Stream<List<int>> read(ByteRange range) => _source.read(range);

  @override
  void releaseDemand(Object token) => _source.releaseDemand(token);

  @override
  Future<void> dispose() => _source.dispose();
}

class _SharedOpen {
  _SharedOpen(this._inner, {required this.onClose});
  final StreamHandle _inner;
  final void Function() onClose;
  int _refs = 0;
  bool _closed = false;

  StreamHandle acquire() {
    if (_closed) throw StateError('stream open is closed');
    _refs++;
    return _RefHandle(this, _inner);
  }

  Future<void> release() async {
    if (_closed || --_refs > 0) return;
    _closed = true;
    try {
      await _inner.dispose();
    } finally {
      onClose();
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    onClose();
    await _inner.dispose();
  }
}

class _RefHandle implements StreamHandle, TransportStatsProvider {
  _RefHandle(this._owner, this._inner);
  final _SharedOpen _owner;
  final StreamHandle _inner;
  bool _disposed = false;
  @override
  Uri get playbackUri {
    _check();
    return _inner.playbackUri;
  }

  @override
  int? get totalBytes {
    _check();
    return _inner.totalBytes;
  }

  @override
  Stream<SourceStatus> get status =>
      _disposed ? const Stream.empty() : _inner.status;
  @override
  Future<void> seekHint(int byteOffset) {
    _check();
    return _inner.seekHint(byteOffset);
  }

  @override
  Future<TransportStats> readStats() {
    _check();
    final inner = _inner;
    if (inner is! TransportStatsProvider) {
      throw UnsupportedError('this stream has no transfer statistics');
    }
    return (inner as TransportStatsProvider).readStats();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _owner.release();
  }

  void _check() {
    if (_disposed) throw StateError('stream handle is disposed');
  }
}

class _FailedHandle implements StreamHandle {
  _FailedHandle(this._uri, this._failure);
  final Uri _uri;
  final TransportFailure _failure;
  bool _disposed = false;
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
  Stream<SourceStatus> get status => _disposed
      ? const Stream<SourceStatus>.empty()
      : Stream<SourceStatus>.value(
          SourceStatus(
            state: SourceState.failed,
            available: RangeSet.empty(),
            totalBytes: null,
            bytesPerSecond: 0,
            peersOrConnections: 0,
            failure: _failure,
          ),
        );

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

class _RemoteHandle implements StreamHandle, TransportStatsProvider {
  _RemoteHandle(
    this._uri,
    this._source, {
    required this.onSeek,
    required this.onDispose,
    this.statusProvider,
  }) {
    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final next = _currentStatus;
      if (_lastStatus == null || !_sameStatus(_lastStatus!, next)) {
        _lastStatus = next;
        if (!_events.isClosed) _events.add(next);
      }
    });
  }
  final Uri _uri;
  final SparseSource _source;
  final Future<void> Function(int) onSeek;
  final Future<void> Function() onDispose;
  final SourceStatus Function()? statusProvider;
  final StreamController<SourceStatus> _events =
      StreamController<SourceStatus>.broadcast();
  SourceStatus? _lastStatus;
  Timer? _statusTimer;
  bool _disposed = false;

  @override
  Uri get playbackUri {
    _check();
    return _uri;
  }

  @override
  int? get totalBytes {
    _check();
    return _source.totalBytes;
  }

  @override
  Stream<SourceStatus> get status {
    _check();
    return Stream<SourceStatus>.multi((multi) {
      multi.add(_lastStatus ??= _currentStatus);
      final sub = _events.stream.listen(multi.add);
      multi.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  SourceStatus get _currentStatus {
    final provided = statusProvider;
    if (provided != null) return provided();
    final failure = _failure;
    final typedFailure = failure is TransportFailure
        ? failure
        : failure == null
        ? null
        : TransportFailure.engineUnavailable(cause: failure);
    return SourceStatus(
      state: typedFailure != null
          ? SourceState.failed
          : (_source.available.ranges.isEmpty
                ? SourceState.buffering
                : SourceState.ready),
      available: _source.available,
      totalBytes: _source.totalBytes,
      bytesPerSecond: 0,
      peersOrConnections: 0,
      failure: typedFailure,
    );
  }

  Object? get _failure => _source is HttpSparseSource ? _source.failure : null;

  bool _sameStatus(SourceStatus a, SourceStatus b) {
    if (a.state != b.state ||
        a.totalBytes != b.totalBytes ||
        a.bytesPerSecond != b.bytesPerSecond ||
        a.peersOrConnections != b.peersOrConnections ||
        a.failure?.code != b.failure?.code) {
      return false;
    }
    final left = a.available.ranges.toList();
    final right = b.available.ranges.toList();
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].start != right[i].start ||
          left[i].endInclusive != right[i].endInclusive) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> seekHint(int byteOffset) {
    _check();
    return onSeek(byteOffset);
  }

  @override
  Future<TransportStats> readStats() {
    _check();
    final source = _source;
    if (source is! TransportStatsProvider) {
      throw UnsupportedError('this source has no transfer statistics');
    }
    return (source as TransportStatsProvider).readStats();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _statusTimer?.cancel();
    await onDispose();
    await _events.close();
  }

  void _check() {
    if (_disposed) throw StateError('stream handle is disposed');
  }
}
