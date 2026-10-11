import 'package:core/core.dart';

/// Persistence failures, `storage.*` prefix (`planning/CONTRACTS.md` §7,
/// owned by Part 01 via `packages/persistence`). Losing watch progress is
/// not fatal; hiding that it was lost is — a storage failure is surfaced
/// like any other, never swallowed.
final class PersistenceFailure extends AppFailure {
  const PersistenceFailure.openFailed({required super.cause, super.stack})
      : super(code: _openFailed, message: 'Failed to open the database');

  const PersistenceFailure.migrationFailed({required super.cause, super.stack})
      : super(code: _migrationFailed, message: 'A database migration failed');

  const PersistenceFailure.writeFailed({required super.cause, super.stack})
      : super(code: _writeFailed, message: 'Failed to write to the database');

  const PersistenceFailure.corrupt({super.cause, super.stack})
      : super(code: _corrupt, message: 'The database is corrupt');

  static const String _openFailed = 'storage.open_failed';
  static const String _migrationFailed = 'storage.migration_failed';
  static const String _writeFailed = 'storage.write_failed';
  static const String _corrupt = 'storage.corrupt';
}
