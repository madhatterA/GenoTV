import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../database/app_database.dart';

/// Reads fail quietly: a drift exception becomes a [PersistenceFailure],
/// is logged, and the call returns null rather than throwing. Writes here
/// are infrequent (an episode boundary crossing), so they go straight to
/// disk — no `WriteQueue`.
class DriftNextUpRepository implements NextUpRepository {
  DriftNextUpRepository(this._db, AppLogger logger)
      : _logger = logger.scoped('persistence.nextUp');

  final AppDatabase _db;
  final AppLogger _logger;

  @override
  Future<NextUpEntry?> forSeries(String seriesId) async {
    try {
      final row = await (_db.select(_db.nextUp)..where((t) => t.seriesId.equals(seriesId)))
          .getSingleOrNull();
      return row == null ? null : _fromRow(row);
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return null;
    }
  }

  @override
  Future<void> set(NextUpEntry entry) async {
    try {
      await _db.into(_db.nextUp).insertOnConflictUpdate(
            NextUpCompanion.insert(
              seriesId: entry.seriesId,
              mediaId: entry.mediaId,
              season: entry.season,
              episode: entry.episode,
              updatedAt: entry.updatedAt.toUtc().millisecondsSinceEpoch,
            ),
          );
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    }
  }

  @override
  Future<void> clear(String seriesId) async {
    try {
      await (_db.delete(_db.nextUp)..where((t) => t.seriesId.equals(seriesId))).go();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    }
  }

  static NextUpEntry _fromRow(NextUpData row) => NextUpEntry(
        seriesId: row.seriesId,
        mediaId: row.mediaId,
        season: row.season,
        episode: row.episode,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true),
      );
}

NextUpRepository createNextUpRepository(AppDatabase db, AppLogger logger) =>
    DriftNextUpRepository(db, logger);
