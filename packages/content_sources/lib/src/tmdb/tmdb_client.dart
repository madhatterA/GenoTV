import '../content_source_failure.dart';
import '../provider_http.dart';
import 'tmdb_records.dart';

/// TMDB v3 client. No key in the app: [http] routes api.themoviedb.org to
/// the backup proxy, which adds it (BACKUP_PROXY.md, owner 2026-10-10).
class TmdbClient {
  TmdbClient({required this.http, Uri? baseUrl})
    : baseUrl = baseUrl ?? Uri.parse('https://api.themoviedb.org/3');

  final ProviderHttp http;
  final Uri baseUrl;

  Future<List<TmdbTitle>> trending({required bool isTv, int page = 1}) =>
      _titlesPage('/trending/${isTv ? 'tv' : 'movie'}/week', isTv, page);

  Future<List<TmdbTitle>> popular({required bool isTv, int page = 1}) =>
      _titlesPage('/${isTv ? 'tv' : 'movie'}/popular', isTv, page);

  Future<List<TmdbTitle>> topRated({required bool isTv, int page = 1}) =>
      _titlesPage('/${isTv ? 'tv' : 'movie'}/top_rated', isTv, page);

  Future<List<TmdbTitle>> searchMulti(String query, {int page = 1}) async {
    final json = await _get('/search/multi', {
      'query': query,
      'page': '$page',
      'include_adult': 'false',
    });
    final results = (json['results'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      for (final r in results)
        if (r['media_type'] == 'movie' || r['media_type'] == 'tv')
          _title(r, r['media_type'] == 'tv'),
    ];
  }

  final _tvCredits = <int, Map<String, dynamic>>{};
  final _genres = <bool, List<TmdbNamedId>>{};

  Future<List<TmdbNamedId>> genres({required bool isTv}) async {
    final cached = _genres[isTv];
    if (cached != null) return cached;
    final json = await _get('/genre/${isTv ? 'tv' : 'movie'}/list', {});
    final result = List<TmdbNamedId>.unmodifiable(_namedIds(json['genres']));
    _genres[isTv] = result;
    return result;
  }

  Future<List<TmdbCountry>> countries() async => const [
    TmdbCountry('AR', 'Argentina'),
    TmdbCountry('AU', 'Australia'),
    TmdbCountry('AT', 'Austria'),
    TmdbCountry('BE', 'Belgium'),
    TmdbCountry('BR', 'Brazil'),
    TmdbCountry('CA', 'Canada'),
    TmdbCountry('CN', 'China'),
    TmdbCountry('DK', 'Denmark'),
    TmdbCountry('EG', 'Egypt'),
    TmdbCountry('FI', 'Finland'),
    TmdbCountry('FR', 'France'),
    TmdbCountry('DE', 'Germany'),
    TmdbCountry('HK', 'Hong Kong'),
    TmdbCountry('IN', 'India'),
    TmdbCountry('IR', 'Iran'),
    TmdbCountry('IE', 'Ireland'),
    TmdbCountry('IL', 'Israel'),
    TmdbCountry('IT', 'Italy'),
    TmdbCountry('JP', 'Japan'),
    TmdbCountry('MX', 'Mexico'),
    TmdbCountry('NL', 'Netherlands'),
    TmdbCountry('NZ', 'New Zealand'),
    TmdbCountry('NG', 'Nigeria'),
    TmdbCountry('NO', 'Norway'),
    TmdbCountry('PL', 'Poland'),
    TmdbCountry('RU', 'Russia'),
    TmdbCountry('ZA', 'South Africa'),
    TmdbCountry('KR', 'South Korea'),
    TmdbCountry('ES', 'Spain'),
    TmdbCountry('SE', 'Sweden'),
    TmdbCountry('CH', 'Switzerland'),
    TmdbCountry('TW', 'Taiwan'),
    TmdbCountry('TH', 'Thailand'),
    TmdbCountry('TR', 'Turkey'),
    TmdbCountry('GB', 'United Kingdom'),
    TmdbCountry('US', 'United States'),
  ];

  /// Discover uses server filters. Search filters each page locally, skipping
  /// empty pages; TV person credits are cached and paged locally per owner ruling.
  Future<TmdbTitlePage> titlePage({
    required bool isTv,
    int page = 1,
    List<int> genreIds = const [],
    String? countryCode,
    int? yearFrom,
    int? yearTo,
    String sort = 'popularity',
    int? personId,
    bool crew = false,
    String? searchText,
    bool trending = false,
    List<int> keywordIds = const [],
  }) async {
    if (page < 1 || page > 500) throw ArgumentError.value(page, 'page');
    if (!const {
      'popularity',
      'rating',
      'releaseDate',
      'title',
    }.contains(sort)) {
      throw ArgumentError.value(sort, 'sort');
    }
    if ((personId != null && searchText != null) ||
        (trending && (personId != null || searchText != null))) {
      throw ArgumentError('Person and search bases are mutually exclusive');
    }
    bool matches(TmdbTitle t) =>
        genreIds.every(t.genreIds.contains) &&
        (countryCode == null || t.originCountries.contains(countryCode)) &&
        (yearFrom == null || (t.year != null && t.year! >= yearFrom)) &&
        (yearTo == null || (t.year != null && t.year! <= yearTo));

    if (isTv && personId != null) {
      var json = _tvCredits[personId];
      if (json == null) {
        json = await _get('/person/$personId/tv_credits', {});
        _tvCredits[personId] = json;
      }
      final seen = <int>{};
      final titles = [
        for (final row
            in (json[crew ? 'crew' : 'cast'] as List? ?? const [])
                .whereType<Map>())
          _title(row.map((k, v) => MapEntry('$k', v)), true),
      ].where((t) => seen.add(t.id) && matches(t)).toList();
      titles.sort((a, b) {
        final comparison = switch (sort) {
          'rating' => b.rating.compareTo(a.rating),
          'releaseDate' => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''),
          'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          _ => b.popularity.compareTo(a.popularity),
        };
        return comparison == 0 ? a.id.compareTo(b.id) : comparison;
      });
      final offset = (page - 1) * 20;
      return TmdbTitlePage(
        items: List.unmodifiable(titles.skip(offset).take(20)),
        nextPage: offset + 20 < titles.length && page < 500 ? page + 1 : null,
      );
    }

    final local = searchText != null || trending;
    final kind = isTv ? 'tv' : 'movie';
    final date = isTv ? 'first_air_date' : 'primary_release_date';
    var current = page;
    while (true) {
      final json = await _get(
        trending
            ? '/trending/$kind/week'
            : searchText == null
            ? '/discover/$kind'
            : '/search/$kind',
        {
          'page': '$current',
          'include_adult': 'false',
          'query': ?searchText,
          if (!local) ...{
            if (genreIds.isNotEmpty) 'with_genres': genreIds.join(','),
            if (keywordIds.isNotEmpty) 'with_keywords': keywordIds.join(','),
            'with_origin_country': ?countryCode,
            if (yearFrom != null) '$date.gte': '$yearFrom-01-01',
            if (yearTo != null) '$date.lte': '$yearTo-12-31',
            if (personId != null) crew ? 'with_crew' : 'with_cast': '$personId',
            'sort_by': switch (sort) {
              'rating' => 'vote_average.desc',
              'releaseDate' => '$date.desc',
              'title' => isTv ? 'name.asc' : 'title.asc',
              _ => 'popularity.desc',
            },
            if (sort == 'rating') 'vote_count.gte': '200',
          },
        },
      );
      final total = (json['total_pages'] as num?)?.toInt() ?? 1;
      final next = current < total && current < 500 ? current + 1 : null;
      final titles = <TmdbTitle>[];
      for (final raw
          in (json['results'] as List? ?? const []).whereType<Map>()) {
        var row = raw.map((k, v) => MapEntry('$k', v));
        if (local &&
            !isTv &&
            countryCode != null &&
            row['origin_country'] == null) {
          final details = await _get('/movie/${row['id']}', {});
          row = {...row, 'origin_country': details['origin_country']};
        }
        final title = _title(row, isTv);
        if (!local || matches(title)) titles.add(title);
      }
      if (!local || titles.isNotEmpty || next == null) {
        return TmdbTitlePage(items: List.unmodifiable(titles), nextPage: next);
      }
      current = next;
    }
  }

  /// A person's movies and shows (cast roles plus directing credits), most
  /// popular first, each title once. `/person/{id}/combined_credits`.

  /// Counts unique credits for the role used to open the person page.
  Future<({int movies, int tv})> personCreditCounts(
    int personId, {
    bool crew = false,
  }) async {
    final json = await _get('/person/$personId/combined_credits', {});
    final rows = (json[crew ? 'crew' : 'cast'] as List? ?? const [])
        .whereType<Map>();
    Set<int> ids(String kind) => {
      for (final row in rows)
        if (row['media_type'] == kind && row['id'] is num)
          (row['id'] as num).toInt(),
    };
    return (movies: ids('movie').length, tv: ids('tv').length);
  }

  Future<TmdbMovieDetails> movie(int id) async {
    final json = await _get('/movie/$id', {
      'append_to_response': 'external_ids,credits,keywords',
    });
    return TmdbMovieDetails(
      id: id,
      title: json['title']?.toString() ?? '',
      year: tmdbYearOf(json['release_date']?.toString()),
      posterPath: json['poster_path']?.toString(),
      backdropPath: json['backdrop_path']?.toString(),
      overview: json['overview']?.toString(),
      originalLanguage: json['original_language'] as String?,
      imdbId: _imdbId(json),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      runtimeMinutes: (json['runtime'] as num?)?.toInt(),
      genres: _genreNames(json),
      genreIds: _namedIds(json['genres']),
      keywords: _namedIds((json['keywords'] as Map?)?['keywords']),
      countries: (json['production_countries'] as List? ?? const [])
          .whereType<Map>()
          .where((c) => c['iso_3166_1'] != null)
          .map(
            (c) => TmdbCountry(
              c['iso_3166_1'].toString(),
              c['name']?.toString() ?? c['iso_3166_1'].toString(),
            ),
          )
          .toList(),
      people: _people(json),
      tagline: (json['tagline']?.toString().isEmpty ?? true)
          ? null
          : json['tagline'].toString(),
    );
  }

  Future<TmdbTvDetails> tv(int id) async {
    final json = await _get('/tv/$id', {
      'append_to_response': 'external_ids,credits,keywords',
    });
    final seasons = (json['seasons'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (s) => TmdbSeasonSummary(
            number: (s['season_number'] as num).toInt(),
            name: s['name']?.toString() ?? '',
            episodeCount: (s['episode_count'] as num?)?.toInt() ?? 0,
            posterPath: s['poster_path']?.toString(),
          ),
        )
        .toList();
    return TmdbTvDetails(
      id: id,
      title: json['name']?.toString() ?? '',
      year: tmdbYearOf(json['first_air_date']?.toString()),
      posterPath: json['poster_path']?.toString(),
      backdropPath: json['backdrop_path']?.toString(),
      overview: json['overview']?.toString(),
      originalLanguage: json['original_language'] as String?,
      imdbId: _imdbId(json),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      genres: _genreNames(json),
      genreIds: _namedIds(json['genres']),
      keywords: _namedIds((json['keywords'] as Map?)?['results']),
      countries: (json['origin_country'] as List? ?? const []).map((c) {
        final countries = (json['production_countries'] as List? ?? const [])
            .whereType<Map>();
        final match = countries.where((p) => p['iso_3166_1'] == c).firstOrNull;
        return TmdbCountry(
          c.toString(),
          match?['name']?.toString() ?? c.toString(),
        );
      }).toList(),
      people: _people(json, isTv: true),
      runtimeMinutes: (json['episode_run_time'] as List?)
          ?.whereType<num>()
          .firstOrNull
          ?.toInt(),
      seasons: seasons,
    );
  }

  Future<TmdbSeasonDetail> season(int tvId, int seasonNumber) async {
    final json = await _get('/tv/$tvId/season/$seasonNumber', const {});
    final episodes = (json['episodes'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (e) => TmdbEpisode(
            seasonNumber: (e['season_number'] as num).toInt(),
            episodeNumber: (e['episode_number'] as num).toInt(),
            name: e['name']?.toString() ?? '',
            overview: e['overview']?.toString(),
            runtimeMinutes: (e['runtime'] as num?)?.toInt(),
            stillPath: e['still_path']?.toString(),
            airDate: e['air_date']?.toString(),
          ),
        )
        .toList();
    return TmdbSeasonDetail(
      seasonNumber: seasonNumber,
      name: json['name']?.toString() ?? '',
      episodes: episodes,
    );
  }

  Future<List<TmdbTitle>> _titlesPage(String path, bool isTv, int page) async {
    final (titles, _) = await _titlesPageWithTotal(path, isTv, page);
    return titles;
  }

  /// Same as the page fetch above but also returns TMDB's `total_pages`, so
  /// callers doing their own multi-page fetch (the catalogue's `browse`)
  /// know when to stop. ch03-p02 addition: ch03-p01's public `trending`/
  /// `popular`/`topRated` return only titles and are unchanged; the
  /// catalogue calls these `*WithTotal` variants instead. See decisions.md.
  Future<(List<TmdbTitle>, int)> _titlesPageWithTotal(
    String path,
    bool isTv,
    int page,
  ) async {
    final json = await _get(path, {'page': '$page'});
    final results = (json['results'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final totalPages = (json['total_pages'] as num?)?.toInt() ?? 1;
    return ([for (final r in results) _title(r, isTv)], totalPages);
  }

  Future<(List<TmdbTitle>, int)> trendingWithTotal({
    required bool isTv,
    int page = 1,
  }) => _titlesPageWithTotal(
    '/trending/${isTv ? 'tv' : 'movie'}/week',
    isTv,
    page,
  );

  Future<(List<TmdbTitle>, int)> popularWithTotal({
    required bool isTv,
    int page = 1,
  }) => _titlesPageWithTotal('/${isTv ? 'tv' : 'movie'}/popular', isTv, page);

  Future<(List<TmdbTitle>, int)> topRatedWithTotal({
    required bool isTv,
    int page = 1,
  }) => _titlesPageWithTotal('/${isTv ? 'tv' : 'movie'}/top_rated', isTv, page);

  TmdbTitle _title(Map<String, dynamic> r, bool isTv) => TmdbTitle(
    id: (r['id'] as num).toInt(),
    isTv: isTv,
    title: (isTv ? r['name'] : r['title'])?.toString() ?? '',
    year: tmdbYearOf(
      (isTv ? r['first_air_date'] : r['release_date'])?.toString(),
    ),
    releaseDate: (isTv ? r['first_air_date'] : r['release_date'])?.toString(),
    posterPath: r['poster_path']?.toString(),
    backdropPath: r['backdrop_path']?.toString(),
    overview: r['overview']?.toString(),
    genreIds: List.unmodifiable(
      (r['genre_ids'] as List? ?? const []).whereType<num>().map(
        (n) => n.toInt(),
      ),
    ),
    originCountries: List.unmodifiable(
      (r['origin_country'] as List? ?? const []).whereType<String>(),
    ),
    popularity: (r['popularity'] as num?)?.toDouble() ?? 0,
    rating: (r['vote_average'] as num?)?.toDouble() ?? 0,
    voteCount: (r['vote_count'] as num?)?.toInt() ?? 0,
  );

  String? _imdbId(Map<String, dynamic> json) {
    final id = (json['external_ids'] as Map?)?['imdb_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  List<String> _genreNames(Map<String, dynamic> json) =>
      (json['genres'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map((g) => g['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

  List<TmdbNamedId> _namedIds(Object? value) => (value as List? ?? const [])
      .whereType<Map>()
      .where((entry) => entry['id'] is num && entry['name'] != null)
      .map(
        (entry) =>
            TmdbNamedId((entry['id'] as num).toInt(), entry['name'].toString()),
      )
      .toList();

  List<TmdbPerson> _people(Map<String, dynamic> json, {bool isTv = false}) {
    final credits = json['credits'] as Map?;
    final crew = (credits?['crew'] as List? ?? const []).whereType<Map>();
    final cast = (credits?['cast'] as List? ?? const []).whereType<Map>();
    final directors = crew.where((p) => p['job'] == 'Director');
    final leads = directors.isNotEmpty
        ? directors
        : (isTv
              ? (json['created_by'] as List? ?? const []).whereType<Map>()
              : const <Map>[]);
    TmdbPerson person(Map p, String role, {bool isCrew = false}) => TmdbPerson(
      p['name']?.toString() ?? '',
      role,
      p['profile_path']?.toString(),
      id: (p['id'] as num?)?.toInt(),
      isCrew: isCrew,
    );
    return [
      for (final p in leads)
        if (p['name'] != null)
          person(
            p,
            directors.isNotEmpty ? 'Director' : 'Creator',
            isCrew: true,
          ),
      for (final p in cast.take(20))
        if (p['name'] != null) person(p, p['character']?.toString() ?? 'Cast'),
    ];
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: {...query, 'language': 'en-US'},
    );
    final json = await http.getJson(uri);
    if (json is! Map) throw const ContentSourceFailure.invalidResponse();
    return json.map((key, value) => MapEntry('$key', value));
  }
}
