import 'persian_plot.dart';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'stream_values.dart';

/// CCloud (code3-dev/CCloud): free aggregator, no login. JSON API at
/// `<root>/api/...` with a fixed public key in the path; the app falls back
/// to mirror hosts when the primary one fails.
class CCloudProvider implements SourceProvider {
  CCloudProvider({
    required this.http,
    required this.logger,
    List<Uri>? roots,
    this.domain,
  }) : _roots =
          roots ??
          [
            Uri.parse('https://server-hi-speed-iran.info'),
            Uri.parse('https://hostinnegar.com'),
            Uri.parse('https://windowsdiba.info'),
          ];

  static const _apiKey = '4F5A9C3D9A86FA54EACEDDD635185';

  final ProviderHttp http;
  final AppLogger logger;
  final List<Uri> _roots;

  /// The user's domain for this use (Title API or Providers), read on every
  /// request; tried first, the built-in mirrors stay as fallback (phase 14).
  final Uri? Function()? domain;

  List<Uri> get roots => [if (domain?.call() case final d?) d, ..._roots];

  @override
  String get id => 'ccloud';
  @override
  String get displayName => 'CCloud';

  /// Records of titles shown so far, by catalogue id (`ccloud:movie|tv:<id>`);
  /// the API has no single-title lookup. Posters/backdrops per id.
  final Map<String, Map<String, dynamic>> records = {};
  final Map<String, Uri> backdrops = {};
  static final _idPattern = RegExp(r'^ccloud:(movie|tv):(\d+)(?::s\d+e\d+)?$');

  /// Newest first (`created`); "top_rated" = by IMDb; "popular" = the server's
  /// "most popular" genre (18). Pages are read in order until the slice fits.
  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    final tv = query.kind == MediaKind.episode;
    final sort = query.sort ?? 'trending';
    final genre = sort == 'popular' ? 18 : 0;
    final order = sort == 'top_rated' ? 'imdb' : 'created';
    final want = query.offset + query.limit + 1;
    final all = <Map<String, dynamic>>[];
    for (var page = 0; all.length < want && page < 10; page++) {
      final rows = _list(
        await _get([
          tv ? 'serie' : 'movie',
          'by',
          'filtres',
          '$genre',
          order,
          '$page',
        ]),
      ).map(_map).where((p) => p['id'] != null).toList();
      if (rows.isEmpty) break;
      all.addAll(rows);
    }
    final slice = all.skip(query.offset).take(query.limit).toList();
    return MediaPage(
      items: [for (final p in slice) _item(p)],
      total: null,
      hasMore: all.length > query.offset + slice.length,
    );
  }

  @override
  Future<MediaPage> search(String query, {int limit = 50}) async {
    if (query.trim().isEmpty)
      return MediaPage(items: [], total: 0, hasMore: false);
    final rows = (await _search(query.trim())).map(_map).toList();
    return MediaPage(
      items: [for (final p in rows.take(limit)) _item(p)],
      total: null,
      hasMore: false,
    );
  }

  MediaItem _item(Map<String, dynamic> p) {
    final tv = p['type'] == 'serie';
    final id = 'ccloud:${tv ? 'tv' : 'movie'}:${p['id']}';
    records[id] = p;
    final back = Uri.tryParse('${p['cover']}');
    if (back != null && back.hasScheme) backdrops[id] = back;
    final poster = Uri.tryParse('${p['image']}');
    final year = p['year'] is int && p['year'] > 0 ? p['year'] as int : null;
    return MediaItem(
      id: id,
      title: '${p['title']}'.trim(),
      kind: tv ? MediaKind.episode : MediaKind.movie,
      artwork: poster != null && poster.hasScheme ? poster : null,
      year: year,
    );
  }

  /// The record of a catalogue title shown earlier in this session.
  Map<String, dynamic> recordOf(String itemId) {
    final r = records[itemId.split(':').take(3).join(':')];
    if (r == null || !_idPattern.hasMatch(itemId)) {
      throw const ContentSourceFailure.notFound();
    }
    return r;
  }

  /// Season number -> episode numbers of a catalogue series.
  Future<Map<int, List<int>>> episodeNumbers(String itemId) async {
    final id = recordOf(itemId)['id'];
    final out = <int, List<int>>{};
    for (final (s, e, _) in _numbered(
      _list(await _get(['season', 'by', 'serie', '$id'])),
    )) {
      if (s != null && e != null) (out[s] ??= []).add(e);
    }
    for (final list in out.values) {
      list.sort();
    }
    return out;
  }

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    final isEpisode = item.kind == MediaKind.episode;
    if (isEpisode &&
        (item.seasonNumber == null || item.episodeNumber == null)) {
      throw const ContentSourceFailure.notFound('Choose an episode first.');
    }
    try {
      final own = _idPattern.firstMatch(item.id);
      if (own != null) return await _resolveOwn(item, own[1] == 'tv');
      // The server matches text literally and stores some titles without
      // punctuation ("Spider Man Brand New Day"), others with it.
      final plain = item.title
          .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
          .trim();
      var poster = _pick(item, await _search(item.title));
      if (poster == null && plain != item.title) {
        poster = _pick(item, await _search(plain));
      }
      if (poster == null) throw const ContentSourceFailure.notFound();
      final specs = orderStreams(
        isEpisode
            ? _episodeSources(
                item,
                _list(await _get(['season', 'by', 'serie', '${poster['id']}'])),
              )
            : _list(poster['sources']).expand((s) => _spec(_map(s), null)),
      );
      if (specs.isEmpty) throw const ContentSourceFailure.notFound();
      logger.info('Resolved $id ${item.id}: ${specs.length} streams');
      return specs;
    } on ContentSourceFailure catch (error) {
      logger.warn('Resolve $id ${item.id}: ${error.code}');
      rethrow;
    }
  }

  /// A catalogue title plays from its own record (no title matching).
  Future<List<SourceSpec>> _resolveOwn(MediaItem item, bool tv) async {
    final record = recordOf(item.id);
    final specs = orderStreams(
      tv
          ? _episodeSources(
              item,
              _list(await _get(['season', 'by', 'serie', '${record['id']}'])),
            )
          : _list(record['sources']).expand((s) => _spec(_map(s), null)),
    );
    if (specs.isEmpty) throw const ContentSourceFailure.notFound();
    logger.info('Resolved $id ${item.id}: ${specs.length} streams');
    return specs;
  }

  /// The Persian story of [item] (text after "درباره فیلم:") from the poster
  /// matched by title and year; null when not found.
  Future<String?> persianPlot(MediaItem item) async {
    final poster = _pick(item, await _search(item.title));
    return storyAfter(poster?['description']?.toString(), 'درباره فیلم:');
  }

  Future<List<dynamic>> _search(String query) async =>
      _list(_map(await _get(['search', query]))['posters']);

  /// Tries each host in order; a network/server failure moves to the next,
  /// the last failure surfaces.
  Future<Object?> _get(List<String> segments) async {
    ContentSourceFailure? last;
    for (final root in roots) {
      try {
        return await http.getJson(
          root.replace(
            pathSegments: [
              ...root.pathSegments.where((s) => s.isNotEmpty),
              'api',
              ...segments,
              _apiKey,
              '',
            ],
          ),
        );
      } on ContentSourceFailure catch (error) {
        if (error.code != 'provider.network' &&
            error.code != 'provider.unavailable') {
          rethrow;
        }
        last = error;
      }
    }
    throw last!;
  }

  /// The API carries no IMDb id, so match on normalised title + type, and
  /// year when both sides have one.
  Map<String, dynamic>? _pick(MediaItem item, List<dynamic> posters) {
    final type = item.kind == MediaKind.movie ? 'movie' : 'serie';
    final wanted = _norm(item.title);
    final candidates = posters
        .map(_map)
        .where((p) => p['type'] == type && _norm('${p['title']}') == wanted)
        .toList();
    if (item.year == null) return candidates.firstOrNull;
    // Year 0 = the server does not know it.
    return candidates
            .where((p) => p['year'] == item.year || p['year'] == 0)
            .firstOrNull ??
        (candidates.length == 1 ? candidates.single : null);
  }

  /// Every episode source with its (season, episode, season title).
  Iterable<(int?, int?, Map<String, dynamic>, String)> _sources(
    List<dynamic> seasons,
  ) sync* {
    final named = RegExp(r'S(\d+)E(\d+)', caseSensitive: false);
    for (final season in seasons.map(_map)) {
      final seasonTitle = '${season['title'] ?? ''}';
      for (final episode in _list(season['episodes']).map(_map)) {
        for (final source in _list(episode['sources']).map(_map)) {
          final file = Uri.tryParse('${source['url']}')
              ?.pathSegments
              .lastOrNull;
          final match = named.firstMatch(file ?? '');
          yield (
            int.tryParse(match?[1] ?? '') ?? _seasonNumber(seasonTitle),
            int.tryParse(match?[2] ?? '') ??
                int.tryParse('${episode['title']}'.trim()),
            source,
            seasonTitle,
          );
        }
      }
    }
  }

  Iterable<(int?, int?, String)> _numbered(List<dynamic> seasons) =>
      _sources(seasons).map((x) => (x.$1, x.$2, x.$4));

  List<SourceSpec> _episodeSources(MediaItem item, List<dynamic> seasons) => [
    for (final (s, e, source, group) in _sources(seasons))
      if (s == item.seasonNumber && e == item.episodeNumber)
        ..._spec(source, group),
  ];

  Iterable<SourceSpec> _spec(Map<String, dynamic> source, String? group) sync* {
    final uri = Uri.tryParse('${source['url']}');
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    final text = '${source['quality'] ?? ''}'.trim();
    final file = uri.pathSegments.lastOrNull;
    yield SourceSpec(
      kind: SourceKind.httpUrl,
      uri: uri,
      headers: const {'User-Agent': 'Mozilla/5.0'},
      quality: parseQuality(text) ?? parseQuality(group) ?? parseQuality(file),
      fileHint: file == null ? null : Uri.decodeComponent(file),
      label: [
        group,
        text,
      ].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
    );
  }

  // ponytail: Persian ordinals 1–10 only; filenames carry SxxEyy for
  // nearly every episode, extend the list when a longer show needs it.
  static const _ordinals = [
    'اول',
    'دوم',
    'سوم',
    'چهارم',
    'پنجم',
    'ششم',
    'هفتم',
    'هشتم',
    'نهم',
    'دهم',
  ];

  static int? _seasonNumber(String title) {
    final digits = RegExp(r'فصل\s*(\d+)').firstMatch(title)?[1];
    if (digits != null) return int.parse(digits);
    final word = RegExp(r'فصل\s*(\S+)').firstMatch(title)?[1];
    final index = _ordinals.indexOf(word ?? '');
    return index < 0 ? null : index + 1;
  }

  static String _norm(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  @override
  Future<void> dispose() async => http.close();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.map((key, item) => MapEntry('$key', item)) : {};
List<dynamic> _list(Object? value) => value is List ? value : [];
