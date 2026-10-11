/// What kind of thing a [MediaItem] is.
enum MediaKind { movie, episode, other }

/// What the UI shows and the player plays. See `planning/CONTRACTS.md` §1.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.kind,
    this.duration,
    this.artwork,
    this.subtitle,
    this.imdbId,
    this.tmdbId,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.originalLanguage,
  });

  /// Stable within a session.
  final String id;
  final String title;
  final MediaKind kind;

  /// May be unknown until the engine probes the file.
  final Duration? duration;
  final Uri? artwork;

  /// e.g. `"S02E04 · Sample Episode"`.
  final String? subtitle;

  /// The title's IMDb id; episodes use the show's id.
  final String? imdbId;

  /// The title's TMDB id; episodes use the show's id.
  final int? tmdbId;

  /// Release year.
  final int? year;

  /// Null for a show or movie.
  final int? seasonNumber;

  /// Null for a show or movie.
  final int? episodeNumber;

  /// The title's original language (TMDB `original_language`); null if unknown.
  /// Episodes use the show's original language.
  final String? originalLanguage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItem &&
          other.id == id &&
          other.title == title &&
          other.kind == kind &&
          other.duration == duration &&
          other.artwork == artwork &&
          other.subtitle == subtitle &&
          other.imdbId == imdbId &&
          other.tmdbId == tmdbId &&
          other.year == year &&
          other.seasonNumber == seasonNumber &&
          other.episodeNumber == episodeNumber &&
          other.originalLanguage == originalLanguage);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    duration,
    artwork,
    subtitle,
    imdbId,
    tmdbId,
    year,
    seasonNumber,
    episodeNumber,
    originalLanguage,
  );

  @override
  String toString() => 'MediaItem($id, $title, $kind)';
}
