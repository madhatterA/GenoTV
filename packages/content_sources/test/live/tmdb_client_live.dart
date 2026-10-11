import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live TMDB check. Reads the repo-root `.tmdb-token` (git-ignored v3 API
/// key) — never skips; fails loudly if the file is missing. Run from
/// `packages/content_sources`.
void main() {
  test('live trending, search, movie, tv and season lookups', () async {
    final client = TmdbClient(http: ProviderHttp());

    final trending = await client.trending(isTv: false);
    expect(trending.length, greaterThanOrEqualTo(10));
    for (final title in trending) {
      expect(title.title, isNotEmpty);
      expect(title.posterPath, isNotNull);
    }

    final search = await client.searchMulti('Inception');
    expect(search.any((t) => t.id == 27205 && !t.isTv), isTrue);

    final movie = await client.movie(27205);
    expect(movie.imdbId, 'tt1375666');
    expect(movie.year, 2010);

    final tv = await client.tv(1396);
    expect(tv.imdbId, 'tt0903747');
    expect(tv.seasons.any((s) => s.number == 2), isTrue);

    final season = await client.season(1396, 2);
    expect(season.episodes, hasLength(13));
    expect(
      season.episodes.firstWhere((e) => e.episodeNumber == 3).name,
      'Bit by a Dead Bee',
    );
  });
}
