import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

/// Coalesces writes **per key** within [window] instead of writing
/// synchronously on every call — playback progress is written every few
/// seconds during playback plus on every pause/seek, and writing each one
/// straight to disk thrashes it (and the battery, on a phone).
///
/// **Read-through**: [pendingValueFor] returns the latest queued value
/// immediately, even before it has actually flushed — a repository's
/// `get()` must check this first, or a read right after a write shows the
/// stale row (Chapter 04 Phase 02 step 6).
///
/// A failed flush is logged as a [PersistenceFailure] and never rethrown —
/// losing a progress write must not kill playback (step 7's deliberate
/// write-fails-quietly asymmetry; reads fail quietly for the same reason,
/// documented on each repository).
class WriteQueue<K, V> {
  WriteQueue({
    required this.flushOne,
    required AppLogger logger,
    this.window = const Duration(seconds: 2),
  }) : _logger = logger.scoped('persistence.writeQueue');

  final Future<void> Function(K key, V value) flushOne;
  final AppLogger _logger;
  final Duration window;

  final Map<K, V> _pending = {};
  final Map<K, Timer> _timers = {};
  final StreamController<K> _changes = StreamController<K>.broadcast();

  /// The latest queued (not yet flushed) value for [key], or null if
  /// nothing is pending for it.
  V? pendingValueFor(K key) => _pending[key];

  /// Every value currently queued (not yet flushed), by key. A list read
  /// (e.g. `continueWatching`) merges this over its DB query results so it
  /// doesn't miss a row still sitting in the queue.
  Map<K, V> get pendingEntries => Map.unmodifiable(_pending);

  /// Emits a key whenever a write is queued *or* flushed for it. A
  /// repository's `watch()` listens to this (filtered to its key) to
  /// re-check [pendingValueFor] the instant a write is queued — not only
  /// once it actually flushes to disk, which drift's own change streams
  /// have no way to know about.
  Stream<K> get changes => _changes.stream;

  /// Queues [value] for [key]. Repeated writes to the same key within
  /// [window] coalesce into one flush carrying the last value; writes to
  /// different keys never coalesce together. [urgent] (e.g. playback
  /// stopping) bypasses the window and flushes immediately.
  void write(K key, V value, {bool urgent = false}) {
    _pending[key] = value;
    _timers.remove(key)?.cancel();
    _changes.add(key);
    if (urgent) {
      unawaited(_flush(key));
      return;
    }
    _timers[key] = Timer(window, () => unawaited(_flush(key)));
  }

  Future<void> _flush(K key) async {
    if (!_pending.containsKey(key)) return;
    final value = _pending.remove(key) as V;
    _timers.remove(key)?.cancel();
    try {
      await flushOne(key, value);
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    } finally {
      _changes.add(key);
    }
  }

  /// Flushes every pending write immediately. Safe to call from
  /// `dispose()` or from an app lifecycle detached/paused signal (Part 07
  /// wires the latter — the flush API only needs to exist here).
  Future<void> flushAll() async {
    for (final key in _pending.keys.toList()) {
      await _flush(key);
    }
  }

  Future<void> dispose() async {
    await flushAll();
    await _changes.close();
  }
}
