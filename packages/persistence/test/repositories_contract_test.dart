import 'package:contracts/testing.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:persistence/persistence.dart';
import 'package:persistence/src/database/app_database.dart';

/// Same suite the in-memory fakes pass (`packages/contracts`, Chapter 03
/// Phase 06) — run here against the real drift implementations.
AppDatabase _newDatabase() => AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        // Recommended for Flutter tests to avoid stream-related test
        // errors (Context7, drift testing guide).
        closeStreamsSynchronously: true,
      ),
    );

void main() {
  runProgressRepositoryContractTests(
    () => createProgressRepository(_newDatabase(), MemoryLogger()),
  );
  runFavouritesRepositoryContractTests(
    () => createFavouritesRepository(_newDatabase(), MemoryLogger()),
  );
  runNextUpRepositoryContractTests(
    () => createNextUpRepository(_newDatabase(), MemoryLogger()),
  );
  runTransportStateRepositoryContractTests(
    () => createTransportStateRepository(_newDatabase(), MemoryLogger()),
  );
}
