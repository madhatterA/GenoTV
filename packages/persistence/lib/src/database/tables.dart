import 'package:drift/drift.dart';

// SQL names below are drift's default snake_case translation of these Dart
// class/column names (`case_from_dart_to_sql: snake_case` is the default —
// confirmed via Context7, no `tableName`/`.named()` overrides needed).
//
// Every timestamp is a plain `IntColumn`, **UTC milliseconds since epoch**
// — not drift's `dateTime()` column type. Its default storage mode uses
// SECONDS (not milliseconds) and discards the UTC flag on retrieval
// (Context7, drift docs: "information about whether a date was UTC is
// lost upon retrieval, as Drift always returns a non-UTC value"), which
// would break every `.isUtc` invariant `packages/contracts` already
// enforces. Repositories convert explicitly:
// `.toUtc().millisecondsSinceEpoch` in, `DateTime.fromMillisecondsSinceEpoch
// (v, isUtc: true)` out.

@TableIndex(name: 'playback_progress_updated_at', columns: {#updatedAt})
class PlaybackProgress extends Table {
  TextColumn get mediaId => text()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get completed => boolean()();
  TextColumn get audioTrackId => text().nullable()();
  TextColumn get subtitleTrackId => text().nullable()();
  // v2: so "resume" can reopen the same source it was playing rather than
  // re-picking one (Chapter 04 Phase 03).
  TextColumn get lastPlayedSourceKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {mediaId};
}

class Favourites extends Table {
  TextColumn get mediaId => text()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {mediaId};
}

class NextUp extends Table {
  TextColumn get seriesId => text()();
  TextColumn get mediaId => text()();
  IntColumn get season => integer()();
  IntColumn get episode => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {seriesId};
}

// @DataClassName avoids a name collision: drift's default naming would
// generate a `DownloadRecord` class here, colliding with contracts'
// `DownloadRecord` value type (`package:contracts/contracts.dart`) in any
// file that imports both.
@TableIndex(name: 'download_records_last_used_at', columns: {#lastUsedAt})
@DataClassName('DownloadRecordRow')
class DownloadRecords extends Table {
  TextColumn get sourceKey => text()();
  TextColumn get kind => text()();
  TextColumn get filePath => text().nullable()();
  IntColumn get totalBytes => integer().nullable()();
  TextColumn get validator => text().nullable()();
  IntColumn get lastUsedAt => integer()();

  @override
  Set<Column> get primaryKey => {sourceKey};
}

class TorrentResume extends Table {
  TextColumn get infoHash => text()();
  BlobColumn get data => blob()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {infoHash};
}
