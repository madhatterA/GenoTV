import 'package:core/core.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Opens the database file at `AppPaths.support/app.db`
/// (`packages/core`, Chapter 02 Phase 03), via `drift_flutter`'s
/// `driftDatabase()` helper — the current recommended connection helper
/// (Context7, drift docs). On native platforms this runs the database on a
/// drift-managed background isolate by default
/// (`NativeDatabase.createInBackground` underneath), so opening or
/// querying the database never blocks the UI isolate.
QueryExecutor openConnection(AppPaths paths) {
  return driftDatabase(
    name: 'app',
    native: DriftNativeOptions(
      databasePath: () async => '${(await paths.support).path}/app.db',
    ),
  );
}
