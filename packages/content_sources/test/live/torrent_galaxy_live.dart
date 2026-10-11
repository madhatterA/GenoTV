import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final search = TorrentGalaxySearch(
    http: ProviderHttp(),
    logger: MemoryLogger(),
  );

  test('live Inception movie', () async {
    final results = await search.search(
      const MediaItem(
        id: 'm',
        title: 'Inception',
        kind: MediaKind.movie,
        year: 2010,
      ),
    );
    expect(results, isNotEmpty);
    for (final r in results) {
      expect(r.infoHash, matches(RegExp(r'^[0-9a-f]{40}$')));
      // ignore: avoid_print
      print('movie ${r.infoHash} seeders=${r.seeders} ${r.releaseName}');
    }
  });

  test('live Breaking Bad S02E03', () async {
    final results = await search.search(
      const MediaItem(
        id: 'e',
        title: 'Breaking Bad',
        kind: MediaKind.episode,
        seasonNumber: 2,
        episodeNumber: 3,
      ),
    );
    expect(results, isNotEmpty);
    for (final r in results) {
      expect(
        RegExp(
          r'S02E03|S02(?!E)|Season 2',
          caseSensitive: false,
        ).hasMatch(r.releaseName),
        isTrue,
        reason: r.releaseName,
      );
      // ignore: avoid_print
      print('episode ${r.infoHash} seeders=${r.seeders} ${r.releaseName}');
    }
  });
}
