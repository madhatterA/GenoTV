import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../write_queue.dart';

/// **Read/write failure asymmetry is deliberate.** Reads fail quietly:
/// a drift exception becomes a [PersistenceFailure], is logged, and the
/// call returns null/empty rather than throwing — a repository call never
/// throws for "not found" or "storage hiccup" (`planning/CONTRACTS.md`
/// §7). Writes fail quietly too, but for a different reason: throwing a
/// storage failure into a playback path must never stop the video because
/// a write failed. Neither is a swallowed error — both are logged via
/// [FailureLogging.failure].
class DriftProgressRepository implements ProgressRepository {
  DriftProgressRepository(this._db, AppLogger logger)
    : _logger = logger.scoped('persistence.progress'),
      _queue = WriteQueue<String, PlaybackProgress>(
        flushOne: (key, value) => _write(_db, value),
        logger: logger,
      );

  final AppDatabase _db;
  final AppLogger _logger;
  final WriteQueue<String, PlaybackProgress> _queue;

  @override
  Future<PlaybackProgress?> get(String mediaId) async {
    final pending = _queue.pendingValueFor(mediaId);
    if (pending != null) return pending;

    try {
      final row = await (_db.select(
        _db.playbackProgress,
      )..where((t) => t.mediaId.equals(mediaId))).getSingleOrNull();
      return row == null ? null : _fromRow(row);
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return null;
    }
  }

  @override
  Future<void> upsert(PlaybackProgress progress) async {
    _queue.write(progress.mediaId, progress);
  }

  /// Merges committed rows with anything still sitting in the write
  /// queue before filtering/sorting — **in Dart, not pushed down to SQL**.
  /// A deliberate departure from a DB-pushed-down `WHERE`/`ORDER BY`/
  /// `LIMIT` query: a pending write isn't in the table yet, so filtering
  /// there alone would miss it (the same read-after-queued-write gap as
  /// [get]). This app's continue-watching list is tens to low hundreds of
  /// rows, so an in-memory merge costs nothing that matters.
  @override
  Future<List<PlaybackProgress>> continueWatching({int limit = 20}) async {
    try {
      final rows = await _db.select(_db.playbackProgress).get();
      final merged = <String, PlaybackProgress>{
        for (final row in rows) row.mediaId: _fromRow(row),
        ..._queue.pendingEntries,
      };
      final result = merged.values.where((p) => !p.completed).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result.take(limit).toList();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return const <PlaybackProgress>[];
    }
  }

  @override
  Future<List<PlaybackProgress>> history({int limit = 20}) async {
    try {
      final rows = await _db.select(_db.playbackProgress).get();
      final merged = <String, PlaybackProgress>{
        for (final row in rows) row.mediaId: _fromRow(row),
        ..._queue.pendingEntries,
      };
      final result = merged.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result.take(limit).toList();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return const <PlaybackProgress>[];
    }
  }

  @override
  Future<void> clear(String mediaId) async {
    try {
      await (_db.delete(
        _db.playbackProgress,
      )..where((t) => t.mediaId.equals(mediaId))).go();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    }
  }

  /// Merges drift's own change stream (replays the current committed row
  /// to a new listener) with [WriteQueue.changes] — a write that hasn't
  /// flushed yet doesn't change the table, so drift's stream alone would
  /// show the stale row until the debounce window elapses.
  @override
  Stream<PlaybackProgress> watch(String mediaId) {
    late StreamController<PlaybackProgress> controller;
    StreamSubscription<PlaybackProgressData?>? dbSub;
    StreamSubscription<String>? pendingSub;

    void pushPendingIfAny() {
      final pending = _queue.pendingValueFor(mediaId);
      if (pending != null) controller.add(pending);
    }

    controller = StreamController<PlaybackProgress>.broadcast(
      onListen: () {
        dbSub =
            (_db.select(_db.playbackProgress)
                  ..where((t) => t.mediaId.equals(mediaId)))
                // OrNull: a write still sitting in the queue hasn't reached the
                // table yet, so the row may not exist there at all (watchSingle
                // would throw on zero rows instead of just... not existing yet).
                .watchSingleOrNull()
                .listen(
                  // A still-pending write is newer than whatever drift just
                  // reported from disk — don't let the stale/absent row
                  // overwrite it.
                  (row) {
                    if (row != null &&
                        _queue.pendingValueFor(mediaId) == null) {
                      controller.add(_fromRow(row));
                    }
                  },
                  onError: controller.addError,
                );
        pendingSub = _queue.changes
            .where((key) => key == mediaId)
            .listen((_) => pushPendingIfAny());
        pushPendingIfAny(); // a write queued before this subscription started
      },
      onCancel: () async {
        await dbSub?.cancel();
        await pendingSub?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  /// Flushes any pending debounced write. Call on shutdown.
  Future<void> dispose() => _queue.dispose();

  static PlaybackProgress _fromRow(PlaybackProgressData row) =>
      PlaybackProgress(
        mediaId: row.mediaId,
        position: Duration(milliseconds: row.positionMs),
        duration: Duration(milliseconds: row.durationMs),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row.updatedAt,
          isUtc: true,
        ),
        completed: row.completed,
        audioTrackId: row.audioTrackId,
        subtitleTrackId: row.subtitleTrackId,
      );

  static Future<void> _write(AppDatabase db, PlaybackProgress progress) {
    return db
        .into(db.playbackProgress)
        .insertOnConflictUpdate(
          PlaybackProgressCompanion.insert(
            mediaId: progress.mediaId,
            positionMs: progress.position.inMilliseconds,
            durationMs: progress.duration.inMilliseconds,
            updatedAt: progress.updatedAt.toUtc().millisecondsSinceEpoch,
            completed: progress.completed,
            audioTrackId: Value(progress.audioTrackId),
            subtitleTrackId: Value(progress.subtitleTrackId),
          ),
        );
  }
}

ProgressRepository createProgressRepository(AppDatabase db, AppLogger logger) =>
    DriftProgressRepository(db, logger);
