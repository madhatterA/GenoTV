import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../cache/cache_budget.dart';
import '../cache/cache_governor.dart';
import '../server/sparse_source.dart';
import 'alert_router.dart';
import 'lt_ffi_session.dart';
import 'piece_mapper.dart';
import 'piece_scheduler.dart';

class TorrentSparseSource implements SparseSource, TransportStatsProvider {
  TorrentSparseSource({
    required this.file,
    required this.mapper,
    this.fileIndex = 0,
    Iterable<int> availablePieces = const <int>[],
  }) : _nativeTorrent = null,
       _pieces = availablePieces.toSet();
  TorrentSparseSource.fromNative({
    required LtTorrent torrent,
    required this.fileIndex,
    required this.mapper,
  }) : file = File(''),
       _nativeTorrent = torrent,
       _pieces = <int>{} {
    if (torrent.metadataReady) {
      _router.route(const TorrentAlert(TorrentAlertKind.metadataReceived));
    }
    _alertSubscription = torrent.session.alerts.listen(_onAlert);
  }
  final File file;
  final PieceMapper mapper;
  final int fileIndex;
  final LtTorrent? _nativeTorrent;
  final Set<int> _pieces;
  final Set<int> _demandedPieces = <int>{};
  final PieceScheduler _scheduler = PieceScheduler();
  final AlertRouter _router = AlertRouter();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  StreamSubscription<LtAlertEvent>? _alertSubscription;
  bool _disposed = false;
  CacheGovernor? _governor;
  // Download-ahead room the cache limit leaves; null without a limit.
  int? _aheadBytes;
  // Ranges whose disk blocks were freed and not written since.
  // First piece not downloaded because it lies beyond the ahead window.
  int _dormantStart = 0;
  // Pieces forgotten by eviction (priority 0 until wanted again).
  final Set<int> _evictedPieces = <int>{};
  // Every byte this torrent has had since it opened, evicted or not: the
  // cache limit frees bytes behind the play head, but the download progressed.
  RangeSet _everDownloaded = RangeSet.empty();

  void _noteDownloaded() {
    for (final range in available.ranges) {
      _everDownloaded = _everDownloaded.add(range);
    }
  }
  @override
  int get totalBytes => mapper.fileLength;
  @override
  RangeSet get available {
    if (_nativeTorrent != null) {
      // Before metadata arrives, pieceCount() is 0 and the native bitfield
      // read (transport_lt_torrent_copy_piece_bitfield) correctly rejects a
      // zero-capacity buffer with a typed error; pieceBitfield() then throws.
      // A consumer calling currentStatus in that window (e.g. immediately
      // after open()) must see SourceState.metadata, not a crash -- found via
      // a real-fixture run, see bug_history.md.
      if (!_nativeTorrent.metadataReady) return RangeSet.empty();
      final bits = _nativeTorrent.pieceBitfield();
      return mapper.rangesForPieces(<int>[
        for (var i = 0; i < bits.length; i++)
          if (bits[i] != 0) i,
      ]);
    }
    return mapper.rangesForPieces(_pieces);
  }

  void pieceFinished(int piece) {
    if (_pieces.add(piece)) _changes.add(null);
  }

  /// Keeps this stream inside [budget]'s limit: pieces beyond the ahead window
  /// are not downloaded, and pieces outside the window around the play head
  /// are forgotten and their disk blocks freed.
  void enableCacheLimit({
    required CacheBudget budget,
    required AppLogger logger,
    required String filePath,
  }) {
    final native = _nativeTorrent;
    if (native == null) return;
    final fs = budget.fs;
    // libtorrent creates the file when the metadata arrives.
    int measure(String path, {int offset = 0, int? length}) =>
        File(path).existsSync()
        ? fs.allocatedBytes(path, offset: offset, length: length)
        : 0;
    _dormantStart = mapper.lastPiece + 1;
    _governor = CacheGovernor(
      budget: budget,
      totalBytes: () => totalBytes,
      available: () => available,
      // libtorrent also writes pieces it has not completed, and the file
      // system may allocate blocks nobody wrote (APFS does, near the file
      // end): everything is checked against what is really allocated.
      occupied: () => RangeSet.empty().add(ByteRange(0, totalBytes - 1)),
      allocatedIn: (range) =>
          measure(filePath, offset: range.start, length: range.length),
      measuredUsed: () => measure(filePath),
      // Each eviction re-adds the torrent, so it runs in big steps (64 MiB).
      evictBatchBytes: math.max(
        mapper.pieceLength,
        math.min(64 * 1024 * 1024, budget.limit ~/ 8),
      ),
      evict: _evict,
      limitAhead: _limitAhead,
      logger: logger,
      onFailure: (error) => _router.failure = error is TransportFailure
          ? error
          : TransportFailure.engineUnavailable(cause: error),
    );
    // Install file and piece priorities together before the first payload.
    final ahead = budget.aheadFor(_governor!, total: totalBytes);
    final int boundary = math.min(
      mapper.lastPiece + 1,
      mapper.firstPiece + math.max(1, ahead ~/ mapper.pieceLength),
    );
    native.initializeDownload(fileIndex, mapper.firstPiece, boundary);
    _dormantStart = boundary;
    _governor!.seekTo(0);
  }

  /// Pieces beyond `head + ahead` get priority 0 so the swarm stops filling
  /// the disk; they get it back as the head moves.
  Future<void> _limitAhead(int head, int aheadBytes) async {
    final native = _nativeTorrent!;
    _aheadBytes = aheadBytes;
    final int headPiece = mapper.pieceForFileOffset(
      head.clamp(0, totalBytes - 1).toInt(),
    );
    final int boundary = math.min(
      mapper.lastPiece + 1,
      headPiece + math.max(1, aheadBytes ~/ mapper.pieceLength),
    );
    final have = native.pieceBitfield();
    bool missing(int piece) => have[piece] == 0;
    if (boundary < _dormantStart) {
      for (var piece = boundary; piece < _dormantStart; piece++) {
        if (missing(piece) && !_demandedPieces.contains(piece)) {
          native.setPiecePriority(piece, 0);
        }
      }
    } else if (boundary > _dormantStart) {
      for (var piece = _dormantStart; piece < boundary; piece++) {
        if (missing(piece)) native.setPiecePriority(piece, 4);
      }
    }
    _dormantStart = boundary;
    // Evicted pieces that fall back into the window are wanted again.
    final wanted = _evictedPieces
        .where((piece) => piece >= headPiece && piece < boundary)
        .toList();
    for (final piece in wanted) {
      native.setPiecePriority(piece, 4);
      _evictedPieces.remove(piece);
    }
  }

  Future<void> _evict(List<ByteRange> ranges) async {
    final native = _nativeTorrent!;
    final pieces = <int>[
      for (final range in ranges)
        for (final piece in mapper.piecesForFileRange(range))
          if (mapper.fileRangeForPiece(piece).start >= range.start &&
              mapper.fileRangeForPiece(piece).endInclusive <=
                  range.endInclusive)
            piece,
    ];
    if (pieces.isEmpty) return;
    _noteDownloaded();
    native.evictPieces(pieces);
    for (final piece in pieces) {
      // Forgotten pieces are not re-downloaded until something asks again.
      if (piece < _dormantStart) native.setPiecePriority(piece, 0);
      _demandedPieces.remove(piece);
      _evictedPieces.add(piece);
    }
    _changes.add(null);
  }

  /// One on-demand read of libtorrent's live counters.
  @override
  Future<TransportStats> readStats() async {
    final native = _nativeTorrent;
    if (native == null) {
      throw UnsupportedError('this torrent source has no live engine');
    }
    final status = native.status;
    final stats = native.stats;
    _noteDownloaded();
    return TransportStats(
      downloadBytesPerSecond: status.downloadRate.toDouble(),
      downloadedBytes: _everDownloaded.ranges.fold<int>(
        0,
        (sum, r) => sum + r.length,
      ),
      totalBytes: totalBytes,
      torrent: TorrentStats(
        uploadBytesPerSecond: stats.uploadRate.toDouble(),
        seeds: stats.seeds,
        peers: stats.peers,
        swarmSeeds: stats.swarmSeeds < 0 ? null : stats.swarmSeeds,
        swarmPeers: stats.swarmPeers < 0 ? null : stats.swarmPeers,
        piecesHave: stats.piecesHave,
        piecesTotal: native.pieceCount,
        pieceSize: native.pieceLength,
        availability: stats.distributedCopies,
        infoHash: native.infoHash,
      ),
    );
  }

  SourceStatus get currentStatus {
    final native = _nativeTorrent;
    var rate = 0;
    if (native != null) {
      final status = native.status;
      rate = status.downloadRate;
      _router.updatePeers(status.peers);
      _router.checkStall();
    }
    final ranges = available;
    final failure = _router.failure;
    final state = failure != null
        ? _router.state
        : ranges.ranges.isEmpty
        ? _router.state
        : SourceState.ready;
    return SourceStatus(
      state: state,
      available: ranges,
      totalBytes: totalBytes,
      bytesPerSecond: rate.toDouble(),
      peersOrConnections: _router.peers,
      failure: failure,
    );
  }

  Future<void> seekHint(int byteOffset) async {
    final native = _nativeTorrent;
    if (native == null) return;
    final offset = byteOffset.clamp(0, totalBytes - 1);
    await _governor?.seekTo(offset);
    final piece = mapper.pieceForFileOffset(offset);
    _router.waitAt(piece, have: native.pieceAvailable(piece));
    _scheduler
        .plan(
          playHead: offset,
          mapper: mapper,
          available: available,
          bitrateBytesPerSecond: native.status.downloadRate,
          maxLookAheadBytes: _aheadBytes,
        )
        .apply(
          clear: native.clearPieceDeadlines,
          prioritize: (piece, priority) => native.setPiecePriority(
            piece,
            _evictedPieces.contains(piece) ? 0 : priority,
          ),
          deadline: native.setPieceDeadline,
        );
  }

  @override
  Future<void> waitFor(ByteRange range) async {
    await seekHint(range.start);
    if (_nativeTorrent != null) {
      // Availability is a piece bitfield, but the default picker may choose
      // distant pieces first. Demand every missing piece covering this range
      // before waiting so a range request cannot starve behind unrelated data.
      for (final piece in mapper.piecesForFileRange(range)) {
        // A read wants this piece again: the scheduler may no longer zero it.
        _evictedPieces.remove(piece);
        if (!_nativeTorrent.pieceAvailable(piece) &&
            _demandedPieces.add(piece)) {
          _nativeTorrent.setPiecePriority(piece, 7);
          _nativeTorrent.setPieceDeadline(piece, 0);
        }
      }
    }
    while (true) {
      _ensureLive();
      if (available.containsRange(range)) break;
      _router.checkStall();
      final failure = _router.failure;
      if (failure != null) throw failure;
      if (_nativeTorrent == null) {
        await _nextChange();
      } else {
        await Future.any<void>([
          _nextChange(),
          Future<void>.delayed(torrentStallThreshold),
        ]);
      }
    }
  }

  // dispose() closes the change stream; a parked waiter then gets "No
  // element". Treat that as a wake-up: the caller's loop sees `_disposed`.
  Future<void> _nextChange() =>
      _changes.stream.first.then<void>((_) {}, onError: (Object _) {});

  /// A disposed source ends quietly. A torrent closed while this source is
  /// still open is a failure, shown through [currentStatus] and the range
  /// response, never a bare "Bad state" from the native handle.
  void _ensureLive() {
    if (_disposed) throw const SparseSourceDisposed();
    final native = _nativeTorrent;
    if (native == null || !native.isClosed) return;
    final failure = TransportFailure.engineUnavailable(
      cause: 'the torrent was closed while its stream was still open',
    );
    _router.failure ??= failure;
    _router.state = SourceState.failed;
    _changes.add(null);
    throw failure;
  }

  void _onAlert(LtAlertEvent event) {
    if (event.torrent != 0 &&
        event.torrent != _nativeTorrent?.nativeHandle.address) {
      return;
    }
    final kind = switch (event.kind) {
      1 => TorrentAlertKind.metadataReceived,
      2 => TorrentAlertKind.pieceFinished,
      3 => TorrentAlertKind.torrentError,
      4 => TorrentAlertKind.fileError,
      5 => TorrentAlertKind.trackerError,
      6 => TorrentAlertKind.torrentFinished,
      7 => TorrentAlertKind.stateChanged,
      8 => TorrentAlertKind.peerDisconnected,
      _ => null,
    };
    if (kind == null || _disposed) return;
    _router.route(
      TorrentAlert(
        kind,
        piece: event.piece < 0 ? null : event.piece,
        peerCount: event.peers < 0 ? null : event.peers,
        error: event.errorCode == 0
            ? event.message
            : '${event.errorCode}: ${event.message}',
      ),
    );
    _changes.add(null);
    if (kind == TorrentAlertKind.pieceFinished) _governor?.poke();
  }

  @override
  Stream<List<int>> read(ByteRange range) async* {
    if (_nativeTorrent != null) {
      final reader = Object();
      var offset = range.start;
      try {
        while (offset <= range.endInclusive) {
          _ensureLive();
          final end = (offset + 256 * 1024 - 1).clamp(
            offset,
            range.endInclusive,
          );
          final chunk = ByteRange(offset, end);
          await waitFor(chunk);
          final bytes = Uint8List(chunk.length);
          final count = _nativeTorrent.read(fileIndex, offset, bytes);
          if (count != bytes.length) {
            throw StateError('short torrent read: $chunk');
          }
          yield bytes;
          offset = end + 1;
          _governor?.readAt(reader, offset);
        }
      } finally {
        _governor?.readDone(reader);
      }
      return;
    }
    final raf = await file.open();
    try {
      var offset = range.start;
      while (offset <= range.endInclusive) {
        final end = (offset + 256 * 1024 - 1).clamp(offset, range.endInclusive);
        final chunk = ByteRange(offset, end);
        await waitFor(chunk);
        await raf.setPosition(mapper.fileOffsetInTorrent + offset);
        final bytes = await raf.read(chunk.length);
        if (bytes.length != chunk.length) {
          throw StateError('short torrent read: $chunk');
        }
        yield bytes;
        offset = end + 1;
      }
    } finally {
      await raf.close();
    }
  }

  @override
  void releaseDemand(Object token) {}
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _governor?.dispose();
    await _alertSubscription?.cancel();
    await _changes.close();
  }
}
