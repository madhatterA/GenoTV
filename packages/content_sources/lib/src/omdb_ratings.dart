import 'dart:io';

import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';

/// IMDb and Rotten Tomatoes scores for one title; either may be null.
/// [tmdb] is the TMDB vote average, set only when OMDb has no score at all.
final class TitleRatings {
  const TitleRatings({this.imdb, this.rottenTomatoes, this.tmdb});

  /// e.g. `"8.8"`.
  final String? imdb;

  /// e.g. `"87%"`.
  final String? rottenTomatoes;

  /// e.g. `"7.0"`.
  final String? tmdb;

  bool get isEmpty => imdb == null && rottenTomatoes == null && tmdb == null;
}

/// OMDb lookup by IMDb id. No key in the app: [http] routes www.omdbapi.com
/// to the backup proxy, which adds it (BACKUP_PROXY.md, owner 2026-10-10).
/// On any failure it returns empty ratings and logs a warning.
class OmdbRatings {
  OmdbRatings({required this.http, required this.logger, Uri? baseUrl})
    : baseUrl = baseUrl ?? Uri.parse('https://www.omdbapi.com/');

  final ProviderHttp http;
  final AppLogger logger;
  final Uri baseUrl;

  Future<TitleRatings> ratings(String imdbId) async {
    try {
      final json = await http.getJson(
        baseUrl.replace(queryParameters: {'i': imdbId}),
      );
      if (json is! Map || json['Response'] == 'False') {
        logger.warn(
          'OMDb refused $imdbId: ${json is Map ? json['Error'] : json}',
        );
        return const TitleRatings();
      }
      final imdb = _value(json['imdbRating']);
      final rt = (json['Ratings'] as List? ?? const [])
          .whereType<Map>()
          .where((r) => r['Source'] == 'Rotten Tomatoes')
          .map((r) => _value(r['Value']))
          .firstOrNull;
      return TitleRatings(imdb: imdb, rottenTomatoes: rt);
    } on ContentSourceFailure catch (error) {
      logger.warn('OMDb lookup $imdbId failed: ${error.code}');
      return const TitleRatings();
    }
  }

  static String? _value(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s == 'N/A' ? null : s;
  }
}
