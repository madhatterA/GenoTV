import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'session_file.dart';
import 'stream_values.dart';

class DigiMoviezProvider implements SourceProvider {
  DigiMoviezProvider({
    required this.http,
    required this.logger,
    File? sessionFile,
    Uri? siteRoot,
    Uri? apiRoot,
  }) : sessionFile =
           sessionFile ??
           File('${Platform.environment['HOME']}/.digimoviez-session.json'),
       siteRoot = siteRoot ?? Uri.parse('https://digimoviez.com'),
       apiRoot = apiRoot ?? Uri.parse('https://digimoviez.com/api/app/v1');

  final ProviderHttp http;
  final AppLogger logger;
  final File sessionFile;
  final Uri siteRoot;
  final Uri apiRoot;
  @override
  String get id => 'digimoviez';
  @override
  String get displayName => 'DigiMoviez';
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
      final token = await readSessionToken(sessionFile, 'auth_token');
      final postId = await _locate(item);
      if (postId == null) throw const ContentSourceFailure.notFound();
      final detail = _map(
        await http.getJson(
          apiRoot.replace(
            path: '${apiRoot.path}/get_movie_detail',
            queryParameters: {'movie_id': postId},
          ),
          headers: {'Accept': 'application/json', 'authorization': token},
        ),
      );
      if (detail['status'] != true) {
        throw const ContentSourceFailure.unavailable();
      }
      final specs = orderStreams(_sources(item, detail));
      if (specs.isEmpty && detail['need_subscription'] == true) {
        throw const ContentSourceFailure.authRequired(
          'DigiMoviez needs an active subscription.',
        );
      }
      logger.info('Resolved $id ${item.id}: ${specs.length} streams');
      return specs;
    } on ContentSourceFailure catch (error) {
      logger.warn('Resolve $id ${item.id}: ${error.code}');
      rethrow;
    }
  }

  Future<String?> _locate(MediaItem item) async {
    if (item.kind == MediaKind.movie) {
      // The `/<imdbId>/` shortcut only exists for some titles (404 for others,
      // wrong film for some); the site search below is the reliable path.
      final direct = _postId(
        await http.getText(
          siteRoot.resolve('/${item.imdbId}/'),
          allowNotFound: true,
        ),
        item.imdbId!,
      );
      if (direct != null) return direct;
    }
    final html =
        await http.getText(
          siteRoot.replace(path: '/', queryParameters: {'s': item.title}),
        ) ??
        '';
    final isMovie = item.kind == MediaKind.movie;
    final pattern = isMovie
        ? RegExp(r'href="(https?://[^" ]+/[a-z0-9-]+-\d{4}/)"')
        : RegExp(r'href="(https?://[^" ]+/serie/[a-z0-9-]+/)"');
    final wanted = _slug(item.title);
    // Title-matching links first: the result page also lists unrelated
    // sidebar titles, and every candidate costs one page fetch.
    final all = pattern.allMatches(html).map((m) => m[1]!).toSet();
    final year = item.year;
    bool yearMatches(String l) => year != null && l.endsWith('-$year/');
    // ponytail: every candidate costs a ~2s page fetch and the result page
    // mixes in unrelated sidebar titles, so try the same-year, then
    // title-matching, then a few other links, at most 6 in all.
    final links = [
      ...all.where((l) => _slugMatches(l, wanted) && yearMatches(l)),
      ...all.where((l) => _slugMatches(l, wanted) && !yearMatches(l)),
      ...all.where((l) => !_slugMatches(l, wanted)),
    ].take(6);
    for (final link in links) {
      final uri = Uri.parse(link);
      if (uri.host != siteRoot.host) continue;
      final id = _postId(
        await http.getText(uri, allowNotFound: true),
        item.imdbId!,
      );
      if (id != null) return id;
    }
    return null;
  }

  static String _slug(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static bool _slugMatches(String link, String wanted) =>
      wanted.isNotEmpty && Uri.parse(link).path.contains(wanted);

  String? _postId(String? html, String imdbId) {
    if (html == null) return null;
    final pageImdb = RegExp(
      r'class="imdb_icon_holder" href="https://www\.imdb\.com/title/(tt\d+)',
      caseSensitive: false,
    ).firstMatch(html)?[1];
    if (pageImdb?.toLowerCase() != imdbId.toLowerCase()) return null;
    return RegExp(r'postid-(\d+)').firstMatch(html)?[1];
  }

  List<SourceSpec> _sources(MediaItem item, Map<String, dynamic> detail) {
    final specs = <SourceSpec>[];
    final seen = <Uri>{};
    void add(Object? raw, Map<String, dynamic> entry, {bool episode = false}) {
      final uri = Uri.tryParse(raw?.toString() ?? '');
      if (uri?.scheme != 'https' || !seen.add(uri!)) return;
      final quality = parseQuality(entry['quality']?.toString());
      final size = entry['size']?.toString() ?? '';
      specs.add(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: uri,
          headers: const {'User-Agent': 'Mozilla/5.0'},
          quality: quality,
          expectedBytes: episode ? null : parseSizeBytes(size),
          fileHint: (entry['filename'] ?? entry['file_name'])?.toString(),
          label: [
            quality,
            entry['encode'] ?? entry['encoder'],
            size,
            if (entry['dubbed'] == true) 'Dubbed',
          ].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
        ),
      );
    }

    if (item.kind == MediaKind.episode) {
      final named = RegExp(r'S(\d+)E(\d+)', caseSensitive: false);
      for (final rawGroup in _list(detail['serie_download_urls'])) {
        final group = _map(rawGroup);
        final season = RegExp(r'\d+')
            .firstMatch(group['season_name']?.toString() ?? '')?[0];
        for (final rawLink in _list(group['links'])) {
          final link = _map(rawLink);
          final url = link['movie']?.toString() ?? '';
          final match = named.firstMatch(
            Uri.tryParse(url)?.pathSegments.lastOrNull ?? '',
          );
          final s = int.tryParse(match?[1] ?? season ?? '');
          final e = int.tryParse(
            match?[2] ?? link['part_id']?.toString() ?? '',
          );
          if (s == item.seasonNumber && e == item.episodeNumber) {
            add(url, group, episode: true);
          }
        }
      }
    } else {
      for (final key in ['movie_download_urls', 'movie_online_urls']) {
        for (final raw in _list(detail[key])) {
          final entry = _map(raw);
          add(entry['file'], entry);
        }
      }
    }
    return specs;
  }

  /// True when a saved session exists (it may still have expired).
  Future<bool> get signedIn async {
    try {
      await readSessionToken(sessionFile, 'auth_token');
      return true;
    } on ContentSourceFailure {
      return false;
    }
  }

  /// Signs in with the account's username and password (the DigiMoviez
  /// app API) and saves the session the provider reads.
  Future<void> signIn(String username, String password) async {
    final response = _map(
      await http.postJson(
        apiRoot.replace(path: '${apiRoot.path}/login'),
        {'username': username, 'password': password},
        headers: {'Accept': 'application/json'},
      ),
    );
    final token = response['auth_token']?.toString() ?? '';
    if (response['status'] != true || token.isEmpty) {
      throw ContentSourceFailure.authRequired(
        response['message']?.toString() ?? 'DigiMoviez rejected the sign-in.',
      );
    }
    await writeSession(sessionFile, {
      'auth_token': token,
      'provider': 'digimoviez-app',
    });
    logger.info('DigiMoviez sign-in saved');
  }

  Future<void> signOut() => deleteSession(sessionFile);

  @override
  Future<void> dispose() async => http.close();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.map((key, item) => MapEntry('$key', item)) : {};
List<dynamic> _list(Object? value) => value is List ? value : [];
