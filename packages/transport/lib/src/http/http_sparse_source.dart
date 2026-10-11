import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../cache/cache_budget.dart';
import '../cache/cache_governor.dart';
import '../cache/fs_native.dart';
import '../cache/range_ops.dart';
import '../server/sparse_source.dart';
import 'aria2_backend.dart';

/// Reads aria2's partial output only after the backend marks pieces complete.
class HttpSparseSource implements SparseSource, TransportStatsProvider {
  HttpSparseSource({
    required this.file,
    required this.totalBytes,
    RangeSet? available,
    this.backend,
    this.jobId,
  }) : _available = available ?? RangeSet.empty() {
    _noteDownloaded(_available);
  }
  final File file;
  @override
  int? totalBytes;
  final Aria2Backend? backend;
  final String? jobId;
  RangeSet _available;

  /// Every byte this stream has had on disk since it opened, evicted or not:
  /// the cache limit frees bytes behind the play head, so the on-disk set
  /// stays about one window long while the download really progresses.
  RangeSet _everDownloaded = RangeSet.empty();
  final StreamController<void> _changed = StreamController<void>.broadcast();
  Timer? _poller;
  StreamSubscription<RangeSet>? _availabilityEvents;
  Object? _failure;
  bool _disposed = false;
  CacheGovernor? _governor;
  FsNative? _fs;

  /// The main download is paused (cache limit reached or a seek window).
  bool paused = false;

  /// Ranges were punched out of [file]: it is no longer a reusable prefix.
  bool hasEvicted = false;
  @override
  RangeSet get available => _available;
  Object? get failure => _failure;
  void startMonitoring() {
    if (_poller != null || backend == null || jobId == null) return;
    _availabilityEvents = backend!
        .availabilityChanges(jobId!)
        .listen(updateAvailability);
    _poller = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
    unawaited(_poll());
  }

  /// Keeps this stream inside [budget]'s limit: stops the download once the
  /// ahead window is full and frees data outside the play-head window.
  void enableCacheLimit({
    required CacheBudget budget,
    required FsNative fs,
    required AppLogger logger,
  }) {
    _fs = fs;
    _governor = CacheGovernor(
      budget: budget,
      totalBytes: () => totalBytes,
      available: () => _available,
      measuredUsed: () => backend!.reservedBytes(jobId!),
      evictBatchBytes: budget.batchFor(16 * 1024 * 1024),
      evict: _evict,
      limitAhead: _limitAhead,
      logger: logger,
      onFailure: (error) {
        _failure = error;
        if (!_changed.isClosed) _changed.add(null);
      },
    );
  }

  Future<void> _limitAhead(int head, int aheadBytes) async {
    if (_disposed || backend == null || jobId == null) return;
    final size = totalBytes;
    if (size == null || size <= 0 || head >= size) return;
    if (aheadBytes <= 0) {
      await backend!.setPaused(jobId!, paused: true);
      return;
    }
    if (aheadBytes >= size) {
      // The whole file fits: fetch from the play head to the end, then the
      // part before it.
      final whole = ByteRange(0, size - 1);
      if (_available.containsRange(whole)) return;
      final tail = ByteRange(head, size - 1);
      await backend!.changeWindow(
        jobId!,
        _available.containsRange(tail) ? whole : tail,
        updateAhead: true,
        copyAll: true,
      );
      return;
    }
    await backend!.changeWindow(
      jobId!,
      ByteRange(head, (head + aheadBytes - 1).clamp(head, size - 1)),
      updateAhead: true,
    );
  }

  Future<void> _evict(List<ByteRange> ranges) async {
    if (_disposed || backend == null || jobId == null) return;
    if (!hasEvicted) {
      // Persist before punching: a crash must not reopen aria2's stale bits.
      await File('${file.path}.evicted').writeAsString('1', flush: true);
      hasEvicted = true;
    }
    for (final range in ranges) {
      // Hide the range before punching so no reader starts on bytes about to
      // vanish. forget() is queued behind any status poll already running,
      // so a stale poll cannot bring the range back.
      await backend!.forget(jobId!, range);
      _available = subtractRange(_available, range);
      _fs!.punchHole(file.path, range.start, range.length);
      hasEvicted = true;
    }
    if (!_changed.isClosed) _changed.add(null);
  }

  /// One on-demand read of aria2's live counters (speed, connections).
  @override
  Future<TransportStats> readStats() async {
    _check();
    final status = await backend!.status(jobId!);
    _noteDownloaded(status.available);
    return TransportStats(
      downloadBytesPerSecond: status.bytesPerSecond,
      downloadedBytes: _everDownloaded.ranges.fold<int>(
        0,
        (sum, r) => sum + r.length,
      ),
      totalBytes: totalBytes ?? status.totalBytes,
      connections: status.peersOrConnections,
    );
  }

  Future<void> _poll() async {
    if (_disposed || backend == null || jobId == null) return;
    try {
      final status = await backend!.status(jobId!);
      final complete =
          totalBytes != null &&
          totalBytes! > 0 &&
          _available.containsRange(ByteRange(0, totalBytes! - 1));
      var changed = !complete && !_sameRanges(status.available, _available);
      if (!complete && status.available.ranges.isNotEmpty) {
        _available = status.available;
        _noteDownloaded(_available);
      }
      paused = status.paused;
      if (totalBytes == null && status.totalBytes != null) {
        totalBytes = status.totalBytes;
        changed = true;
      }
      if (status.error != null) {
        _failure = status.error;
        changed = true;
      }
      if (changed && !_changed.isClosed) _changed.add(null);
      _governor?.poke();
    } catch (error) {
      _failure = error;
      if (!_changed.isClosed) _changed.add(null);
    }
  }

  void _noteDownloaded(RangeSet now) {
    for (final range in now.ranges) {
      _everDownloaded = _everDownloaded.add(range);
    }
  }

  void updateAvailability(RangeSet next) {
    if (_available == next) return;
    _available = next;
    _noteDownloaded(next);
    if (!_changed.isClosed) _changed.add(null);
  }

  /// Parked [waitFor] calls. One download window serves one place at a time,
  /// so only the newest reader steers it: a player that streams from byte 0
  /// and also reads the index at the file end would otherwise drag the window
  /// back and forth and starve the newcomer until the range server's timeout.
  final List<_Wait> _waiters = [];
  int _waitOrder = 0;

  @override
  Future<void> waitFor(
    ByteRange range, {
    ByteRange? downloadRange,
    int? order,
  }) async {
    _check();
    if (_available.containsRange(range)) return;
    final me = _Wait(order ?? ++_waitOrder);
    _waiters.add(me);
    var steering = false;
    try {
      while (!_available.containsRange(range)) {
        if (_failure != null) throw _failure!;
        if (_disposed) throw const SparseSourceDisposed();
        final newest = _waiters.reduce((a, b) => b.order > a.order ? b : a);
        final mine = identical(newest, me);
        if (mine && !steering && backend != null && jobId != null) {
          unawaited(
            backend!.changeWindow(jobId!, downloadRange ?? range).catchError((
              Object error,
            ) {
              if (_disposed) return;
              _failure = error;
              if (!_changed.isClosed) _changed.add(null);
            }),
          );
        }
        steering = mine;
        try {
          await _changed.stream.first;
        } on StateError {
          // dispose() closed the change stream while this waiter was parked.
          throw const SparseSourceDisposed();
        }
      }
    } finally {
      _waiters.remove(me);
      // The next-newest reader takes the window over.
      if (_waiters.isNotEmpty && !_changed.isClosed) _changed.add(null);
    }
  }

  @override
  Stream<List<int>> read(ByteRange range) async* {
    final order = ++_waitOrder;
    await waitFor(
      ByteRange(
        range.start,
        (range.start + 256 * 1024 - 1).clamp(range.start, range.endInclusive),
      ),
      downloadRange: range,
      order: order,
    );
    final reader = Object();
    final handle = await file.open();
    try {
      await handle.setPosition(range.start);
      var offset = range.start;
      while (offset <= range.endInclusive) {
        final end = (offset + 256 * 1024 - 1).clamp(offset, range.endInclusive);
        final chunk = ByteRange(offset, end);
        await waitFor(chunk, downloadRange: range, order: order);
        final bytes = await handle.read(chunk.length);
        if (bytes.length != chunk.length) {
          throw StateError('short partial-file read for $chunk');
        }
        yield bytes;
        offset = end + 1;
        _governor?.readAt(reader, offset);
      }
    } finally {
      _governor?.readDone(reader);
      await handle.close();
    }
  }

  @override
  void releaseDemand(Object token) {}
  Future<void> seekHint(int offset) async {
    _check();
    final size = totalBytes;
    if (size == null || size <= 0 || backend == null || jobId == null) return;
    final start = offset.clamp(0, size - 1);
    await _governor?.seekTo(start);
    final end = (start + 64 * 1024 * 1024 - 1).clamp(start, size - 1);
    await backend!.changeWindow(jobId!, ByteRange(start, end));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _poller?.cancel();
    await _availabilityEvents?.cancel();
    await _governor?.dispose();
    await _changed.close();
  }

  void _check() {
    if (_disposed) throw const SparseSourceDisposed();
  }

  bool _sameRanges(RangeSet a, RangeSet b) {
    final left = a.ranges.toList();
    final right = b.ranges.toList();
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].start != right[i].start ||
          left[i].endInclusive != right[i].endInclusive) {
        return false;
      }
    }
    return true;
  }
}

class _Wait {
  _Wait(this.order);
  final int order;
}
