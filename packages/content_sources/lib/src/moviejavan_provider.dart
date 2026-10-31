import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'persian_plot.dart';
import 'provider_http.dart';
import 'session_file.dart';
import 'stream_values.dart';

/// MovieJavan streams for a signed-in account. The app API has no search
/// (config MobileSearchEnabled "0"), so the movie/series catalogue is paged
/// once per session into a title index; a title is accepted only when the
/// detail's IMDb id equals the requested one (research/provider
/// research/moviejavan/reverse-engineering-report.md §5–§8, §10).
class MovieJavanProvider implements SourceProvider {
  MovieJavanProvider({
    required this.http,
    required this.logger,
    File? sessionFile,
    Uri? host,
    this.domain,
  }) : sessionFile =
           sessionFile ??
           defaultSessionFile('moviejavan'),
       _api = (host ?? Uri.parse('http://cdntmp.dnstmp10.q5eapp.ir')).replace(
         path: '/playstore/api',
       );

  final ProviderHttp http;
  final AppLogger logger;
  final File sessionFile;
  final Uri _api;

  /// The user's domain for this use, read on every request (phase 14).
  final Uri? Function()? domain;

  Uri get api => rebase(_api, Uri.parse(_api.origin), domain?.call());

  /// The app's fixed key (same value as the REST API-KEY header).
  static const String _key = '1661e8b60126d9f9';
  static const int _pageSize = 18;
  static const Duration _indexLife = Duration(hours: 6);

  final Map<String, _Catalogue> _catalogues = {};

  @override
  String get id => 'moviejavan';
  @override
  String get displayName => 'MovieJavan';

  /// Poster-sized backdrops by item id (the list's thumbnail), for the Home hero.
  final Map<String, Uri> backdrops = <String, Uri>{};

  static final _idPattern = RegExp(
    r'^moviejavan:(movie|tv):(\d+)(?::s(\d+)e(\d+))?$',
  );
  static const int _searchScan = 1000;

  /// The catalogue read newest first (Part 06 limited mode). The API has no
  /// sort or search, so "popular" is the batch after the newest 40 and
  /// "top_rated" is the newest 90 sorted by IMDb rating.
  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    final tv = query.kind == MediaKind.episode;
    final sort = query.sort ?? 'trending';
    final skip = switch (sort) {
      'popular' => 40 + query.offset,
      'top_rated' => query.offset,
      _ => query.offset,
    };
    final entries = await _entries(
      tv ? 'tvseries' : 'movie',
      sort == 'top_rated' ? 90 : skip + query.limit,
    );
    final list = sort == 'top_rated'
        ? (entries.take(90).toList()
            ..sort((a, b) => b.rating.compareTo(a.rating)))
        : entries;
    final page = list.skip(skip).take(query.limit).toList();
    return MediaPage(
      items: [for (final e in page) _item(e, tv)],
      total: null,
      hasMore: sort != 'top_rated' && list.length > skip + page.length,
    );
  }

  /// Matches against the newest [_searchScan] titles of each kind (the API has
  /// no search); Latin queries match the normalised names, others the raw text.
  @override
  Future<MediaPage> search(String query, {int limit = 50}) async {
    final wanted = _norm(query);
    final raw = query.trim().toLowerCase();
    if (raw.isEmpty) return MediaPage(items: [], total: 0, hasMore: false);
    final items = <MediaItem>[];
    for (final tv in [false, true]) {
      for (final e in await _entries(tv ? 'tvseries' : 'movie', _searchScan)) {
        final hit = wanted.isNotEmpty
            ? e.names.any((n) => n.contains(wanted))
            : e.rawNames.toLowerCase().contains(raw);
        if (hit) items.add(_item(e, tv));
      }
    }
    return MediaPage(
      items: items.take(limit).toList(),
      total: null,
      hasMore: false,
    );
  }

  MediaItem _item(_Entry e, bool tv) {
    final id = 'moviejavan:${tv ? 'tv' : 'movie'}:${e.id}';
    final back = Uri.tryParse(e.raw['thumbnail_url']?.toString() ?? '');
    if (back != null && back.hasScheme) backdrops[id] = back;
    final poster = Uri.tryParse(e.raw['poster_url']?.toString() ?? '');
    return MediaItem(
      id: id,
      title: cleanTitle(e.raw['title']?.toString() ?? ''),
      kind: tv ? MediaKind.episode : MediaKind.movie,
      artwork: poster != null && poster.hasScheme ? poster : null,
      year: int.tryParse(e.year),
    );
  }

  /// The title as shown: MovieJavan appends an emoji marker (movie, TV).
  static String cleanTitle(String title) => title
      .replaceAll(
        RegExp('[\u{1F300}-\u{1FAFF}\u2600-\u27BF\uFE0F]', unicode: true),
        '',
      )
      .trim();

  /// The full detail record of a catalogue title (`moviejavan:movie:123`).
  Future<Map<String, dynamic>> detailOf(String itemId) async {
    final m = _idPattern.firstMatch(itemId);
    if (m == null) throw const ContentSourceFailure.notFound();
    return _map(
      await http.getJson(
        _url('get_single_details', {
          'type': m[1] == 'tv' ? 'tvseries' : 'movie',
          'id': m[2]!,
        }),
      ),
    );
  }

  /// At least [count] list entries of [kind] (fewer when the list is shorter).
  Future<List<_Entry>> _entries(String kind, int count) {
    final catalogue = _fresh(kind);
    return catalogue.exclusive(() async {
      while (catalogue.entries.length < count && !catalogue.done) {
        await _loadPage(kind, catalogue);
      }
      return List.of(catalogue.entries);
    });
  }

  _Catalogue _fresh(String kind) {
    final saved = _catalogues[kind];
    return saved != null && DateTime.now().difference(saved.at) < _indexLife
        ? saved
        : _catalogues[kind] = _Catalogue();
  }

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    final own = _idPattern.firstMatch(item.id);
    if (own != null) return _resolveOwn(item, own[1] == 'tv');
    if (item.imdbId == null) {
      throw const ContentSourceFailure.notFound('This title has no IMDb id.');
    }
    final isEpisode = item.kind == MediaKind.episode;
    if (isEpisode &&
        (item.seasonNumber == null || item.episodeNumber == null)) {
      throw const ContentSourceFailure.notFound('Choose an episode first.');
    }
    try {
      await readSessionToken(sessionFile, 'user_id');
      final kind = isEpisode ? 'tvseries' : 'movie';
      final detail = await _locate(item, kind);
      if (detail == null) throw const ContentSourceFailure.notFound();
      final specs = orderStreams(
        isEpisode ? _episodeSources(item, detail) : _movieSources(detail),
      );
      logger.info('Resolved $id ${item.id}: ${specs.length} streams');
      return specs;
    } on ContentSourceFailure catch (error) {
      logger.warn('Resolve $id ${item.id}: ${error.code}');
      rethrow;
    }
  }

  /// A catalogue title plays from its own record (no IMDb id needed).
  Future<List<SourceSpec>> _resolveOwn(MediaItem item, bool tv) async {
    if (tv && (item.seasonNumber == null || item.episodeNumber == null)) {
      throw const ContentSourceFailure.notFound('Choose an episode first.');
    }
    await readSessionToken(sessionFile, 'user_id');
    final detail = await detailOf(item.id);
    return orderStreams(
      tv ? _episodeSources(item, detail) : _movieSources(detail),
    );
  }

  /// The Persian story of [item] (text after "خلاصه داستان:"), found by IMDb
  /// id; null when the title is not on MovieJavan or has no description.
  Future<String?> persianPlot(MediaItem item) async {
    if (item.imdbId == null) return null;
    final kind = item.kind == MediaKind.episode ? 'tvseries' : 'movie';
    final detail = await _locate(item, kind);
    return storyAfter(detail?['description']?.toString(), 'خلاصه داستان:');
  }

  Future<Map<String, dynamic>?> _locate(MediaItem item, String kind) async {
    final wanted = _norm(item.title);
    if (wanted.isEmpty) return null;
    final year = item.year?.toString();
    final saved = _catalogues[kind];
    final catalogue =
        saved != null && DateTime.now().difference(saved.at) < _indexLife
        ? saved
        : _catalogues[kind] = _Catalogue();
    // One scan per kind at a time; later resolves reuse the pages it read.
    return catalogue.exclusive(() async {
      var checked = 0;
      var verified = 0;
      while (true) {
        final fresh = [
          for (final entry in catalogue.entries.skip(checked))
            if (entry.names.contains(wanted)) entry,
        ]..sort((a, b) => (b.year == year ? 1 : 0) - (a.year == year ? 1 : 0));
        checked = catalogue.entries.length;
        for (final entry in fresh) {
          // ponytail: the IMDb id check keeps a same-name title out; at most
          // 6 detail calls per resolve.
          if (verified++ >= 6) return null;
          final detail = _map(
            await http.getJson(
              _url('get_single_details', {'type': kind, 'id': entry.id}),
            ),
          );
          if ('${detail['imdbid']}'.toLowerCase() ==
              item.imdbId!.toLowerCase()) {
            return detail;
          }
        }
        if (catalogue.done) return null;
        await _loadPage(kind, catalogue);
      }
    });
  }

  /// The API has no search: pages are read newest first, in order (the
  /// server is slower when asked for several at once), until the title is
  /// found. A full read of the movie list is about 750 pages, ~12 s.
  Future<void> _loadPage(String kind, _Catalogue catalogue) async {
    final endpoint = kind == 'movie' ? 'get_movies' : 'get_tvseries';
    final list = _list(await _page(endpoint, catalogue.nextPage++));
    for (final item in list) {
      final entry = _Entry.from(_map(item));
      if (entry != null) catalogue.entries.add(entry);
    }
    if (list.length < _pageSize) catalogue.done = true;
  }

  /// The gateway answers a cold burst with 502; a page is tried three times.
  Future<Object?> _page(String endpoint, int page) async {
    for (var attempt = 1; ; attempt++) {
      try {
        // getText + decode here: getJson starts an isolate for every page
        // over 50 KB, which cost ~1 s per round of pages.
        final body = await http.getText(_url(endpoint, {'page': '$page'}));
        return body == null ? null : jsonDecode(body);
      } on FormatException catch (error) {
        throw ContentSourceFailure.invalidResponse(error);
      } on ContentSourceFailure catch (error) {
        if (attempt == 3 || error.code == 'provider.auth_required') rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  Uri _url(String endpoint, Map<String, String> query) => api.replace(
    path: '${api.path}/$endpoint',
    queryParameters: {
      'api_secret_key': _key,
      'version': '4.5.0',
      'sp': 'false',
      'country': 'other',
      ...query,
    },
  );

  List<SourceSpec> _movieSources(Map<String, dynamic> detail) => [
    for (final raw in _list(detail['videos']))
      ?_spec(_map(raw)['file_url'], _map(raw)['label'], _map(raw)['file_size']),
  ];

  List<SourceSpec> _episodeSources(
    MediaItem item,
    Map<String, dynamic> detail,
  ) {
    final specs = <SourceSpec>[];
    for (final rawSeason in _list(detail['season'])) {
      final season = _map(rawSeason);
      final name = season['seasons_name']?.toString() ?? '';
      // "1 720p ..." — the leading number is the season, then the quality.
      if (int.tryParse(RegExp(r'^\s*(\d+)').firstMatch(name)?[1] ?? '') !=
          item.seasonNumber) {
        continue;
      }
      for (final rawEpisode in _list(season['episodes'])) {
        final episode = _map(rawEpisode);
        if (int.tryParse('${episode['order']}') != item.episodeNumber) continue;
        final spec = _spec(
          episode['file_url'],
          name.replaceFirst(RegExp(r'^\s*\d+'), ''),
          episode['file_size'],
        );
        if (spec != null) specs.add(spec);
      }
    }
    return specs;
  }

  /// Teasers have no quality in their label and are skipped.
  SourceSpec? _spec(Object? url, Object? label, Object? sizeMb) {
    final uri = Uri.tryParse(url?.toString() ?? '');
    final quality = parseQuality(label?.toString());
    if (uri == null || !uri.scheme.startsWith('http') || quality == null) {
      return null;
    }
    final mb = int.tryParse('$sizeMb');
    return SourceSpec(
      kind: SourceKind.httpUrl,
      uri: uri,
      headers: const {'User-Agent': 'Mozilla/5.0'},
      quality: quality,
      fileHint: uri.pathSegments.lastOrNull,
      label: [
        quality,
        if (mb != null)
          mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '$mb MB',
      ].join(' · '),
    );
  }

  /// True when a saved session exists (it may still have expired).
  Future<bool> get signedIn async {
    try {
      await readSessionToken(sessionFile, 'user_id');
      return true;
    } on ContentSourceFailure {
      return false;
    }
  }

  @override
  Future<void> dispose() async => http.close();
}

class _Catalogue {
  final DateTime at = DateTime.now();
  final List<_Entry> entries = [];
  int nextPage = 1;
  bool done = false;
  Future<void> _turn = Future<void>.value();

  Future<T> exclusive<T>(Future<T> Function() body) {
    final result = _turn.then((_) => body());
    _turn = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}

class _Entry {
  _Entry(this.id, this.names, this.year, this.raw, this.rawNames);
  final String id;
  final Set<String> names;
  final String year;
  final Map<String, dynamic> raw;
  final String rawNames;
  double get rating => double.tryParse('${raw['imdb_rating']}') ?? 0;

  static _Entry? from(Map<String, dynamic> item) {
    final id = item['videos_id']?.toString() ?? '';
    if (id.isEmpty) return null;
    // `writer` lists alternate titles (Persian and English), comma separated.
    final names = {
      for (final name in [
        item['title']?.toString() ?? '',
        ...(item['writer']?.toString() ?? '').split(','),
      ])
        if (_norm(name).isNotEmpty) _norm(name),
    };
    final release = item['release']?.toString() ?? '';
    return _Entry(
      id,
      names,
      release.length >= 4 ? release.substring(0, 4) : '',
      item,
      '${item['title']} ${item['writer']}',
    );
  }
}

String _norm(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.map((key, item) => MapEntry('$key', item)) : {};
List<dynamic> _list(Object? value) => value is List ? value : [];
