import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'stream_values.dart';

/// CCloud (code3-dev/CCloud): free aggregator, no login. JSON API at
/// `<root>/api/...` with a fixed public key in the path; the app falls back
/// to mirror hosts when the primary one fails.
class CCloudProvider implements SourceProvider {
  CCloudProvider({required this.http, required this.logger, List<Uri>? roots})
    : roots =
          roots ??
          [
            Uri.parse('https://server-hi-speed-iran.info'),
            Uri.parse('https://hostinnegar.com'),
            Uri.parse('https://windowsdiba.info'),
          ];

  static const _apiKey = '4F5A9C3D9A86FA54EACEDDD635185';

  final ProviderHttp http;
  final AppLogger logger;
  final List<Uri> roots;

  @override
  String get id => 'ccloud';
  @override
  String get displayName => 'CCloud';
  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: [], total: 0, hasMore: false);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) async =>
      MediaPage(items: [], total: 0, hasMore: false);

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    final isEpisode = item.kind == MediaKind.episode;
    if (isEpisode &&
        (item.seasonNumber == null || item.episodeNumber == null)) {
      throw const ContentSourceFailure.notFound('Choose an episode first.');
    }
    try {
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

  Future<List<dynamic>> _search(String query) async =>
      _list(_map(await _get(['search', query]))['posters']);

  /// Tries each host in order; a network/server failure moves to the next,
  /// the last failure surfaces.
  Future<Object?> _get(List<String> segments) async {
    ContentSourceFailure? last;
    for (final root in roots) {
      try {
        return await http.getJson(
          root.replace(pathSegments: ['api', ...segments, _apiKey, '']),
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

  List<SourceSpec> _episodeSources(MediaItem item, List<dynamic> seasons) {
    final named = RegExp(r'S(\d+)E(\d+)', caseSensitive: false);
    final specs = <SourceSpec>[];
    for (final season in seasons.map(_map)) {
      final seasonTitle = '${season['title'] ?? ''}';
      for (final episode in _list(season['episodes']).map(_map)) {
        for (final source in _list(episode['sources']).map(_map)) {
          final file = Uri.tryParse('${source['url']}')
              ?.pathSegments
              .lastOrNull;
          final match = named.firstMatch(file ?? '');
          final s = int.tryParse(match?[1] ?? '') ?? _seasonNumber(seasonTitle);
          final e =
              int.tryParse(match?[2] ?? '') ??
              int.tryParse('${episode['title']}'.trim());
          if (s == item.seasonNumber && e == item.episodeNumber) {
            specs.addAll(_spec(source, seasonTitle));
          }
        }
      }
    }
    return specs;
  }

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
