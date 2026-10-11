// Ported from PlayTorrio V3 (GPL-3.0), commit 39b736f:
// lib/services/debrid/utils/debrid_media_matcher.dart.
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'torrent_metadata.dart';

const int sampleSizeFloor = 100 * 1024 * 1024;

/// Selects a media file; sample videos below [sampleSizeFloor] are excluded when
/// a larger candidate exists.
class MediaFileSelector {
  const MediaFileSelector();
  static final _ptt = ParseTorrentTitle();

  static const _videoExts = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.ts',
    '.m4v',
    '.flv',
    '.wmv',
    '.iso',
  };

  static const _audioExts = {
    '.mp3',
    '.m4b',
    '.m4a',
    '.aac',
    '.flac',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
  };

  // Changed from PlayTorrio: also match junk folders at the start of a path.
  static final _junkRegex = RegExp(
    r'(?:(?:^|[\b._\-/])sample[\b._\-/]|(?:^|[\b._\-/])trailer[\b._\-/]|(?:^|[\b._\-/])extras?[\b._\-/]|(?:^|[\b._\-/])bonus[\b._\-/]|(?:^|[\b._\-/])featurettes?[\b._\-/]|(?:^|[\b._\-/])deleted[._ -]scenes?[\b._\-/]|behind[._ -]the[._ -]scenes|preview|interview)',
    caseSensitive: false,
  );

  /// Checks if a file path or filename matches the requested season and episode.
  bool _isFileMatch(
    String rawPath,
    int targetSeason,
    int targetEpisode, {
    String? episodeTitle,
  }) {
    return _computeFileMatchScore(
          rawPath,
          1024 * 1024 * 1000,
          season: targetSeason,
          episode: targetEpisode,
          episodeTitle: episodeTitle,
        ) >
        500.0;
  }

  /// Calculates a comprehensive match score for a torrent file candidate.
  double _computeFileMatchScore(
    String rawPath,
    int sizeBytes, {
    int? season,
    int? episode,
    String? episodeTitle,
    String? filename,
  }) {
    double score = 0.0;
    final lowerPath = rawPath.toLowerCase();

    // 1. Strict Penalty for Samples, Trailers, and Extras
    if (_junkRegex.hasMatch(lowerPath) ||
        lowerPath.endsWith('.sample') ||
        lowerPath.contains('sample.')) {
      score -= 5000.0;
    }

    // 2. File size weight: larger files are full releases, not short clips
    final sizeGB = sizeBytes / (1024.0 * 1024.0 * 1024.0);
    score += (sizeGB * 25.0).clamp(0.0, 100.0);

    if (sizeBytes < 25 * 1024 * 1024 &&
        !_audioExts.any((ext) => lowerPath.endsWith(ext))) {
      score -= 2000.0; // Stubs, previews, or sample files
    }

    // 3. Season & Episode Matching
    if (season != null && episode != null) {
      final parsed = _ptt.parsePath(rawPath);
      final parsedSeason = parsed['season'] as int?;
      final parsedEpisode = parsed['episode'] as int?;
      final episodeRange = parsed['episodeRange'] as List<int>?;
      // Changed from PlayTorrio: contradictory episode metadata is ineligible.
      final inRange =
          episodeRange != null &&
          episode >= episodeRange[0] &&
          episode <= episodeRange[1];
      if ((parsedSeason != null && parsedSeason != season) ||
          (parsedEpisode != null && parsedEpisode != episode && !inRange) ||
          (episodeRange != null && !inRange)) {
        return double.negativeInfinity;
      }

      // Exact Season & Episode Match
      if (parsedSeason == season && parsedEpisode == episode) {
        score += 1500.0;
      }
      // Multi-Episode File Range Match (e.g. S01E01-E04 for Ep 2)
      else if (parsedSeason == season &&
          episodeRange != null &&
          episode >= episodeRange[0] &&
          episode <= episodeRange[1]) {
        score += 1400.0;
      }
      // Single-Season Pack (Season omitted in filename, but episode matches)
      else if (parsedSeason == null && parsedEpisode == episode) {
        score += 1250.0;
      }
      // Range match without explicit season
      else if (parsedSeason == null &&
          episodeRange != null &&
          episode >= episodeRange[0] &&
          episode <= episodeRange[1]) {
        score += 1200.0;
      }
      // Secondary fallback patterns for uncommon naming schemes
      else {
        final normalized = ParseTorrentTitle.normalizeTorrentTitle(rawPath)
            .toLowerCase();
        final sStr = season.toString().padLeft(2, '0');
        final eStr = episode.toString().padLeft(2, '0');

        final fallbackRegexes = [
          RegExp('s0*$season[ ._x-]*e0*$episode', caseSensitive: false),
          RegExp('0*$season[xX]0*$episode', caseSensitive: false),
          RegExp('s0*$season[ ._x-]+0*$episode', caseSensitive: false),
          RegExp(
            '(?:season|saison)[ ._x-]*0*$season.*(?:episode|ep|e)[ ._x-]*0*$episode',
            caseSensitive: false,
          ),
          RegExp(
            r'\b0*'
            '$season'
            r'[- ._]+0*'
            '$episode'
            r'\b',
          ),
        ];

        bool matchedFallback = false;
        for (final p in fallbackRegexes) {
          if (p.hasMatch(normalized)) {
            matchedFallback = true;
            break;
          }
        }

        if (matchedFallback ||
            normalized.contains(
              's$sStr'
              'e$eStr',
            ) ||
            normalized.contains('${season}x$eStr') ||
            normalized.contains('${sStr}x$eStr')) {
          score += 1100.0;
        } else {
          // Changed from PlayTorrio: size/title bonuses cannot create an episode match.
          return double.negativeInfinity;
        }
      }
    }

    // 4. Episode Title Semantic Match (Extra confidence layer)
    if (episodeTitle != null && episodeTitle.trim().isNotEmpty) {
      final cleanEpTitle = episodeTitle
          .replaceAll(RegExp(r'[^\w\s]+'), '')
          .toLowerCase()
          .trim();
      final cleanPath = rawPath
          .replaceAll(RegExp(r'[^\w\s]+'), ' ')
          .toLowerCase();

      if (cleanEpTitle.length >= 4 && cleanPath.contains(cleanEpTitle)) {
        score += 600.0;
      }
    }

    // 5. Filename substring match for movies / general files
    if (filename != null && filename.trim().isNotEmpty) {
      final cleanName = filename.toLowerCase().trim();
      if (lowerPath.contains(cleanName)) {
        score += 300.0;
      }
    }

    return score;
  }

  TorrentFile select(
    TorrentMetadata metadata, {
    String? fileHint,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
  }) {
    if (metadata.files.isEmpty) {
      throw const TransportFailure.torrentFileNotFound(
        cause: 'torrent has no files',
      );
    }
    final files = metadata.files;
    TorrentFile? hinted;
    if (fileHint != null && fileHint.isNotEmpty) {
      final exact = files.where((f) => f.path == fileHint);
      if (exact.isNotEmpty) {
        hinted = exact.first;
      } else {
        final hintBase = fileHint.split('/').last.toLowerCase();
        final base = files.where(
          (f) => f.path.split('/').last.toLowerCase() == hintBase,
        );
        if (base.isNotEmpty) {
          hinted = base.first;
        } else {
          final contains = files.where(
            (f) => f.path.toLowerCase().contains(fileHint.toLowerCase()),
          );
          if (contains.isNotEmpty) hinted = contains.first;
        }
      }
      if (hinted == null) {
        throw TransportFailure.torrentFileNotFound(
          cause: files.map((f) => f.path).join(', '),
        );
      }
      if (seasonNumber == null ||
          episodeNumber == null ||
          _isFileMatch(
            hinted.path,
            seasonNumber,
            episodeNumber,
            episodeTitle: episodeTitle,
          )) {
        return hinted;
      }
    }
    if (seasonNumber != null && episodeNumber != null) {
      final mediaFiles = files.where((f) {
        final n = f.path.toLowerCase();
        return _videoExts.any((ext) => n.endsWith(ext)) ||
            _audioExts.any((ext) => n.endsWith(ext));
      }).toList();
      final candidates = mediaFiles.isNotEmpty ? mediaFiles : files;
      final scoredList = List<TorrentFile>.from(candidates);
      scoredList.sort((a, b) {
        final scoreA = _computeFileMatchScore(
          a.path,
          a.length,
          season: seasonNumber,
          episode: episodeNumber,
          episodeTitle: episodeTitle,
          filename: fileHint,
        );
        final scoreB = _computeFileMatchScore(
          b.path,
          b.length,
          season: seasonNumber,
          episode: episodeNumber,
          episodeTitle: episodeTitle,
          filename: fileHint,
        );
        return scoreB.compareTo(scoreA);
      });
      final bestCandidate = scoredList.first;
      final bestScore = _computeFileMatchScore(
        bestCandidate.path,
        bestCandidate.length,
        season: seasonNumber,
        episode: episodeNumber,
        episodeTitle: episodeTitle,
        filename: fileHint,
      );
      if (bestScore > 0.0) return bestCandidate;
      throw TransportFailure.torrentFileNotFound(
        cause: files.map((f) => f.path).join(', '),
      );
    }
    final videos = files.where((f) => _isVideo(f.path)).toList();
    final candidates = videos
        .where((f) => f.length >= sampleSizeFloor)
        .toList();
    final eligible = candidates.isNotEmpty
        ? candidates
        : (videos.isNotEmpty ? videos : files);
    return eligible.reduce((a, b) => a.length >= b.length ? a : b);
  }

  bool _isVideo(String path) => const <String>{
    'mkv',
    'mp4',
    'm4v',
    'mov',
    'avi',
    'webm',
    'ts',
  }.contains(path.split('.').last.toLowerCase());
}
