import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'session_file.dart';
import 'stream_values.dart';

class ThirtyNamaProvider implements SourceProvider {
  ThirtyNamaProvider({
    required this.http,
    required this.logger,
    File? sessionFile,
    Uri? searchUrl,
    Uri? actionUrl,
  }) : sessionFile =
           sessionFile ??
           File('${Platform.environment['HOME']}/.30nama-session.json'),
       searchUrl =
           searchUrl ??
           Uri.parse(
             'https://stg-ciera.webpanel.systems/videoContent/user-video-content/explore',
           ),
       actionUrl =
           actionUrl ?? Uri.parse('https://interface.30nama.com/api/v1/action');

  final ProviderHttp http;
  final AppLogger logger;
  final File sessionFile;
  final Uri searchUrl;
  final Uri actionUrl;
  @override
  String get id => 'thirtynama';
  @override
  String get displayName => '30nama';

  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: [], total: 0, hasMore: false);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) async =>
      MediaPage(items: [], total: 0, hasMore: false);

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    if (item.imdbId == null) {
      throw const ContentSourceFailure.notFound('This title has no IMDb id.');
    }
    if (item.kind == MediaKind.episode &&
        (item.seasonNumber == null || item.episodeNumber == null)) {
      throw const ContentSourceFailure.notFound('Choose an episode first.');
    }
    try {
      final token = await readSessionToken(sessionFile, 'access_token');
      final headers = {..._apiHeaders, 'c-token': token};
      // The site's own search (full_search) matches an IMDb id and returns
      // exactly that title. The explore endpoint below is a name index only:
      // it does not index the IMDb id of every entry (Coyote vs. Acme), so it
      // is the fallback, by same title and year (up to 3 pages).
      final providerId =
          await _findByImdb(item.imdbId!, headers) ??
          _str((await _find(item, _nameQuery(item.title), 3))?['id']);
      if (providerId.isEmpty) throw const ContentSourceFailure.notFound();
      final stream = _map(
        await http.postForm(
          actionUrl.resolve('${actionUrl.path}/stream/id/$providerId'),
          {'freeStream': 'false'},
          headers: headers,
        ),
      );
      final download = _map(
        await http.postForm(
          actionUrl.resolve('${actionUrl.path}/download/id/$providerId'),
          {'freeDownload': 'false'},
          headers: headers,
        ),
      );
      if (stream['success'] != true || download['success'] != true) {
        throw ContentSourceFailure.authRequired(
          _str(stream['msg'] ?? download['msg']).isEmpty
              ? '30nama refused the link request.'
              : _str(stream['msg'] ?? download['msg']),
        );
      }
      final specs = orderStreams(
        _sources(item, _map(stream['result']), _map(download['result'])),
      );
      logger.info('Resolved $id ${item.id}: ${specs.length} streams');
      return specs;
    } on ContentSourceFailure catch (error) {
      logger.warn('Resolve $id ${item.id}: ${error.code}');
      rethrow;
    }
  }

  /// 30nama's site search for an IMDb id (`tt...` as `query`); returns the id
  /// of the post whose `imdb_id` equals [imdbId], or null.
  Future<String?> _findByImdb(
    String imdbId,
    Map<String, String> headers,
  ) async {
    final result = _map(
      await http.postForm(
        actionUrl.resolve(
          '${actionUrl.path}/full_search/type/all/orderby/relevant/order/desc/page/1',
        ),
        {'query': imdbId},
        headers: headers,
      ),
    );
    if (result['success'] != true) {
      throw const ContentSourceFailure.unavailable();
    }
    for (final post in _list(_map(_map(result['result'])['title'])['posts'])) {
      final entry = _map(post);
      if (_str(entry['imdb_id']).toLowerCase() == imdbId.toLowerCase()) {
        return _str(entry['id']);
      }
    }
    return null;
  }

  /// Searches 30nama for [query]; returns the entry for [item], or null.
  Future<Map<String, dynamic>?> _find(
    MediaItem item,
    String query,
    int maxPages,
  ) async {
    for (var page = 1; page <= maxPages; page++) {
      final result = _map(
        await http.getJson(
          searchUrl.replace(
            queryParameters: {
              'search': query,
              'type': item.kind == MediaKind.movie ? 'movies' : 'series',
              'with_elastic': 'true',
              'page': '$page',
              'limit': '20',
            },
          ),
          headers: {'Accept': 'application/json', 'c-platform': 'website'},
        ),
      );
      if (result['success'] != true) {
        throw const ContentSourceFailure.unavailable();
      }
      final matches = _list(_map(result['data'])['items']).map(_map).toList();
      for (final entry in matches) {
        if (_isTitle(item, entry)) return entry;
      }
      if (matches.length < 20) break;
    }
    return null;
  }

  /// 30nama's fuzzy search ranks every "vs."/"v"/"versus" title above the one
  /// asked for ("Coyote vs. Acme" sits on page 6, "Coyote Acme" on page 1), so
  /// the name query keeps only the significant words.
  static String _nameQuery(String title) {
    final words = title
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where(
          (w) =>
              w.isNotEmpty &&
              !const {'vs', 'v', 'versus'}.contains(w.toLowerCase()),
        );
    return words.isEmpty ? title : words.join(' ');
  }

  static bool _isTitle(MediaItem item, Map<String, dynamic> entry) {
    final id = _str(_map(_map(entry['ratings'])['imdb'])['sub_path'])
        .split('/')
        .where((x) => x.isNotEmpty)
        .lastOrNull;
    if (id != null) return id.toLowerCase() == item.imdbId!.toLowerCase();
    // No IMDb id on the entry: "<title> <year>" must equal ours.
    final name = _str(_map(_map(entry['info'])['en'])['title']);
    final m = RegExp(r'^(.*?)\s+(\d{4})$').firstMatch(name);
    if (m == null) return false;
    String norm(String t) =>
        t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return norm(m.group(1)!) == norm(item.title) &&
        (item.year == null || '${item.year}' == m.group(2));
  }

  List<SourceSpec> _sources(
    MediaItem item,
    Map<String, dynamic> stream,
    Map<String, dynamic> download,
  ) {
    final specs = <SourceSpec>[];
    if (item.kind == MediaKind.episode) {
      for (final entry in _list(_map(stream['list'])['${item.seasonNumber}'])) {
        final data = _map(entry);
        if (int.tryParse(_str(_map(data['data'])['number'])) ==
            item.episodeNumber) {
          specs.addAll(_hls(_map(data['file'])['source']));
        }
      }
      for (final raw in _list(download['download'])) {
        final entry = _map(raw);
        if (int.tryParse(_str(entry['season_int'] ?? entry['season'])) !=
            item.seasonNumber) {
          continue;
        }
        for (final rawLink in _list(entry['link'])) {
          final link = _map(rawLink);
          if (int.tryParse(_str(link['episode'])) == item.episodeNumber) {
            final spec = _file(link['dl'], entry);
            if (spec != null) specs.add(spec);
          }
        }
      }
    } else {
      specs.addAll(_hls(_map(stream['file'])['source']));
      for (final raw in _list(download['download'])) {
        final entry = _map(raw);
        final spec = _file(entry['dl'], entry);
        if (spec != null) specs.add(spec);
      }
    }
    return specs;
  }

  Iterable<SourceSpec> _hls(Object? raw) sync* {
    for (final entry in _list(raw)) {
      final data = _map(entry);
      final uri = Uri.tryParse(_str(data['auto']));
      if (uri?.scheme != 'https') continue;
      final label = _str(data['label']);
      yield SourceSpec(
        kind: SourceKind.hlsUrl,
        uri: uri!,
        headers: const {'User-Agent': 'Mozilla/5.0'},
        quality: parseQuality(label),
        label: 'HLS · ${label == 'خودکار' ? 'Auto' : label}',
      );
    }
  }

  SourceSpec? _file(Object? raw, Map<String, dynamic> data) {
    final uri = Uri.tryParse(_str(raw));
    if (uri?.scheme != 'https') return null;
    final quality = parseQuality(
      '${_str(data['resolution'])} ${_str(data['quality'])}',
    );
    final size = _str(data['size']);
    return SourceSpec(
      kind: SourceKind.httpUrl,
      uri: uri!,
      headers: const {'User-Agent': 'Mozilla/5.0'},
      quality: quality,
      expectedBytes: parseSizeBytes(size),
      fileHint: _str(data['filename'] ?? data['file_name']).isEmpty
          ? null
          : _str(data['filename'] ?? data['file_name']),
      label: [
        quality,
        _str(data['encoder']),
        _str(data['tags']),
        size,
      ].whereType<String>().where((part) => part.isNotEmpty).join(' · '),
    );
  }

  static const Map<String, String> _apiHeaders = {
    'c-api-key':
        'YygufGCvFgYR3g9sjD92Ct5ZSx7SJs4JXpuCeTS24nWAszaL4u3qCDZRULpejmzF',
    'c-useragent': 'Website',
    'c-app-version': '1.0.0',
    'c-platform': 'Website',
  };

  /// True when a saved session exists (it may still have expired).
  Future<bool> get signedIn async {
    try {
      await readSessionToken(sessionFile, 'access_token');
      return true;
    } on ContentSourceFailure {
      return false;
    }
  }

  /// Starts a QR sign-in: [url] is what the QR encodes; a device already
  /// signed in to 30nama opens it to approve. Same API as 30nama.com/auth.
  Future<({String code, Uri url})> startQrLogin() async {
    final result = _map(
      _map(
        await http.postForm(
          actionUrl.resolve('${actionUrl.path}/qrcode/'),
          const {},
          headers: _apiHeaders,
        ),
      )['result'],
    );
    final code = _str(result['code']);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(code)) {
      throw const ContentSourceFailure.invalidResponse(
        '30nama returned no valid QR code',
      );
    }
    final url = _str(result['url']);
    return (
      code: code,
      url: url.startsWith('https://30nama.com/auth/')
          ? Uri.parse(url)
          : Uri.parse('https://30nama.com/auth/${Uri.encodeComponent(code)}'),
    );
  }

  /// True once [code] was approved; the session is then saved.
  Future<bool> pollQrLogin(String code) async {
    final response = _map(
      await http.postForm(
        actionUrl.resolve(
          '${actionUrl.path}/qrlogin/code/${Uri.encodeComponent(code)}',
        ),
        const {},
        headers: _apiHeaders,
      ),
    );
    final token = _str(_map(response['result'])['usertoken']);
    if (response['success'] != true || token.isEmpty) return false;
    await writeSession(sessionFile, {
      'access_token': token,
      'provider': '30nama-app-qr',
    });
    logger.info('30nama QR sign-in saved');
    return true;
  }

  Future<void> signOut() => deleteSession(sessionFile);

  @override
  Future<void> dispose() async => http.close();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.map((key, item) => MapEntry('$key', item)) : {};
List<dynamic> _list(Object? value) => value is List ? value : [];
String _str(Object? value) => value?.toString().trim() ?? '';
