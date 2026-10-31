import 'package:contracts/contracts.dart';

import 'fallback_catalogue.dart';
import 'ccloud_provider.dart';
import 'moviejavan_provider.dart';
import 'omdb_ratings.dart';
import 'persian_plot.dart';
import 'tmdb/tmdb_catalogue.dart';
import 'tmdb/tmdb_records.dart';

/// The app's title catalogue (Part 06): TMDB while it answers, otherwise the
/// Iranian providers' own catalogues through a [FallbackCatalogue]. A
/// `moviejavan:` title opens and plays from MovieJavan; anything else is TMDB.
/// Everything the Home rows, search and the detail pages call is covered;
/// TMDB-only extras (people, genre filters) simply stay unavailable offline.
final class FallbackTmdbCatalogue extends TmdbCatalogue {
  FallbackTmdbCatalogue({
    required TmdbCatalogue tmdb,
    required this.javan,
    List<SourceProvider> others = const [],
    Duration timeout = const Duration(seconds: 5),
    Duration recheck = const Duration(seconds: 60),
  }) : _tmdb = tmdb,
       fallback = FallbackCatalogue(
         sources: [tmdb, javan, ...others],
         timeout: timeout,
         recheck: recheck,
       ),
       super(client: tmdb.client, omdb: tmdb.omdb);

  final TmdbCatalogue _tmdb;
  final MovieJavanProvider javan;
  CCloudProvider? get _ccloud =>
      fallback.sources.whereType<CCloudProvider>().firstOrNull;
  final FallbackCatalogue fallback;

  /// True while titles come from a fallback (drives the "Limited mode" notice).
  bool get limited => fallback.limited;
  Stream<String> get changes => fallback.changes;

  @override
  Map<String, Uri> get backdrops => _tmdb.backdrops;

  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    final page = await fallback.browse(query);
    _addBackdrops();
    return page;
  }

  void _addBackdrops() {
    _tmdb.backdrops
      ..addAll(javan.backdrops)
      ..addAll(_ccloud?.backdrops ?? const {});
  }

  @override
  Future<MediaPage> search(String query, {int limit = 50}) async {
    final page = await fallback.search(query, limit: limit);
    _addBackdrops();
    return page;
  }

  static bool _own(MediaItem item) => item.id.startsWith('moviejavan:');

  static bool _cloud(MediaItem item) => item.id.startsWith('ccloud:');

  @override
  Future<TmdbDetails> details(MediaItem item) async {
    if (_cloud(item)) return _cloudDetails(item);
    if (!_own(item)) return _tmdb.details(item);
    final d = await javan.detailOf(item.id);
    final rating = d['imdb_rating']?.toString();
    final backdrop = Uri.tryParse(d['thumbnail_url']?.toString() ?? '');
    final poster = Uri.tryParse(d['poster_url']?.toString() ?? '');
    final minutes = int.tryParse(
      RegExp(r'\d+').firstMatch('${d['runtime']}')?.group(0) ?? '',
    );
    final release = '${d['release']}';
    return TmdbDetails(
      item: MediaItem(
        id: item.id,
        title: MovieJavanProvider.cleanTitle('${d['title'] ?? item.title}'),
        kind: item.kind,
        duration: minutes == null ? null : Duration(minutes: minutes),
        artwork: backdrop != null && backdrop.hasScheme
            ? backdrop
            : item.artwork,
        imdbId: _text(d['imdbid']),
        year: release.length >= 4
            ? int.tryParse(release.substring(0, 4))
            : item.year,
      ),
      overview: storyAfter(_text(d['description']), 'خلاصه داستان:'),
      ratings: TitleRatings(
        imdb: rating == null || rating == '0' ? null : rating,
      ),
      backdrop: backdrop != null && backdrop.hasScheme ? backdrop : null,
      poster: poster != null && poster.hasScheme ? poster : item.artwork,
    );
  }

  Future<TmdbDetails> _cloudDetails(MediaItem item) async {
    final r = _ccloud!.recordOf(item.id);
    final imdb = r['imdb'] is num && (r['imdb'] as num) > 0
        ? '${r['imdb']}'
        : null;
    final minutes = int.tryParse('${r['duration']}');
    final back = Uri.tryParse('${r['cover']}');
    return TmdbDetails(
      item: MediaItem(
        id: item.id,
        title: item.title,
        kind: item.kind,
        duration: minutes == null || minutes <= 0
            ? null
            : Duration(minutes: minutes),
        artwork: item.artwork,
        year: item.year,
      ),
      overview:
          storyAfter(_text(r['description']), 'درباره فیلم:') ??
          _text(r['description']),
      ratings: TitleRatings(imdb: imdb),
      backdrop: back != null && back.hasScheme ? back : null,
      poster: item.artwork,
    );
  }

  static String? _text(Object? v) {
    final t = v?.toString().trim();
    return t == null || t.isEmpty || t == 'null' ? null : t;
  }

  /// MovieJavan lists one "season" per quality ("1 480p ..."); the first entry
  /// of each season number is used.
  Map<int, Map<String, dynamic>> _seasonsOf(Map<String, dynamic> d) {
    final out = <int, Map<String, dynamic>>{};
    for (final raw in d['season'] is List ? d['season'] as List : const []) {
      if (raw is! Map) continue;
      final n = int.tryParse(
        RegExp(r'^\s*(\d+)').firstMatch('${raw['seasons_name']}')?[1] ?? '',
      );
      if (n != null && n > 0)
        out.putIfAbsent(n, () => raw.cast<String, dynamic>());
    }
    return out;
  }

  @override
  Future<List<TmdbSeasonSummary>> seasons(MediaItem show) async {
    if (_cloud(show)) {
      final numbers = await _ccloud!.episodeNumbers(show.id);
      return [
        for (final n in numbers.keys.toList()..sort())
          TmdbSeasonSummary(
            number: n,
            name: 'Season $n',
            episodeCount: numbers[n]!.toSet().length,
          ),
      ];
    }
    if (!_own(show)) return _tmdb.seasons(show);
    final seasons = _seasonsOf(await javan.detailOf(show.id));
    return [
      for (final n in seasons.keys.toList()..sort())
        TmdbSeasonSummary(
          number: n,
          name: 'Season $n',
          episodeCount: (seasons[n]!['episodes'] as List? ?? const []).length,
        ),
    ];
  }

  @override
  Future<List<MediaItem>> episodes(MediaItem show, int seasonNumber) async {
    if (_cloud(show)) {
      final numbers = await _ccloud!.episodeNumbers(show.id);
      return [
        for (final e in (numbers[seasonNumber] ?? const <int>[]).toSet())
          MediaItem(
            id: '${show.id}:s${seasonNumber}e$e',
            title: show.title,
            kind: MediaKind.episode,
            artwork: show.artwork,
            subtitle:
                'S${seasonNumber.toString().padLeft(2, '0')}'
                'E${e.toString().padLeft(2, '0')}',
            year: show.year,
            seasonNumber: seasonNumber,
            episodeNumber: e,
          ),
      ];
    }
    if (!_own(show)) return _tmdb.episodes(show, seasonNumber);
    final d = await javan.detailOf(show.id);
    final season = _seasonsOf(d)[seasonNumber];
    final base = show.id.split(':').take(3).join(':');
    final list =
        [
          for (final raw in season?['episodes'] as List? ?? const [])
            if (raw is Map && int.tryParse('${raw['order']}') != null) raw,
        ]..sort(
          (a, b) =>
              int.parse('${a['order']}').compareTo(int.parse('${b['order']}')),
        );
    return [
      for (final e in list)
        MediaItem(
          id: '$base:s${seasonNumber}e${e['order']}',
          title: show.title,
          kind: MediaKind.episode,
          artwork: Uri.tryParse('${e['image_url']}'),
          subtitle:
              'S${seasonNumber.toString().padLeft(2, '0')}'
              'E${'${e['order']}'.padLeft(2, '0')} · '
              '${'${e['episodes_name']}'.replaceFirst(RegExp(r'^\s*\d+\s*'), '')}',
          imdbId: _text(d['imdbid']) ?? show.imdbId,
          year: show.year,
          seasonNumber: seasonNumber,
          episodeNumber: int.parse('${e['order']}'),
        ),
    ];
  }

  @override
  Future<void> dispose() async {
    await fallback.dispose();
    await super.dispose();
  }
}
