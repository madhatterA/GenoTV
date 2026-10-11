import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../write_queue.dart';

/// **Read/write failure asymmetry is deliberate** — see
/// [DriftProgressRepository]'s doc comment; the same reasoning applies
/// here. Torrent resume data is written on a cadence by Part 03 and can be
/// tens of kilobytes, so [putTorrentResumeData] is routed through the same
/// `WriteQueue` mechanism as progress, with a longer window (10s vs 2s) —
/// it matters far less if the last few seconds of resume data are lost
/// than if a progress write is. `upsert` for [DownloadRecord] itself is
/// not queued: it is not written on a tight timer the way progress and
/// resume data are.
class DriftTransportStateRepository implements TransportStateRepository {
  DriftTransportStateRepository(this._db, AppLogger logger)
      : _logger = logger.scoped('persistence.transportState'),
        _resumeDataQueue = WriteQueue<String, Uint8List>(
          flushOne: (key, value) => _writeResumeData(_db, key, value),
          logger: logger,
          window: const Duration(seconds: 10),
        );

  final AppDatabase _db;
  final AppLogger _logger;
  final WriteQueue<String, Uint8List> _resumeDataQueue;

  @override
  Future<DownloadRecord?> get(String sourceKey) async {
    try {
      final row = await (_db.select(_db.downloadRecords)
            ..where((t) => t.sourceKey.equals(sourceKey)))
          .getSingleOrNull();
      return row == null ? null : _fromRow(row);
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return null;
    }
  }

  @override
  Future<void> upsert(DownloadRecord record) async {
    try {
      await _db.into(_db.downloadRecords).insertOnConflictUpdate(
            DownloadRecordsCompanion.insert(
              sourceKey: record.sourceKey,
              kind: record.kind.name,
              filePath: Value(record.filePath),
              totalBytes: Value(record.totalBytes),
              validator: Value(record.validator),
              lastUsedAt: record.lastUsedAt.toUtc().millisecondsSinceEpoch,
            ),
          );
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    }
  }

  @override
  Future<List<DownloadRecord>> all() async {
    try {
      final rows = await _db.select(_db.downloadRecords).get();
      return rows.map(_fromRow).toList();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return const <DownloadRecord>[];
    }
  }

  @override
  Future<void> delete(String sourceKey) async {
    try {
      await (_db.delete(_db.downloadRecords)..where((t) => t.sourceKey.equals(sourceKey))).go();
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.writeFailed(cause: e, stack: stack));
    }
  }

  @override
  Future<Uint8List?> torrentResumeData(String infoHash) async {
    final pending = _resumeDataQueue.pendingValueFor(infoHash);
    if (pending != null) return pending;

    try {
      final row = await (_db.select(_db.torrentResume)..where((t) => t.infoHash.equals(infoHash)))
          .getSingleOrNull();
      return row?.data;
    } catch (e, stack) {
      _logger.failure(PersistenceFailure.openFailed(cause: e, stack: stack));
      return null;
    }
  }

  @override
  Future<void> putTorrentResumeData(String infoHash, Uint8List data) async {
    _resumeDataQueue.write(infoHash, data);
  }

  /// Flushes any pending debounced resume-data write. Call on shutdown.
  Future<void> dispose() => _resumeDataQueue.dispose();

  static DownloadRecord _fromRow(DownloadRecordRow row) => DownloadRecord(
        sourceKey: row.sourceKey,
        kind: SourceKind.values.byName(row.kind),
        filePath: row.filePath,
        totalBytes: row.totalBytes,
        validator: row.validator,
        lastUsedAt: DateTime.fromMillisecondsSinceEpoch(row.lastUsedAt, isUtc: true),
      );

  static Future<void> _writeResumeData(AppDatabase db, String infoHash, Uint8List data) {
    return db.into(db.torrentResume).insertOnConflictUpdate(
          TorrentResumeCompanion.insert(
            infoHash: infoHash,
            data: data,
            updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }
}

TransportStateRepository createTransportStateRepository(AppDatabase db, AppLogger logger) =>
    DriftTransportStateRepository(db, logger);
