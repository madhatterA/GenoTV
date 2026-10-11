import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

/// Stream lists saved on disk per provider and title, so switching
/// providers or reopening a title does not load them again (owner
/// 2026-10-10). A list is kept 7 days, the media cache's retention; the
/// play-source Refresh button replaces it. Lists are a few KB, far under the
/// media cache's 30%-of-free-space limit, so only age expires them.
class SourceCache {
  SourceCache(this.dir, this._logger);

  static const Duration retention = Duration(days: 7);

  final Directory dir;
  final AppLogger _logger;

  File _file(String providerId, MediaItem item) => File(
    '${dir.path}${Platform.pathSeparator}'
    '${Uri.encodeComponent(providerId)}__${Uri.encodeComponent(item.id)}.json',
  );

  Future<List<SourceSpec>?> read(String providerId, MediaItem item) async {
    final file = _file(providerId, item);
    if (!await file.exists()) return null;
    if (DateTime.now().difference(await file.lastModified()) > retention) {
      await file.delete();
      return null;
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return [for (final entry in raw) _spec(entry as Map<String, dynamic>)];
    } on Object catch (error, stack) {
      // An unreadable file is a cache miss: delete it and load afresh.
      _logger.warn(
        'source cache: bad ${file.path}',
        error: error,
        stack: stack,
      );
      await file.delete();
      return null;
    }
  }

  Future<void> write(
    String providerId,
    MediaItem item,
    List<SourceSpec> specs,
  ) async {
    await dir.create(recursive: true);
    await _file(
      providerId,
      item,
    ).writeAsString(jsonEncode([for (final spec in specs) _json(spec)]));
  }

  Future<void> forget(String providerId, MediaItem item) async {
    final file = _file(providerId, item);
    if (await file.exists()) await file.delete();
  }

  /// Deletes every list older than [retention].
  Future<void> prune() async {
    if (!await dir.exists()) return;
    final now = DateTime.now();
    await for (final entity in dir.list()) {
      if (entity is File &&
          now.difference(await entity.lastModified()) > retention) {
        await entity.delete();
      }
    }
  }

  static Map<String, Object?> _json(SourceSpec spec) => <String, Object?>{
    'kind': spec.kind.name,
    'uri': spec.uri.toString(),
    'headers': spec.headers,
    'fileHint': spec.fileHint,
    'expectedBytes': spec.expectedBytes,
    'label': spec.label,
    'quality': spec.quality,
    'seasonNumber': spec.seasonNumber,
    'episodeNumber': spec.episodeNumber,
    'episodeTitle': spec.episodeTitle,
  };

  static SourceSpec _spec(Map<String, dynamic> json) => SourceSpec(
    kind: SourceKind.values.byName(json['kind'] as String),
    uri: Uri.parse(json['uri'] as String),
    headers: (json['headers'] as Map<String, dynamic>).cast<String, String>(),
    fileHint: json['fileHint'] as String?,
    expectedBytes: json['expectedBytes'] as int?,
    label: json['label'] as String?,
    quality: json['quality'] as String?,
    seasonNumber: json['seasonNumber'] as int?,
    episodeNumber: json['episodeNumber'] as int?,
    episodeTitle: json['episodeTitle'] as String?,
  );
}

/// [inner] with its stream lists served from [cache] when saved.
class CachedSourceProvider implements SourceProvider {
  CachedSourceProvider(this.inner, this.cache);

  final SourceProvider inner;
  final SourceCache cache;

  @override
  String get id => inner.id;
  @override
  String get displayName => inner.displayName;
  @override
  Future<MediaPage> browse(BrowseQuery query) => inner.browse(query);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) =>
      inner.search(query, limit: limit);

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    final saved = await cache.read(id, item);
    if (saved != null) return saved;
    final specs = await inner.resolve(item);
    await cache.write(id, item, specs);
    return specs;
  }

  @override
  Future<void> dispose() => inner.dispose();
}
