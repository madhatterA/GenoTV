import 'dart:typed_data';

import 'package:contracts/contracts.dart';

import 'src/replay_latest_broadcast.dart';

/// In-memory [ProgressRepository]. Holds the same shape Chapter 04's drift
/// implementation will be held to by `runRepositoryContractTests`.
class FakeProgressRepository implements ProgressRepository {
  final Map<String, PlaybackProgress> _byMediaId = {};
  final Map<String, ReplayLatestBroadcast<PlaybackProgress>> _watchers = {};

  ReplayLatestBroadcast<PlaybackProgress> _watcherFor(String mediaId) =>
      _watchers.putIfAbsent(
        mediaId,
        ReplayLatestBroadcast<PlaybackProgress>.new,
      );

  @override
  Future<PlaybackProgress?> get(String mediaId) async => _byMediaId[mediaId];

  @override
  Future<void> upsert(PlaybackProgress progress) async {
    _byMediaId[progress.mediaId] = progress;
    _watcherFor(progress.mediaId).add(progress);
  }

  @override
  Future<List<PlaybackProgress>> continueWatching({int limit = 20}) async {
    final items = _byMediaId.values.where((p) => !p.completed).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(limit).toList();
  }

  @override
  Future<List<PlaybackProgress>> history({int limit = 20}) async {
    final items = _byMediaId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(limit).toList();
  }

  @override
  Future<void> clear(String mediaId) async => _byMediaId.remove(mediaId);

  @override
  Stream<PlaybackProgress> watch(String mediaId) => _watcherFor(mediaId).stream;
}

/// In-memory [FavouritesRepository].
class FakeFavouritesRepository implements FavouritesRepository {
  FakeFavouritesRepository() {
    _watcher.add(const <String>[]);
  }

  final Set<String> _favourites = {};
  final ReplayLatestBroadcast<List<String>> _watcher =
      ReplayLatestBroadcast<List<String>>();

  @override
  Future<bool> isFavourite(String mediaId) async =>
      _favourites.contains(mediaId);

  @override
  Future<void> setFavourite(String mediaId, bool value) async {
    if (value) {
      _favourites.add(mediaId);
    } else {
      _favourites.remove(mediaId);
    }
    _watcher.add(List.unmodifiable(_favourites));
  }

  @override
  Future<List<String>> all() async => List.unmodifiable(_favourites);

  @override
  Stream<List<String>> watchAll() => _watcher.stream;
}

/// In-memory [NextUpRepository].
class FakeNextUpRepository implements NextUpRepository {
  final Map<String, NextUpEntry> _bySeriesId = {};

  @override
  Future<NextUpEntry?> forSeries(String seriesId) async =>
      _bySeriesId[seriesId];

  @override
  Future<void> set(NextUpEntry entry) async =>
      _bySeriesId[entry.seriesId] = entry;

  @override
  Future<void> clear(String seriesId) async => _bySeriesId.remove(seriesId);
}

/// In-memory [TransportStateRepository].
class FakeTransportStateRepository implements TransportStateRepository {
  final Map<String, DownloadRecord> _bySourceKey = {};
  final Map<String, Uint8List> _resumeData = {};

  @override
  Future<DownloadRecord?> get(String sourceKey) async =>
      _bySourceKey[sourceKey];

  @override
  Future<void> upsert(DownloadRecord record) async =>
      _bySourceKey[record.sourceKey] = record;

  @override
  Future<List<DownloadRecord>> all() async => _bySourceKey.values.toList();

  @override
  Future<void> delete(String sourceKey) async => _bySourceKey.remove(sourceKey);

  @override
  Future<Uint8List?> torrentResumeData(String infoHash) async =>
      _resumeData[infoHash];

  @override
  Future<void> putTorrentResumeData(String infoHash, Uint8List data) async =>
      _resumeData[infoHash] = data;
}
