import 'package:contracts/contracts.dart';

import '../omdb_ratings.dart';
import 'tmdb_client.dart';
import 'tmdb_records.dart';

const _tmdbPageSize = 20;
final _episodeIdPattern = RegExp(r'^tmdb:tv:(\d+):s(\d+)e(\d+)$');
final _titleIdPattern = RegExp(r'^tmdb:(movie|tv):(\d+)$');

/// `details()` result: the enriched [item] plus display-only fields no
/// `MediaItem` field covers.
final class TmdbDetails {
  const TmdbDetails({
    required this.item,
    this.overview,
    this.originalLanguage,
    this.tagline,
    this.genres = const [],
    this.ratings = const TitleRatings(),
    this.genreIds = const [],
    this.keywords = const [],
    this.countries = const [],
    this.people = const [],
    this.backdrop,
    this.poster,
  });

  final MediaItem item;
  final String? overview;
  final String? originalLanguage;
  final String? tagline;
  final List<String> genres;
  final TitleRatings ratings;
  final List<TmdbNamedId> genreIds;
  final List<TmdbNamedId> keywords;
  final List<TmdbCountry> countries;
  final List<TmdbPerson> people;
  final Uri? backdrop;

  /// The 2:3 poster the lists show (the item itself carries the backdrop).
  final Uri? poster;
}

/// TMDB-backed [SourceProvider]: browse/search a catalogue of movies and TV
/// shows. Carries no streams of its own — `resolve` is always empty; the
/// link providers (thirtynama, digimoviez, ...) resolve playable sources.
class TmdbCatalogue implements SourceProvider {
  TmdbCatalogue({required this.client, this.omdb});

  final TmdbClient client;

  /// Optional IMDb/Rotten Tomatoes source; without it details carry no ratings.
  final OmdbRatings? omdb;

  @override
  String get id => 'tmdb';
  @override
  String get displayName => 'TMDB';

  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    final isTv = query.kind == MediaKind.episode;
    final sort = query.sort ?? 'trending';
    final firstPage = query.offset ~/ _tmdbPageSize + 1;
    final skip = query.offset % _tmdbPageSize;

    final collected = <TmdbTitle>[];
    var page = firstPage;
    var totalPages = firstPage;
    for (var requests = 0; requests < 3; requests++) {
      final (titles, total) = await _fetchSortedPage(sort, isTv, page);
      collected.addAll(titles);
      totalPages = total;
      if (collected.length - skip >= query.limit) break;
      if (page >= totalPages) break;
      page++;
    }

    final visible = collected.skip(skip).take(query.limit).toList();
    final buffered = collected.length - skip > visible.length;
    final morePages = page < totalPages;
    return MediaPage(
      items: [for (final t in visible) _titleItem(t)],
      total: null,
      hasMore: buffered || morePages,
    );
  }

  Future<(List<TmdbTitle>, int)> _fetchSortedPage(
    String sort,
    bool isTv,
    int page,
  ) => switch (sort) {
    'popular' => client.popularWithTotal(isTv: isTv, page: page),
    'top_rated' => client.topRatedWithTotal(isTv: isTv, page: page),
    _ => client.trendingWithTotal(isTv: isTv, page: page),
  };

  @override
  Future<MediaPage> search(String query, {int limit = 50}) async {
    if (query.trim().isEmpty) {
      return MediaPage(items: const [], total: 0, hasMore: false);
    }
    final results = await client.searchMulti(query);
    final items = results.take(limit).map(_titleItem).toList();
    return MediaPage(items: items, total: null, hasMore: false);
  }

  /// Wide backdrop picture by item id for every title listed so far; the
  /// home hero shows these instead of the small poster.
  final Map<String, Uri> backdrops = <String, Uri>{};

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async => const [];

  /// Enriches a movie or show item with `imdbId`/`year`/`duration` and
  /// returns the display-only fields alongside.
  Future<TmdbDetails> details(MediaItem item) async {
    final match = _titleIdPattern.firstMatch(item.id);
    if (match == null) {
      throw ArgumentError.value(item.id, 'item.id', 'not a TMDB movie/tv id');
    }
    final tmdbId = int.parse(match.group(2)!);
    if (match.group(1) == 'movie') {
      final movie = await client.movie(tmdbId);
      return TmdbDetails(
        item: MediaItem(
          id: item.id,
          title: movie.title,
          kind: MediaKind.movie,
          duration: movie.runtimeMinutes == null
              ? null
              : Duration(minutes: movie.runtimeMinutes!),
          artwork: _image(movie.backdropPath, 'original') ?? item.artwork,
          subtitle: item.subtitle,
          imdbId: movie.imdbId,
          tmdbId: tmdbId,
          year: movie.year,
          originalLanguage: movie.originalLanguage,
        ),
        overview: movie.overview,
        originalLanguage: movie.originalLanguage,
        tagline: movie.tagline,
        genres: movie.genres,
        ratings: await _ratings(movie.imdbId, movie.voteAverage),
        genreIds: movie.genreIds,
        keywords: movie.keywords,
        countries: movie.countries,
        people: movie.people,
        backdrop: _image(movie.backdropPath, 'original'),
        poster: _image(movie.posterPath, 'w500'),
      );
    }
    final tv = await client.tv(tmdbId);
    return TmdbDetails(
      item: MediaItem(
        id: item.id,
        title: tv.title,
        kind: MediaKind.episode,
        artwork: _image(tv.backdropPath, 'original') ?? item.artwork,
        subtitle: item.subtitle,
        imdbId: tv.imdbId,
        tmdbId: tmdbId,
        year: tv.year,
        originalLanguage: tv.originalLanguage,
        duration: tv.runtimeMinutes == null
            ? null
            : Duration(minutes: tv.runtimeMinutes!),
      ),
      overview: tv.overview,
      originalLanguage: tv.originalLanguage,
      genres: tv.genres,
      ratings: await _ratings(tv.imdbId, tv.voteAverage),
      genreIds: tv.genreIds,
      keywords: tv.keywords,
      countries: tv.countries,
      people: tv.people,
      backdrop: _image(tv.backdropPath, 'original'),
      poster: _image(tv.posterPath, 'w500'),
    );
  }

  /// OMDb first; TMDB's vote average only when OMDb has no score at all.
  Future<TitleRatings> _ratings(String? imdbId, double? vote) async {
    final fromOmdb = imdbId == null || omdb == null
        ? const TitleRatings()
        : await omdb!.ratings(imdbId);
    if (!fromOmdb.isEmpty || vote == null || vote <= 0) return fromOmdb;
    return TitleRatings(tmdb: vote.toStringAsFixed(1));
  }

  /// Seasons for a show item, season 0 ("Specials") removed, ascending.
  Future<List<TmdbSeasonSummary>> seasons(MediaItem show) async {
    final tmdbId = show.tmdbId ?? _tvIdOf(show.id);
    final tv = await client.tv(tmdbId);
    final kept = tv.seasons.where((s) => s.number != 0).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return kept;
  }

  /// Provider-ready episode items for one season of [show], per P6-D6: show
  /// title/imdbId/tmdbId/year, both season and episode numbers set, subtitle
  /// `"S%02dE%02d · <name>"`. Requires `show.imdbId`; when it is still null
  /// this calls `details` first, and if TMDB has none the items carry
  /// `imdbId: null` (the link providers then answer `not_found`).
  Future<List<MediaItem>> episodes(MediaItem show, int seasonNumber) async {
    final tmdbId = show.tmdbId ?? _tvIdOf(show.id);
    var resolvedShow = show;
    if (resolvedShow.imdbId == null ||
        resolvedShow.tmdbId == null ||
        resolvedShow.originalLanguage == null) {
      resolvedShow = (await details(show)).item;
    }
    final season = await client.season(tmdbId, seasonNumber);
    return [
      for (final e in season.episodes)
        MediaItem(
          id: 'tmdb:tv:$tmdbId:s${e.seasonNumber}e${e.episodeNumber}',
          title: resolvedShow.title,
          kind: MediaKind.episode,
          duration: e.runtimeMinutes == null
              ? null
              : Duration(minutes: e.runtimeMinutes!),
          artwork: _image(e.stillPath, 'w780'),
          subtitle:
              'S${e.seasonNumber.toString().padLeft(2, '0')}'
              'E${e.episodeNumber.toString().padLeft(2, '0')} · ${e.name}',
          imdbId: resolvedShow.imdbId,
          tmdbId: tmdbId,
          year: resolvedShow.year,
          originalLanguage: resolvedShow.originalLanguage,
          seasonNumber: e.seasonNumber,
          episodeNumber: e.episodeNumber,
        ),
    ];
  }

  @override
  Future<void> dispose() async {}

  MediaItem _titleItem(TmdbTitle t) {
    final item = _titleItemOf(t);
    if (_image(t.backdropPath, 'original') case final backdrop?) {
      backdrops[item.id] = backdrop;
    }
    return item;
  }

  /// Maps a paged TMDB title through the catalogue's standard artwork/id path.
  MediaItem titleItem(TmdbTitle title) => _titleItem(title);

  MediaItem _titleItemOf(TmdbTitle t) => MediaItem(
    id: t.isTv ? 'tmdb:tv:${t.id}' : 'tmdb:movie:${t.id}',
    title: t.title,
    kind: t.isTv ? MediaKind.episode : MediaKind.movie,
    artwork: _image(t.posterPath, 'w500'),
    tmdbId: t.id,
    year: t.year,
  );

  Uri? _image(String? path, String size) => (path == null || path.isEmpty)
      ? null
      : Uri.parse('https://image.tmdb.org/t/p/$size$path');

  int _tvIdOf(String itemId) {
    final episode = _episodeIdPattern.firstMatch(itemId);
    if (episode != null) return int.parse(episode.group(1)!);
    final title = _titleIdPattern.firstMatch(itemId);
    if (title != null) return int.parse(title.group(2)!);
    throw ArgumentError.value(itemId, 'itemId', 'not a TMDB tv id');
  }
}
