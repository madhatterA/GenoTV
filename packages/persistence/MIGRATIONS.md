# Migrations

Every schema change follows the same steps, in order: bump `schemaVersion` in
`lib/src/database/app_database.dart`, add exactly one stepwise `fromNToN+1` upgrade to
`MigrationStrategy.onUpgrade`'s `stepByStep(...)` (never a jump from N to N+2), then
export the new snapshot with `dart run drift_dev schema dump
lib/src/database/app_database.dart drift_schemas/` and regenerate
`lib/src/database/schema_versions.dart` with `dart run drift_dev schema steps
drift_schemas/ lib/src/database/schema_versions.dart`. Commit the new snapshot and the
regenerated file alongside the schema change — a migration without a committed
snapshot to migrate *from* cannot be tested.

Add a migration test for the new step in `test/migration_test.dart`, following the
existing v1→v2 test: populate rows under the *old* schema first, run the migration,
then assert every old row survived with its values intact and any new column has the
value the migration actually wrote (usually `null`). A test against an empty database
proves nothing — it passes even when the real migration drops every row. Regenerate
the test helpers with `dart run drift_dev schema generate --data-classes
--companions drift_schemas/ test/generated_migrations/` after adding the new
snapshot.

Never edit an existing migration step once it has shipped — users on that build are
already past it, and changing it puts them on a schema state nothing can reach. If a
past step was wrong, add a new step that corrects it forward. And never add a
destructive fallback ("drop and recreate on failure") anywhere in the migration path:
a migration failure surfaces as `storage.migration_failed` with the database left
untouched, not a silently wiped library.
