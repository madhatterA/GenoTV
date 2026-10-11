import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

/// Maps the UI's query to the content-source API at the app boundary.
Future<TitlePage> loadTmdbTitlePage(
  TmdbCatalogue catalogue,
  TitleQuery query,
  int page,
) async {
  final result = await catalogue.client.titlePage(
    isTv: query.kind == TitleKind.tv,
    page: page,
    genreIds: query.genreIds,
    keywordIds: query.keywordIds,
    trending: query.base == TitleBase.trending,
    countryCode: query.countryCode,
    yearFrom: query.yearFrom,
    yearTo: query.yearTo,
    sort: query.sort.name,
    personId: query.base == TitleBase.person ? query.personId : null,
    crew: query.personRole == TitlePersonRole.crew,
    searchText: query.base == TitleBase.search ? query.searchText : null,
  );
  final items = result.items.map(catalogue.titleItem).toList();
  return TitlePage(
    items: items,
    nextPage: result.nextPage,
    metadata: {
      for (var index = 0; index < items.length; index++)
        items[index].id: TitleMetadata(
          popularity: result.items[index].popularity,
          rating: result.items[index].rating,
          voteCount: result.items[index].voteCount,
          releaseDate: DateTime.tryParse(result.items[index].releaseDate ?? ''),
          genreIds: result.items[index].genreIds,
          countryCodes: result.items[index].originCountries,
        ),
    },
  );
}

final _tmdbTitleId = RegExp(r'^tmdb:(movie|tv):(\d+)(?::s\d+e\d+)?$');

/// Resolves stored media ids (favourites, watch history; episodes map to
/// their series) to poster-art catalogue items, in order, each title once.
/// Ids that are not catalogue titles (pasted links) are skipped.
Future<List<MediaItem>> loadTmdbTitles(
  TmdbCatalogue catalogue,
  Iterable<String> mediaIds, {
  AppLogger? logger,
}) async {
  final ids = <String>{};
  for (final id in mediaIds) {
    final match = _tmdbTitleId.firstMatch(id);
    if (match == null) {
      logger?.info(
        'Stored title has no catalogue metadata',
        data: {'mediaId': id},
      );
      continue;
    }
    ids.add('tmdb:${match.group(1)}:${match.group(2)}');
  }
  return Future.wait(
    ids.map((id) async {
      final movie = id.startsWith('tmdb:movie:');
      final details = await catalogue.details(
        MediaItem(
          id: id,
          title: id,
          kind: movie ? MediaKind.movie : MediaKind.episode,
        ),
      );
      final item = details.item;
      return MediaItem(
        id: item.id,
        title: item.title,
        kind: item.kind,
        artwork: details.poster ?? item.artwork,
        year: item.year,
        tmdbId: item.tmdbId,
      );
    }),
  );
}
