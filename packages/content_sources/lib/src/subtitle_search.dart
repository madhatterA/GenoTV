import 'dart:typed_data';

import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'subtitle_accounts.dart';

/// What is playing. [imdbId] ("tt0133093") and [tmdbId] win over [title]+[year];
/// for an episode they identify the SERIES and [season]/[episode] pick it.
class SubtitleQuery {
  const SubtitleQuery({
    this.imdbId,
    this.tmdbId,
    this.title,
    this.year,
    this.season,
    this.episode,
    this.languages = const ['fa', 'en'],
    this.fileName = '',
  });

  final String? imdbId;
  final int? tmdbId;
  final String? title;
  final int? year;
  final int? season;
  final int? episode;

  /// ISO 639-1 codes, preferred first; the order ranks results.
  final List<String> languages;

  /// The playing file's name, matched against each result's release name.
  final String fileName;

  bool get isEpisode => season != null && episode != null;
}

class SubtitleResult {
  const SubtitleResult({
    required this.service,
    required this.language,
    required this.release,
    required this.uploader,
    required this.hearingImpaired,
    required this.downloads,
    required this.ref,
    this.score = 0,
  });

  /// [SubtitleAccounts.subdl], [SubtitleAccounts.subsource] or
  /// [SubtitleAccounts.openSubtitles].
  final String service;

  /// Lower-case ISO 639-1, e.g. `fa`.
  final String language;
  final String release;
  final String uploader;
  final bool hearingImpaired;
  final int downloads;

  /// SubDL: the zip path; SubSource: the subtitle id (zip); OpenSubtitles: the file id. Input to p04's download.
  final String ref;

  /// 0..1 token overlap between [release] and the playing file name.
  final double score;

  SubtitleResult _scored(double s) => SubtitleResult(
    service: service,
    language: language,
    release: release,
    uploader: uploader,
    hearingImpaired: hearingImpaired,
    downloads: downloads,
    ref: ref,
    score: s,
  );
}

class SubtitleSearchOutcome {
  const SubtitleSearchOutcome(this.results, this.failures, this.notSignedIn);

  final List<SubtitleResult> results;

  /// A service that was tried and failed; the others still answered.
  final Map<String, ContentSourceFailure> failures;

  /// Services the user has not signed in to (so were not searched).
  final List<String> notSignedIn;
}

/// Searches every service the user is signed in to, merges, de-duplicates and
/// ranks: language preference, then release-name match, then downloads.
class SubtitleSearch {
  SubtitleSearch({
    required this.accounts,
    required this.http,
    required this.logger,
  });

  final SubtitleAccounts accounts;
  final ProviderHttp http;
  final AppLogger logger;

  Future<SubtitleSearchOutcome> search(SubtitleQuery query) async {
    final failures = <String, ContentSourceFailure>{};
    final missing = <String>[];
    final results = <SubtitleResult>[];
    await Future.wait([
      for (final (id, run)
          in <(String, Future<List<SubtitleResult>> Function())>[
            (SubtitleAccounts.subdl, () => _subdl(query)),
            (SubtitleAccounts.subsource, () => _subsource(query)),
            (SubtitleAccounts.openSubtitles, () => _openSubtitles(query)),
          ])
        () async {
          if (!await accounts.signedIn(id)) {
            missing.add(id);
            return;
          }
          try {
            results.addAll(await run());
          } on ContentSourceFailure catch (error) {
            logger.warn('$id subtitle search failed: ${error.code}');
            failures[id] = error;
          }
        }(),
    ]);
    return SubtitleSearchOutcome(rank(results, query), failures, missing);
  }

  /// The chosen subtitle's bytes: a zip (SubDL) or a plain file
  /// (OpenSubtitles), with a file name. One OpenSubtitles download counts
  /// against the user's daily quota.
  Future<({String name, Uint8List bytes})> download(SubtitleResult r) async {
    if (r.service == SubtitleAccounts.subsource) {
      final root = accounts.subsourceRoot;
      final bytes = await http.getBytes(
        root.replace(path: '${root.path}/subtitles/${r.ref}/download'),
        headers: {
          'X-API-Key': await accounts.token(SubtitleAccounts.subsource),
        },
      );
      return (name: 'subsource-${r.ref}.zip', bytes: bytes);
    }
    if (r.service == SubtitleAccounts.subdl) {
      final root = Uri.parse('https://dl.subdl.com');
      // The ref carries no key (it ends up in widget keys and logs).
      final key = await accounts.token(SubtitleAccounts.subdl);
      final bytes = await http.getBytes(
        root.replace(path: r.ref, queryParameters: {'api_key': key}),
      );
      return (name: r.ref.split('/').last, bytes: bytes);
    }
    final root = accounts.openSubtitlesRoot;
    final headers = {
      'Api-Key': accounts.consumerKey,
      'User-Agent': 'GenoTV v1.0',
      'Accept': 'application/json',
      'Authorization':
          'Bearer ${await accounts.token(SubtitleAccounts.openSubtitles)}',
    };
    final Object? response;
    try {
      response = await http.postJson(
        root.replace(path: '${root.path}/download'),
        {'file_id': int.parse(r.ref)},
        headers: headers,
      );
    } on ContentSourceFailure catch (error) {
      // 406 = the account's daily download allowance is used up.
      if (error.cause == 406) throw ContentSourceFailure.quotaReached(406);
      rethrow;
    }
    final link = response is Map ? response['link'] : null;
    if (link is! String) throw const ContentSourceFailure.invalidResponse();
    final name = response is Map
        ? '${response['file_name'] ?? 'subtitle.srt'}'
        : 'subtitle.srt';
    return (
      name: name.contains('.') ? name : '$name.srt',
      bytes: await http.getBytes(Uri.parse(link)),
    );
  }

  static List<SubtitleResult> rank(List<SubtitleResult> all, SubtitleQuery q) {
    final wanted = _tokens(q.fileName);
    final seen = <String>{};
    final out = <SubtitleResult>[];
    for (final r in all) {
      // Same language + same release name = the same subtitle on two services.
      if (!seen.add('${r.language}|${_tokens(r.release).join('.')}')) continue;
      final have = _tokens(r.release);
      final hits = have.where(wanted.contains).length;
      out.add(r._scored(have.isEmpty ? 0 : hits / have.length));
    }
    int lang(SubtitleResult r) {
      final i = q.languages.indexOf(r.language);
      return i < 0 ? q.languages.length : i;
    }

    out.sort((a, b) {
      final byLang = lang(a).compareTo(lang(b));
      if (byLang != 0) return byLang;
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : b.downloads.compareTo(a.downloads);
    });
    return out;
  }

  static Set<String> _tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toSet();

  Future<List<SubtitleResult>> _subdl(SubtitleQuery q) async {
    final key = await accounts.token(SubtitleAccounts.subdl);
    final root = accounts.subdlRoot;
    final params = <String, String>{
      'api_key': key,
      'languages': q.languages.map((l) => l.toUpperCase()).join(','),
      if (q.imdbId != null) 'imdb_id': q.imdbId!,
      if (q.imdbId == null && q.tmdbId != null) 'tmdb_id': '${q.tmdbId}',
      if (q.imdbId == null && q.tmdbId == null) ...{
        'film_name': q.title ?? '',
        if (q.year != null) 'year': '${q.year}',
      },
      if (q.isEpisode) ...{
        'type': 'tv',
        'season_number': '${q.season}',
        'episode_number': '${q.episode}',
      },
    };
    final body = await http.getJson(
      root.replace(path: '${root.path}/subtitles', queryParameters: params),
    );
    final list = body is Map ? body['subtitles'] : null;
    if (list is! List) return const [];
    return [
      for (final s in list.whereType<Map>())
        if (s['url'] is String)
          SubtitleResult(
            service: SubtitleAccounts.subdl,
            language: '${s['language']}'.toLowerCase(),
            release: '${s['release_name'] ?? s['name'] ?? ''}',
            uploader: '${s['author'] ?? ''}',
            hearingImpaired: s['hi'] == true,
            downloads: 0,
            ref: Uri.parse(s['url'] as String).path,
          ),
    ];
  }

  // SubSource names languages in words, not ISO codes.
  static const _subsourceLanguages = {
    'en': 'english',
    'fa': 'farsi_persian',
    'ar': 'arabic',
    'fr': 'french',
    'de': 'german',
    'es': 'spanish',
    'tr': 'turkish',
    'ru': 'russian',
  };

  Future<List<SubtitleResult>> _subsource(SubtitleQuery q) async {
    final headers = {
      'X-API-Key': await accounts.token(SubtitleAccounts.subsource),
    };
    final root = accounts.subsourceRoot;
    final wanted = {
      for (final l in q.languages)
        if (_subsourceLanguages[l] != null) _subsourceLanguages[l]!: l,
    };
    if (wanted.isEmpty) return const [];
    // 1. The title (a season is its own entry for a series).
    final found = await http.getJson(
      root.replace(
        path: '${root.path}/movies/search',
        queryParameters: {
          if (q.imdbId != null) ...{
            'searchType': 'imdb',
            'imdb': q.imdbId!,
          } else ...{
            'searchType': 'text',
            'q': q.title ?? '',
            if (q.year != null) 'year': '${q.year}',
          },
          if (q.isEpisode) 'season': '${q.season}',
        },
      ),
      headers: headers,
    );
    final titles = found is Map ? found['data'] : null;
    if (titles is! List || titles.isEmpty || titles.first is! Map) {
      return const [];
    }
    final movieId = (titles.first as Map)['movieId'];
    // 2. Its subtitles in the wanted languages, most downloaded first.
    final body = await http.getJson(
      root.replace(
        path: '${root.path}/subtitles',
        queryParameters: {
          'movieId': '$movieId',
          'language': wanted.keys.join(','),
          'sort': 'popular',
          'limit': '100',
        },
      ),
      headers: headers,
    );
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    final episode = q.isEpisode
        ? RegExp('s0*${q.season}e0*${q.episode}(?![0-9])', caseSensitive: false)
        : null;
    final out = <SubtitleResult>[];
    for (final s in data.whereType<Map>()) {
      final language = wanted['${s['language']}'];
      final id = s['subtitleId'];
      if (language == null || id == null) continue;
      final info = s['releaseInfo'];
      final release = info is List && info.isNotEmpty ? '${info.first}' : '';
      // A season entry also holds other episodes: keep this one and packs.
      if (episode != null &&
          RegExp(r's\d+e\d+', caseSensitive: false).hasMatch(release) &&
          !episode.hasMatch(release)) {
        continue;
      }
      final contributors = s['contributors'];
      out.add(
        SubtitleResult(
          service: SubtitleAccounts.subsource,
          language: language,
          release: release,
          uploader: contributors is List && contributors.isNotEmpty
              ? '${(contributors.first as Map)['displayname'] ?? ''}'
              : '',
          hearingImpaired: s['hearingImpaired'] == true,
          downloads: (s['downloads'] as num?)?.toInt() ?? 0,
          ref: '$id',
        ),
      );
    }
    return out;
  }

  Future<List<SubtitleResult>> _openSubtitles(SubtitleQuery q) async {
    final root = accounts.openSubtitlesRoot;
    final imdb = q.imdbId == null
        ? null
        : '${int.parse(q.imdbId!.replaceFirst('tt', ''))}';
    // OpenSubtitles redirects unless the keys are lower-case and sorted.
    final params = <String, String>{
      'languages': q.languages.join(','),
      (q.isEpisode ? 'parent_imdb_id' : 'imdb_id'): ?imdb,
      if (imdb == null && q.tmdbId != null)
        (q.isEpisode ? 'parent_tmdb_id' : 'tmdb_id'): '${q.tmdbId}',
      if (imdb == null && q.tmdbId == null) ...{
        'query': (q.title ?? '').toLowerCase(),
        if (q.year != null) 'year': '${q.year}',
      },
      if (q.isEpisode) ...{
        'season_number': '${q.season}',
        'episode_number': '${q.episode}',
      },
    };
    final sorted = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final body = await http.getJson(
      root.replace(path: '${root.path}/subtitles', queryParameters: sorted),
      headers: {
        'Api-Key': accounts.consumerKey,
        'User-Agent': 'GenoTV v1.0',
        'Accept': 'application/json',
      },
    );
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    final out = <SubtitleResult>[];
    for (final item in data.whereType<Map>()) {
      final a = item['attributes'];
      if (a is! Map) continue;
      final files = a['files'];
      final fileId = files is List && files.isNotEmpty && files.first is Map
          ? (files.first as Map)['file_id']
          : null;
      if (fileId == null) continue;
      final uploader = a['uploader'];
      out.add(
        SubtitleResult(
          service: SubtitleAccounts.openSubtitles,
          language: '${a['language']}'.toLowerCase(),
          release: '${a['release'] ?? ''}',
          uploader: uploader is Map ? '${uploader['name'] ?? ''}' : '',
          hearingImpaired: a['hearing_impaired'] == true,
          downloads: (a['download_count'] as num?)?.toInt() ?? 0,
          ref: '$fileId',
        ),
      );
    }
    return out;
  }
}
