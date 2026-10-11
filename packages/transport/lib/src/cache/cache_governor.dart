import 'dart:async';
import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'cache_budget.dart';
import 'range_ops.dart';

/// Keeps one open stream inside the cache limit. Driven by reader position
/// events (no timer of its own): it tells the transport to stop downloading
/// beyond the ahead window and evicts data outside the window around the
/// play head.
class CacheGovernor implements CacheClient {
  CacheGovernor({
    required this.budget,
    required this.totalBytes,
    required this.available,
    required this.evictBatchBytes,
    this.occupied,
    this.allocatedIn,
    this.measuredUsed,
    required this.evict,
    required this.limitAhead,
    required this._logger,
    required this.onFailure,
  }) {
    budget.register(this);
  }

  final CacheBudget budget;
  final int? Function() totalBytes;
  final RangeSet Function() available;

  /// Everything that may hold disk bytes, when that is more than [available]
  /// (a torrent also writes pieces it has not completed). Defaults to
  /// [available].
  final RangeSet Function()? occupied;

  /// Disk bytes really allocated inside a range, when the transport can tell.
  final int Function(ByteRange range)? allocatedIn;

  /// Disk bytes the whole stream really occupies, when the transport can tell.
  final int Function()? measuredUsed;

  /// Evict nothing until at least this many bytes are outside the window.
  final int evictBatchBytes;

  /// Frees the given ranges (disk and bookkeeping).
  final Future<void> Function(List<ByteRange> ranges) evict;

  /// Stops or resumes downloading so data ahead of [head] stays within
  /// [aheadBytes].
  final Future<void> Function(int head, int aheadBytes) limitAhead;
  final void Function(Object error) onFailure;
  final AppLogger _logger;

  static const int _step = 1024 * 1024;

  /// A read must have delivered this much before it counts as the playback
  /// position; shorter reads (index probes at the file end) do not move it.
  static const int _primaryAfter = 1024 * 1024;

  /// Around each active reader, data that is never evicted.
  static const int _readerBehind = 1024 * 1024;
  static const int _readerAhead = 8 * 1024 * 1024;

  final Map<Object, ({int start, int pos})> _readers = {};
  int _head = 0;
  int _evaluatedHead = -(1 << 60);
  bool _running = false;
  bool _rerun = false;
  bool _closed = false;
  final Stopwatch _sinceEvaluation = Stopwatch()..start();
  Future<void>? _inflight;

  // Availability read once per evaluation (a torrent builds it from a bitfield).
  RangeSet? _snapshot;

  @override
  int get usedBytes =>
      measuredUsed?.call() ?? rangesLength(_snapshot ?? available());

  @override
  int get batchBytes => evictBatchBytes;

  /// A reader delivered bytes up to [position].
  void readAt(Object reader, int position) {
    final start = _readers[reader]?.start ?? position;
    _readers[reader] = (start: start, pos: position);
    if (position - start >= _primaryAfter) _head = position;
    if ((_head - _evaluatedHead).abs() >= _step) _schedule();
  }

  void readDone(Object reader) => _readers.remove(reader);

  /// Playback moved to [offset] (control-plane seek).
  Future<void> seekTo(int offset) async {
    _head = offset;
    _schedule();
    await _inflight;
  }

  /// Something else changed (new data arrived): look again, at most every
  /// 200 ms so a fast swarm does not keep the isolate busy.
  void poke() {
    if (_sinceEvaluation.elapsedMilliseconds < 200) return;
    _schedule();
  }

  void _schedule() {
    if (_closed) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    _inflight = _run();
  }

  Future<void> _run() async {
    try {
      do {
        _rerun = false;
        _evaluatedHead = _head;
        await _evaluate();
      } while (_rerun && !_closed);
    } catch (error, stack) {
      _logger.error(
        'Cache limit enforcement failed',
        error: error,
        stack: stack,
      );
      onFailure(error);
    } finally {
      _running = false;
    }
  }

  Future<void> _evaluate() async {
    final total = totalBytes();
    if (total == null || total <= 0) return;
    _sinceEvaluation.reset();
    final snapshot = _snapshot = (occupied ?? available)();
    final ahead = budget.aheadFor(this, total: total);
    final head = _head;
    if (ahead >= total) {
      // The whole file fits: download it all, evict nothing.
      _snapshot = null;
      await budget.makeRoom();
      await limitAhead(head, ahead);
      return;
    }
    final futureWindow = ByteRange(
      head.clamp(0, total - 1).toInt(),
      (head + math.max(1, ahead) - 1).clamp(0, total - 1).toInt(),
    );
    final projectedUsed = budget.openUsed - usedBytes +
        rangesLength(snapshot.add(futureWindow));
    final keepStart = math.max(0, head - budget.backWindow);
    var outside = subtractRange(
      snapshot,
      ByteRange(keepStart, math.max(keepStart, head + ahead - 1)),
    );
    for (final reader in _readers.values) {
      outside = subtractRange(
        outside,
        ByteRange(
          math.max(0, reader.pos - _readerBehind),
          reader.pos + _readerAhead,
        ),
      );
    }
    _snapshot = null;
    final measure = allocatedIn;
    final outsideBytes = measure == null
        ? rangesLength(outside)
        : outside.ranges.fold<int>(0, (sum, r) => sum + measure(r));
    await budget.makeRoom();
    if (outsideBytes >= evictBatchBytes &&
        projectedUsed >= budget.limit - evictBatchBytes) {
      _logger.info(
        'Cache limit: evicting $outsideBytes bytes '
        'outside the window at $_head',
      );
      await evict(outside.ranges.toList());
    }
    await limitAhead(head, ahead);
  }

  Future<void> dispose() async {
    _closed = true;
    budget.unregister(this);
    await _inflight;
  }
}
