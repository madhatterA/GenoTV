import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live chain: search -> details -> seasons -> episodes, against real TMDB.
/// Reads the repo-root `.tmdb-token`; never skips.
void main() {
  test('live search to provider-ready episode item', () async {
    final catalogue = TmdbCatalogue(client: TmdbClient(http: ProviderHttp()));

    final movieSearch = await catalogue.search('Inception');
    final movieHit = movieSearch.items.firstWhere(
      (i) => i.id == 'tmdb:movie:27205',
    );
    expect(movieHit.kind, MediaKind.movie);

    final movieDetails = await catalogue.details(movieHit);
    expect(movieDetails.item.imdbId, 'tt1375666');
    expect(movieDetails.item.year, 2010);
    expect(movieDetails.item.tmdbId, 27205);

    final showSearch = await catalogue.search('Breaking Bad');
    final show = showSearch.items.firstWhere((i) => i.id == 'tmdb:tv:1396');
    expect(show.kind, MediaKind.episode);
    expect(show.seasonNumber, isNull);

    final seasons = await catalogue.seasons(show);
    expect(seasons.first.number, 1);

    final episodes = await catalogue.episodes(show, 2);
    final expected = MediaItem(
      id: 'tmdb:tv:1396:s2e3',
      title: 'Breaking Bad',
      kind: MediaKind.episode,
      duration: const Duration(minutes: 47),
      artwork: Uri.parse(
        'https://image.tmdb.org/t/p/w780/abgJTOWYPdZGxAWhsg6lmtM8qcU.jpg',
      ),
      subtitle: 'S02E03 · Bit by a Dead Bee',
      imdbId: 'tt0903747',
      tmdbId: 1396,
      year: 2008,
      seasonNumber: 2,
      episodeNumber: 3,
      originalLanguage: 'en',
    );
    expect(episodes[2], expected);
  });
}
