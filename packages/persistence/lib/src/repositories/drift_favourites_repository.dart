import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../database/app_database.dart';

/// Reads fail quietly: a drift exception becomes a [PersistenceFailure],
/// is logged, and the call returns false/empty rather than throwing.
/// Writes here are infrequent, discrete user actions (a favourite toggle),
/// not a high-frequency timer — unlike [DriftProgressRepository] they go
/// straight to disk, no `WriteQueue`.
class DriftFavouritesRepository implements FavouritesRepository {
  DriftFavouritesRepository(this._db, AppLogger logger)
      : _logger = logger.scoped('persistence.favourites');

  final AppDatabase _db;
  final AppLogger _logger;

  @override
  Future<bool> isFavourite(String mediaId) async {
    try {
      final row = await (_db.select(_db.favourites)..where((t) => t.mediaId.equals(mediaId)))
          .getSingleOrNull();
      return row != null;
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return false;
    }
  }

  @override
  Future<void> setFavourite(String mediaId, bool value) async {
    try {
      if (value) {
        await _db.into(_db.favourites).insertOnConflictUpdate(
              FavouritesCompanion.insert(
                mediaId: mediaId,
                addedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      } else {
        await (_db.delete(_db.favourites)..where((t) => t.mediaId.equals(mediaId))).go();
      }
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    }
  }

  @override
  Future<List<String>> all() async {
    try {
      final rows = await _db.select(_db.favourites).get();
      return rows.map((r) => r.mediaId).toList();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return const <String>[];
    }
  }

  @override
  Stream<List<String>> watchAll() {
    return _db.select(_db.favourites).watch().map((rows) => rows.map((r) => r.mediaId).toList());
  }
}

FavouritesRepository createFavouritesRepository(AppDatabase db, AppLogger logger) =>
    DriftFavouritesRepository(db, logger);
