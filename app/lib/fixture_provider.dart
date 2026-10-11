import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';

/// Part 07's temporary provider. Part 06 is intentionally empty, so this
/// keeps a deterministic catalogue and one source for every source kind.
final class FixtureProvider implements SourceProvider {
  FixtureProvider({Directory? fixtureDirectory})
    : _items = const [
        MediaItem(
          id: 'fixture-movie',
          title: 'Fixture Movie',
          kind: MediaKind.movie,
          subtitle: 'Local sample',
        ),
        MediaItem(
          id: 'fixture-episode',
          title: 'Fixture Episode',
          kind: MediaKind.episode,
          subtitle: 'S01E01',
        ),
        MediaItem(
          id: 'fixture-series-episode',
          title: 'Fixture Series Episode',
          kind: MediaKind.episode,
          subtitle: 'S02E04',
        ),
        MediaItem(
          id: 'fixture-other',
          title: 'Fixture Extra',
          kind: MediaKind.other,
        ),
      ],
      _sources = _buildSources(fixtureDirectory);

  static Future<FixtureProvider> create({Directory? fixtureDirectory}) async {
    if (fixtureDirectory != null) {
      await _materializeFixture(fixtureDirectory, 'Butterfly-209.mp4');
    }
    return FixtureProvider(fixtureDirectory: fixtureDirectory);
  }

  final List<MediaItem> _items;
  final Map<String, List<SourceSpec>> _sources;

  static Map<String, List<SourceSpec>> _buildSources(
    Directory? fixtureDirectory,
  ) {
    final fixture = _fixtureFile(fixtureDirectory, 'Butterfly-209.mp4');
    return <String, List<SourceSpec>>{
      'fixture-movie': [
        SourceSpec(kind: SourceKind.localFile, uri: Uri.file(fixture)),
      ],
      'fixture-episode': [
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('http://127.0.0.1:8765/Butterfly-209.mp4'),
        ),
      ],
      'fixture-series-episode': [
        SourceSpec(
          kind: SourceKind.torrentMagnet,
          uri: Uri.parse(
            'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
          ),
        ),
      ],
      'fixture-other': [
        SourceSpec(
          kind: SourceKind.torrentFile,
          uri: Uri.parse('file:///fixtures/sample.torrent'),
        ),
      ],
    };
  }

  static String _fixtureFile(Directory? requested, String name) {
    final roots = <Directory>[];
    if (requested != null) {
      final cached = File('${requested.path}/$name');
      if (cached.existsSync()) return cached.path;
      roots.add(requested);
    }
    void addAncestors(Directory start) {
      var current = start.absolute;
      for (var index = 0; index < 10; index++) {
        roots.add(current);
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }

    addAncestors(Directory.current);
    addAncestors(File(Platform.resolvedExecutable).absolute.parent);
    for (final root in roots) {
      final candidate = File(
        '${root.path}/packages/playback/test/fixtures/$name',
      );
      if (candidate.existsSync()) return candidate.path;
      final packageRoot = File('${root.path}/test/fixtures/$name');
      if (packageRoot.existsSync()) return packageRoot.path;
    }
    return '/fixtures/$name';
  }

  static Future<void> _materializeFixture(
    Directory destination,
    String name,
  ) async {
    final target = File('${destination.path}/$name');
    if (target.existsSync() && await target.length() > 0) return;
    await destination.create(recursive: true);
    final asset = await rootBundle.load('assets/$name');
    await target.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      flush: true,
    );
  }

  @override
  String get id => 'fixture';

  @override
  String get displayName => 'Fixture catalogue';

  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    final items = _items.skip(query.offset).take(query.limit).toList();
    return MediaPage(
      items: items,
      total: _items.length,
      hasMore: query.offset + items.length < _items.length,
    );
  }

  @override
  Future<MediaPage> search(String query, {int limit = 50}) async {
    final needle = query.toLowerCase();
    final items = _items
        .where((item) => item.title.toLowerCase().contains(needle))
        .take(limit)
        .toList();
    return MediaPage(items: items, total: items.length, hasMore: false);
  }

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async =>
      List<SourceSpec>.unmodifiable(_sources[item.id] ?? const []);

  @override
  Future<void> dispose() async {}
}
