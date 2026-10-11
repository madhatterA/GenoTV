import 'package:contracts/contracts.dart';

/// Minimal [SourceProvider] over a static list, so Part 04's tests have
/// something to browse. Part 07 owns the real `FixtureProvider`.
class FixtureProviderStub implements SourceProvider {
  FixtureProviderStub({List<MediaItem>? items}) : _items = items ?? _defaultItems();

  final List<MediaItem> _items;

  static List<MediaItem> _defaultItems() => const <MediaItem>[
        MediaItem(id: 'fixture-1', title: 'Fixture Movie', kind: MediaKind.movie),
        MediaItem(
          id: 'fixture-2',
          title: 'Fixture Episode',
          kind: MediaKind.episode,
          subtitle: 'S01E01',
        ),
      ];

  @override
  String get id => 'fixture';

  @override
  String get displayName => 'Fixture';

  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    final page = _items.skip(query.offset).take(query.limit).toList();
    return MediaPage(
      items: page,
      total: _items.length,
      hasMore: query.offset + page.length < _items.length,
    );
  }

  @override
  Future<MediaPage> search(String query, {int limit = 50}) async {
    final needle = query.toLowerCase();
    final matches =
        _items.where((item) => item.title.toLowerCase().contains(needle)).take(limit).toList();
    return MediaPage(items: matches, total: matches.length, hasMore: false);
  }

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async => const <SourceSpec>[];

  @override
  Future<void> dispose() async {}
}
