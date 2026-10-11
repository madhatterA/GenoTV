import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'fs_native.dart';

const int _gib = 1024 * 1024 * 1024;

/// Auto limit: 30% of the cache volume's free space, no floor or ceiling.
int resolveCacheLimit(TransportOptions options, int freeBytes) =>
    options.cacheLimitBytes ?? freeBytes * 3 ~/ 10;

/// A cached item not played for this long is deleted.
const Duration cacheRetention = Duration(days: 7);

/// An open stream the budget accounts for.
abstract interface class CacheClient {
  /// Disk bytes this stream's data currently occupies.
  int get usedBytes;

  /// Eviction runs in steps of this size; the ahead window keeps that margin.
  int get batchBytes;
}

/// One thing in the cache directory that belongs to a closed stream.
class CacheEntry {
  CacheEntry(this.entity, this.records, this.lastUsed, this.bytes);
  final FileSystemEntity entity;
  final List<DownloadRecord> records;
  final DateTime lastUsed;
  final int bytes;
}

/// The size limit of the media cache directory and what is on it. The
/// directory may be shared with other files: only entries this transport
/// created are ever deleted (`*.partial`, `*.partial.aria2`, idle
/// `aria2-window-*`, and torrent paths named by a [DownloadRecord]).
class CacheBudget {
  CacheBudget({
    required this.dir,
    required this.fs,
    required this._logger,
    required this.state,
    required this.openNames,
    required this.openKeys,
  });

  final Directory dir;
  final FsNative fs;
  final TransportStateRepository? state;

  /// Top-level names under [dir] that belong to open streams.
  final Set<String> Function() openNames;
  final Set<String> Function() openKeys;
  final AppLogger _logger;
  final List<CacheClient> _clients = <CacheClient>[];
  int limit = 2 * _gib;
  int _roomAtUsed = 0;

  /// Granularity of eviction for a stream, within [maxBytes].
  int batchFor(int maxBytes) => (limit ~/ 32).clamp(1024 * 1024, maxBytes);

  /// Data behind the play head that is kept for a quick seek back.
  int get backWindow => limit ~/ 4;

  void register(CacheClient client) => _clients.add(client);
  void unregister(CacheClient client) => _clients.remove(client);

  int get openUsed => _clients.fold(0, (sum, c) => sum + c.usedBytes);

  /// Bytes [client] may download ahead of the play head. A file of [total]
  /// bytes that fits the limit (with the other open streams) is downloaded
  /// whole: the answer is then [total] and nothing is ever evicted.
  int aheadFor(CacheClient client, {int? total}) {
    final others = openUsed - client.usedBytes;
    if (total != null && total + others <= limit) return total;
    return math.max(0, limit - backWindow - client.batchBytes - others);
  }

  String? _top(String path) {
    final root = dir.path;
    return path.startsWith('$root/')
        ? path.substring(root.length + 1).split('/').first
        : null;
  }

  // A file deleted by its owner while the directory is scanned counts as 0.
  int _allocated(String path) {
    try {
      return fs.allocatedBytes(path);
    } on FsNativeException {
      if (File(path).existsSync()) rethrow;
      return 0;
    }
  }

  Future<int> _bytes(FileSystemEntity entity) async {
    if (entity is File) return _allocated(entity.path);
    if (entity is! Directory) return 0;
    var total = 0;
    await for (final child in entity.list(
      recursive: true,
      followLinks: false,
    )) {
      if (child is File) total += _allocated(child.path);
    }
    return total;
  }

  /// Everything owned by streams that are not open, oldest use first.
  Future<List<CacheEntry>> closedEntries() async {
    if (!await dir.exists()) return const <CacheEntry>[];
    final open = openNames();
    final keys = openKeys();
    final records = state == null
        ? const <DownloadRecord>[]
        : [
            for (final r in await state!.all())
              if (!keys.contains(r.sourceKey)) r,
          ];
    final byName = <String, List<DownloadRecord>>{};
    for (final r in records) {
      final top = r.filePath == null ? null : _top(r.filePath!);
      if (top != null) (byName[top] ??= <DownloadRecord>[]).add(r);
    }
    final entries = <CacheEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final ours =
          byName.containsKey(name) ||
          name.endsWith('.partial') ||
          name.endsWith('.partial.aria2') ||
          name.endsWith('.partial.evicted') ||
          name.startsWith('aria2-window-');
      if (!ours || open.contains(name) || open.contains('$name.aria2')) {
        continue;
      }
      final mine = byName[name] ?? const <DownloadRecord>[];
      final lastUsed = mine.isEmpty
          ? (await entity.stat()).modified.toUtc()
          : mine
                .map((r) => r.lastUsedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      entries.add(CacheEntry(entity, mine, lastUsed, await _bytes(entity)));
    }
    entries.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    return entries;
  }

  /// Deletes [entry] and its persisted state; returns the bytes freed.
  Future<int> remove(CacheEntry entry) async {
    final path = entry.entity.path;
    await _deleteIfPresent(entry.entity);
    if (path.endsWith('.partial')) {
      // Its control and eviction-marker files go with it.
      await _deleteIfPresent(File('$path.aria2'));
      await _deleteIfPresent(File('$path.evicted'));
    }
    for (final record in entry.records) {
      await forgetRecord(record);
    }
    return entry.bytes;
  }

  Future<void> _deleteIfPresent(FileSystemEntity entity) async {
    if (await entity.exists()) await entity.delete(recursive: true);
  }

  /// Drops the persisted state of a stream whose files are gone.
  Future<void> forgetRecord(DownloadRecord record) async {
    final repo = state;
    if (repo == null) return;
    // The repository has no torrent-resume delete; empty bytes mean "none".
    if (record.kind != SourceKind.httpUrl) {
      await repo.putTorrentResumeData(record.sourceKey, Uint8List(0));
    }
    await repo.delete(record.sourceKey);
  }

  /// Clear cache: removes every closed stream. Returns the bytes freed.
  Future<int> clear() async {
    var freed = 0;
    for (final entry in await closedEntries()) {
      freed += await remove(entry);
    }
    // Records whose files were already gone.
    final keys = openKeys();
    for (final record in await state?.all() ?? const <DownloadRecord>[]) {
      if (!keys.contains(record.sourceKey)) await forgetRecord(record);
    }
    return freed;
  }

  /// Deletes every closed entry last used more than [cacheRetention] ago.
  Future<void> expire({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(cacheRetention);
    for (final entry in await closedEntries()) {
      if (entry.lastUsed.isBefore(cutoff)) {
        _logger.info('Cache entry unused for 7 days, removing '
            '${entry.entity.path}');
        await remove(entry);
      }
    }
  }

  /// Keeps closed + open data under [limit] by removing closed streams, least
  /// recently used first. Runs only after the open data grew by a batch.
  Future<void> makeRoom({bool force = false}) async {
    final used = openUsed;
    if (!force && (used - _roomAtUsed).abs() < batchFor(16 * 1024 * 1024)) {
      return;
    }
    _roomAtUsed = used;
    final entries = await closedEntries();
    var excess = entries.fold<int>(0, (sum, e) => sum + e.bytes) + used - limit;
    for (final entry in entries) {
      if (excess <= 0) break;
      _logger.info('Cache over limit, removing ${entry.entity.path}');
      excess -= await remove(entry);
    }
  }
}
