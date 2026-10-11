// Ported from PlayTorrioV3 lib/services/scraper/sites/knaben.dart,
// commit 39b736f. GPL-3.0; see root README.md (Credits) and LICENSE.
import 'package:contracts/contracts.dart';

bool matchesRequest(Map<String, dynamic> parsed, MediaItem item) {
  final parsedTitle = (parsed['title'] ?? '').toString().toLowerCase();
  final cleanParsedTitle = parsedTitle.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final searchTitleLower = item.title.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  if (cleanParsedTitle != searchTitleLower) return false;
  if (item.kind == MediaKind.episode) {
    final parsedSeason = parsed['season'];
    final parsedEpisode = parsed['episode'];
    if (item.seasonNumber != null &&
        parsedSeason != null &&
        parsedSeason != item.seasonNumber) {
      return false;
    }
    // Keep season packs, which have no parsed episode.
    if (item.episodeNumber != null &&
        parsedEpisode != null &&
        parsedEpisode != item.episodeNumber) {
      return false;
    }
  }
  return true;
}
