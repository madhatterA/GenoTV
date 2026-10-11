import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live Breaking Bad S02E03 aggregate', () async {
    final http = ProviderHttp();
    final logger = MemoryLogger();
    final provider = TorrentSearchProvider(
      searches: [
        KnabenSearch(http: http).search,
        TorrentGalaxySearch(http: http, logger: logger).search,
      ],
      logger: logger,
    );
    final specs = await provider.resolve(
      const MediaItem(
        id: 'e',
        title: 'Breaking Bad',
        kind: MediaKind.episode,
        seasonNumber: 2,
        episodeNumber: 3,
      ),
    );
    http.close();
    expect(specs.length, greaterThanOrEqualTo(2));
    final hashes = specs.map(
      (s) => s.uri.toString().split('btih:')[1].split('&')[0],
    );
    expect(hashes.toSet(), hasLength(specs.length));
    expect(
      specs.every((s) => s.seasonNumber == 2 && s.episodeNumber == 3),
      isTrue,
    );
    int rank(SourceSpec s) => switch (s.quality) {
      '2160p' => 4,
      '1080p' => 3,
      '720p' => 2,
      '480p' => 1,
      _ => 0,
    };
    int seeds(SourceSpec s) => int.parse(
      s.label!
          .split('\n')
          .firstWhere((line) => line.startsWith('Seeders: '))
          .substring(9),
    );
    for (var i = 1; i < specs.length; i++) {
      final (a, b) = (specs[i - 1], specs[i]);
      expect(
        rank(a) > rank(b) || (rank(a) == rank(b) && seeds(a) >= seeds(b)),
        isTrue,
      );
    }
  });
}
