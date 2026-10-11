/// Parsed TMDB v3 records. Plain data classes, no JSON codegen.
final class TmdbTitle {
  const TmdbTitle({
    required this.id,
    required this.isTv,
    required this.title,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.genreIds = const [],
    this.originCountries = const [],
    this.popularity = 0,
    this.rating = 0,
    this.voteCount = 0,
    this.releaseDate,
  });
  final int id;
  final bool isTv;
  final String title;
  final int? year;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final List<int> genreIds;
  final List<String> originCountries;
  final double popularity;
  final double rating;
  final int voteCount;
  final String? releaseDate;
}

/// Continuation points at the next API page (search can skip empty pages).
final class TmdbTitlePage {
  const TmdbTitlePage({required this.items, this.nextPage});
  final List<TmdbTitle> items;
  final int? nextPage;
  bool get hasMore => nextPage != null;
}

final class TmdbNamedId {
  const TmdbNamedId(this.id, this.name);
  final int id;
  final String name;
}

final class TmdbPerson {
  const TmdbPerson(
    this.name,
    this.role,
    this.profilePath, {
    this.id,
    this.isCrew = false,
  });
  final int? id;
  final String name;
  final String role;
  final bool isCrew;
  final String? profilePath;
}

final class TmdbCountry {
  const TmdbCountry(this.code, this.name);
  final String code;
  final String name;
}

final class TmdbMovieDetails {
  const TmdbMovieDetails({
    required this.id,
    required this.title,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.originalLanguage,
    this.imdbId,
    this.voteAverage,
    this.runtimeMinutes,
    this.genres = const [],
    this.genreIds = const [],
    this.keywords = const [],
    this.countries = const [],
    this.people = const [],
    this.tagline,
  });

  final int id;
  final String title;
  final int? year;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final String? originalLanguage;
  final String? imdbId;
  final double? voteAverage;
  final int? runtimeMinutes;
  final List<String> genres;
  final List<TmdbNamedId> genreIds;
  final List<TmdbNamedId> keywords;
  final List<TmdbCountry> countries;
  final List<TmdbPerson> people;
  final String? tagline;
}

final class TmdbSeasonSummary {
  const TmdbSeasonSummary({
    required this.number,
    required this.name,
    required this.episodeCount,
    this.posterPath,
  });

  final int number;
  final String name;
  final int episodeCount;
  final String? posterPath;
}

final class TmdbTvDetails {
  const TmdbTvDetails({
    required this.id,
    required this.title,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.originalLanguage,
    this.imdbId,
    this.voteAverage,
    this.genres = const [],
    this.genreIds = const [],
    this.keywords = const [],
    this.countries = const [],
    this.people = const [],
    this.runtimeMinutes,
    this.seasons = const [],
  });

  final int id;
  final String title;
  final int? year;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final String? originalLanguage;
  final String? imdbId;
  final double? voteAverage;
  final List<String> genres;
  final List<TmdbNamedId> genreIds;
  final List<TmdbNamedId> keywords;
  final List<TmdbCountry> countries;
  final List<TmdbPerson> people;
  final int? runtimeMinutes;
  final List<TmdbSeasonSummary> seasons;
}

final class TmdbEpisode {
  const TmdbEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.runtimeMinutes,
    this.stillPath,
    this.airDate,
  });

  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String? overview;
  final int? runtimeMinutes;
  final String? stillPath;
  final String? airDate;
}

final class TmdbSeasonDetail {
  const TmdbSeasonDetail({
    required this.seasonNumber,
    required this.name,
    required this.episodes,
  });

  final int seasonNumber;
  final String name;
  final List<TmdbEpisode> episodes;
}

/// First four characters of [date] when they parse as a year, else null.
int? tmdbYearOf(String? date) {
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}
