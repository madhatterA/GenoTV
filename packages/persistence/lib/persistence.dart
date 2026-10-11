/// SQLite (drift) schema, migrations and repository implementations.
///
/// Owned by Part 01. See `planning/part-01-*/PART.md`.
///
/// Deliberately does not export the schema (`src/database/tables.dart`),
/// drift's generated DAOs, `AppDatabase` itself, or the concrete repository
/// classes (Chapter 04 Phase 02 step 2: "the concrete classes and
/// AppDatabase stay library-private"). `AppDatabase` is an opaque handle:
/// `openDatabase()` returns one, the four factories below take one — Part
/// 07 wires them together via type inference (`final db = await
/// openDatabase(...)`) without ever needing to name the type. No Part
/// queries a database directly (`planning/CONTRACTS.md` §7: repositories
/// are the only persistence surface).
library;

export 'src/database/app_database.dart' show openDatabase, recoverByRenaming;
export 'src/repositories/drift_favourites_repository.dart' show createFavouritesRepository;
export 'src/repositories/drift_next_up_repository.dart' show createNextUpRepository;
export 'src/repositories/drift_progress_repository.dart' show createProgressRepository;
export 'src/repositories/drift_transport_state_repository.dart'
    show createTransportStateRepository;
