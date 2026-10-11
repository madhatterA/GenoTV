/// "What plays after this" for a series.
class NextUpEntry {
  NextUpEntry({
    required this.seriesId,
    required this.mediaId,
    required this.season,
    required this.episode,
    required this.updatedAt,
  }) : assert(updatedAt.isUtc, 'updatedAt must be stored as UTC — convert at the edge');

  final String seriesId;
  final String mediaId;
  final int season;
  final int episode;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NextUpEntry &&
          other.seriesId == seriesId &&
          other.mediaId == mediaId &&
          other.season == season &&
          other.episode == episode &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(seriesId, mediaId, season, episode, updatedAt);
}

/// Provided by `packages/persistence` (Part 01). Stored independently of
/// the player (`research/ui/interaction-notes/README.md`: "persist
/// next-up state independently of the player").
abstract interface class NextUpRepository {
  Future<NextUpEntry?> forSeries(String seriesId);
  Future<void> set(NextUpEntry entry);
  Future<void> clear(String seriesId);
}
