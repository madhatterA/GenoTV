import 'dart:io';

// show only: contracts' PlaybackProgress value type would otherwise
// collide with tables.dart's PlaybackProgress Table class below.
import 'package:contracts/contracts.dart' show PersistenceFailure;
import 'package:core/core.dart';
import 'package:drift/drift.dart';

import 'connection.dart';
import 'schema_versions.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [PlaybackProgress, Favourites, NextUp, DownloadRecords, TorrentResume])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  /// **No destructive fallback, ever.** A migration failure must never
  /// "drop and recreate" — that silently deletes the user's watch history.
  /// It surfaces as `storage.migration_failed` instead, with the database
  /// left untouched (Chapter 04 Phase 03 step 3/pitfalls: "the single most
  /// damaging thing this file could contain").
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // Stepwise, one version at a time, never a jump — generated from
        // the committed `drift_schemas/` snapshots
        // (`dart run drift_dev schema steps`), see MIGRATIONS.md.
        onUpgrade: stepByStep(
          from1To2: (m, schema) async {
            // Atomic: if a future multi-statement step throws partway
            // through, this rolls back rather than leaving a half-migrated
            // schema on disk.
            await transaction(() async {
              await m.addColumn(
                  schema.playbackProgress, schema.playbackProgress.lastPlayedSourceKey);
            });
          },
        ),
        beforeOpen: (details) async {
          // WAL lets a single writer and multiple readers operate in
          // parallel; the busy timeout avoids SQLITE_BUSY under
          // concurrent writes from Part 03 instead of failing immediately.
          await customStatement('PRAGMA journal_mode=WAL;');
          await customStatement('PRAGMA busy_timeout=5000;');
          // No foreign keys in v1/v2 (Phase 01 step 5) — nothing to enforce.
          //
          // No runtime validateDatabaseSchema() call here: it lives in
          // `package:drift_dev`, a dev-only tool. Importing it from this
          // file (shipped, `lib/` runtime code) would require `drift_dev`
          // as a REGULAR dependency of `packages/persistence` — but a
          // dependent package's dev_dependencies are never inherited by
          // its own dependents (pub semantics), so `app/`'s build would
          // fail to resolve it. The same "create and migrate produce an
          // identical schema" check runs instead in
          // `test/migration_test.dart` via drift's `SchemaVerifier`, which
          // is exactly what drift's own testing guide uses it for.
        },
      );
}

/// Opens the database, applying migrations if needed
/// (`planning/CONTRACTS.md` §8). Forces the lazy connection open before
/// returning — by the time this `Future` completes, the schema has been
/// created/migrated, not deferred to the caller's first real query.
///
/// Throws [PersistenceFailure] (never an untyped exception) if opening or
/// migrating fails. `.corrupt` for a truncated/garbage file; `.migrationFailed`
/// otherwise — connecting and migrating are the only things that can fail
/// this early, and `MigrationStrategy.onUpgrade` above rolls back on its
/// own failure (`transaction(...)`), so the file is left untouched either
/// way. **No destructive fallback**: this function never deletes or
/// recreates the file itself — see [recoverByRenaming], which the caller
/// must call explicitly.
Future<AppDatabase> openDatabase({required AppPaths paths}) async {
  final database = AppDatabase(openConnection(paths));
  try {
    await database.customSelect('SELECT 1').getSingleOrNull();
  } catch (e, stack) {
    await database.close();
    final message = e.toString().toLowerCase();
    final looksCorrupt = message.contains('malformed') ||
        message.contains('not a database') ||
        message.contains('file is encrypted or is not a database');
    throw looksCorrupt
        ? PersistenceFailure.corrupt(cause: e, stack: stack)
        : PersistenceFailure.migrationFailed(cause: e, stack: stack);
  }
  return database;
}

/// Moves a corrupt/unusable database file aside so a subsequent
/// [openDatabase] call starts fresh. **Never called automatically** — the
/// recovery policy is report, do not delete: losing a library silently is
/// worse than an error the owner can act on (Chapter 04 Phase 03 step 5).
Future<void> recoverByRenaming({required AppPaths paths}) async {
  final dir = await paths.support;
  final file = File('${dir.path}/app.db');
  if (!file.existsSync()) return;
  final backupPath =
      '${file.path}.corrupt-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  await file.rename(backupPath);
}
