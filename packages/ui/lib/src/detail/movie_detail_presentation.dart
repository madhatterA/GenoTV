import 'package:contracts/contracts.dart';

/// Caller-supplied presentation data for [MovieDetailScreen]. `MediaItem`
/// (`packages/contracts/lib/src/media/media_item.dart`) is a frozen,
/// cross-Part contract with only id/title/kind/duration/artwork/subtitle —
/// it has no room for genres, rating, tagline, cast, etc. Per the Phase 05
/// "Data" decision ("immutable caller-supplied presentation sections | Part
/// boundary"), this package defines its own immutable presentation model
/// instead of extending the contract; the content-source Part (out of
/// scope, CLAUDE.md) will be the eventual real supplier.
class MovieDetailPresentation {
  const MovieDetailPresentation({
    required this.item,
    this.poster,
    this.year,
    this.runtimeLabel,
    this.runtime,
    this.imdbRating,
    this.rottenTomatoes,
    this.tmdbRating,
    this.contentRating,
    this.genres = const <String>[],
    this.links = const <DetailLink>[],
    this.tagline,
    this.summary,
    this.qualityBadges = const <String>[],
    this.progress,
    this.isWatched = false,
    this.isInWatchlist = false,
    this.trailers = const <MediaItem>[],
    this.cast = const <CastMember>[],
    this.related = const <MediaItem>[],
    this.about = const <AboutFact>[],
  });

  final MediaItem item;

  /// The 2:3 poster shown left of the title on desktop and TV; [item]'s own
  /// artwork is the wide backdrop. Null shows no poster.
  final Uri? poster;
  final String? year;
  final String? runtimeLabel;

  /// Shown through the duration formatter when [runtimeLabel] is null.
  final Duration? runtime;
  final String? imdbRating;
  final String? rottenTomatoes;
  final String? tmdbRating;
  final String? contentRating;

  final List<String> genres;
  final List<DetailLink> links;
  final String? tagline;
  final String? summary;
  final List<String> qualityBadges;

  /// Resume position, if any. Zero/null progress renders the primary
  /// action as "Play"; a non-null, non-complete progress renders "Resume".
  final PlaybackProgress? progress;
  final bool isWatched;
  final bool isInWatchlist;

  final List<MediaItem> trailers;
  final List<CastMember> cast;
  final List<MediaItem> related;
  final List<AboutFact> about;

  /// A new [MovieDetailPresentation] with the given fields replaced —
  /// used by the playback-return refresh path (step 5) so the caller can
  /// hand back updated progress/watch state without rebuilding the page.
  MovieDetailPresentation copyWith({
    PlaybackProgress? progress,
    bool? isWatched,
    bool? isInWatchlist,
  }) => MovieDetailPresentation(
    item: item,
    poster: poster,
    year: year,
    runtimeLabel: runtimeLabel,
    runtime: runtime,
    imdbRating: imdbRating,
    rottenTomatoes: rottenTomatoes,
    tmdbRating: tmdbRating,
    contentRating: contentRating,
    genres: genres,
    links: links,
    tagline: tagline,
    summary: summary,
    qualityBadges: qualityBadges,
    progress: progress ?? this.progress,
    isWatched: isWatched ?? this.isWatched,
    isInWatchlist: isInWatchlist ?? this.isInWatchlist,
    trailers: trailers,
    cast: cast,
    related: related,
    about: about,
  );
}

class DetailLink {
  const DetailLink(this.label, this.value, this.filter);
  final String label;
  final String value;
  final String filter;

  /// Genres and keywords are the tag chips; year and country are inline
  /// links in the hero's facts line.
  bool get isTag => filter == 'with_genres' || filter == 'with_keywords';
  bool get isYear =>
      filter == 'primary_release_year' || filter == 'first_air_date_year';
  bool get isCountry => filter == 'with_origin_country';
}

/// One cast entry — `CastCell.swift`. No photo resolution beyond the
/// shared `ArtworkResolverScope` (a missing photo falls back the same way
/// a missing poster does).
class CastMember {
  const CastMember({
    required this.name,
    this.role,
    this.photo,
    this.id,
    this.isCrew = false,
    this.biography,
  });

  /// TMDB person id; null when the person page cannot be opened.
  final int? id;
  final String name;
  final String? role;
  final bool isCrew;
  final Uri? photo;

  /// Shown on the person page, six lines with a "More" button.
  final String? biography;
}

/// One "about/technical information" row — `AboutInfoCells.swift`.
class AboutFact {
  const AboutFact(this.label, this.value);

  final String label;
  final String value;
}
