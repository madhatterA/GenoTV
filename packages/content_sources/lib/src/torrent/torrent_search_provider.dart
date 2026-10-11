// Aggregation ported from PlayTorrioV3 lib/services/scraper/stream_scraper.dart
// (`scrapeAll`) and lib/pages/player/watch_screen.dart (seeder floor, sort),
// commit 39b736f. GPL-3.0; see root README.md (Credits) and LICENSE.
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../content_source_failure.dart';
import 'release_text.dart' as text;
import 'torrent_result.dart';

typedef TorrentSearch = Future<List<TorrentResult>> Function(MediaItem item);

class TorrentSearchProvider implements SourceProvider {
  TorrentSearchProvider({required this.searches, required this.logger});

  final List<TorrentSearch> searches;
  final AppLogger logger;

  @override
  String get id => 'torrents';

  @override
  String get displayName => 'Torrents';

  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: const [], hasMore: false);

  @override
  Future<MediaPage> search(String query, {int limit = 50}) async =>
      MediaPage(items: const [], hasMore: false);

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    if (item.title.trim().isEmpty) throw const ContentSourceFailure.notFound();
    final outcomes = await Future.wait(
      searches.map((search) async {
        try {
          return (results: await search(item), error: null as Object?);
        } on Object catch (error, stack) {
          logger.warn('Torrent search failed', error: error, stack: stack);
          return (results: <TorrentResult>[], error: error);
        }
      }),
    );
    final failures = outcomes.where((o) => o.error != null).toList();
    if (failures.length == outcomes.length && failures.isNotEmpty) {
      throw failures.first.error!;
    }
    final seen = <String>{};
    final merged = <TorrentResult>[
      for (final outcome in outcomes)
        for (final result in outcome.results)
          if (result.seeders >= 1 && seen.add(result.infoHash)) result,
    ];
    // Stable sort: quality rank desc, then seeders desc.
    merged.sort((a, b) {
      final byQuality = text
          .qualityRank(b.releaseName)
          .compareTo(text.qualityRank(a.releaseName));
      return byQuality != 0 ? byQuality : b.seeders.compareTo(a.seeders);
    });
    return [for (final result in merged) result.toSourceSpec(item)];
  }

  @override
  Future<void> dispose() async {}
}
