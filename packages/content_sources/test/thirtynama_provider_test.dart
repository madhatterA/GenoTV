import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

const _inception = MediaItem(
  id: 'inception',
  title: 'Inception',
  kind: MediaKind.movie,
  imdbId: 'tt1375666',
);

const _breakingBadS02E03 = MediaItem(
  id: 'breaking-bad-s02e03',
  title: 'Breaking Bad',
  kind: MediaKind.episode,
  imdbId: 'tt0903747',
  seasonNumber: 2,
  episodeNumber: 3,
);

String _fixture(String name) =>
    File('test/fixtures/thirtynama/$name.json').readAsStringSync();

void main() {
  late HttpServer server;
  late Uri searchUrl;
  late Uri actionUrl;
  late File sessionFile;
  late Directory tempDir;
  bool linkSuccess = true;
  final searches = <String>[];
  final imdbSearches = <String>[];

  Future<void> respond(HttpRequest request) async {
    final path = request.uri.path;
    if (path.startsWith('/action/full_search/')) {
      // Real site search: POST form `query=<imdb id>`, posts carry `imdb_id`.
      final query = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      )['query']!;
      imdbSearches.add(query);
      const ids = {'tt1375666': 8863, 'tt0903747': 1};
      request.response.write(
        query == 'tt1756855'
            ? _fixture('full_search_coyote')
            : jsonEncode({
                'success': true,
                'result': {
                  'title': {
                    'posts': [
                      if (ids.containsKey(query))
                        {'id': ids[query], 'imdb_id': query},
                    ],
                  },
                },
              }),
      );
    } else if (path == '/search') {
      final type = request.uri.queryParameters['type'];
      final filler = jsonEncode({
        'success': true,
        'data': {
          'items': [
            for (var i = 0; i < 20; i++)
              {
                'id': 'x$i',
                'ratings': {
                  'imdb': {'sub_path': '/title/tt9$i/'},
                },
              },
          ],
        },
      });
      final search = request.uri.queryParameters['search'];
      final page = request.uri.queryParameters['page'];
      searches.add(search!);
      String one(Map<String, dynamic> entry) => jsonEncode({
        'success': true,
        'data': {
          'items': [entry],
        },
      });
      final body = search == 'tt5555555' || search == 'tt31510819'
          ? jsonEncode({
              'success': true,
              'data': {'items': []},
            })
          : search == 'Paged Film'
          ? (page == '1'
                ? filler
                : one({
                    'id': 'p',
                    'ratings': {
                      'imdb': {'sub_path': '/title/tt5555555/'},
                    },
                  }))
          : search == 'Coyote Acme'
          ? one({
              'id': 444744,
              'ratings': {
                'imdb': {'sub_path': null, 'score': null, 'votes': null},
              },
              'info': {
                'en': {'title': 'Coyote vs. Acme 2026'},
              },
            })
          : search == 'tt1756855' || search == 'Coyote vs. Acme'
          ? jsonEncode({
              'success': true,
              'data': {'items': []},
            })
          : search == 'MobLand'
          ? one({
              'id': 'mob',
              'ratings': {
                'imdb': {'sub_path': null},
              },
              'info': {
                'en': {'title': 'MobLand 2025'},
              },
            })
          : type == 'series'
          ? _fixture('search_breaking_bad')
          : _fixture('search_inception');
      request.response.write(body);
    } else if (path.startsWith('/action/stream/id/')) {
      if (!linkSuccess) {
        request.response.write(jsonEncode({'success': false, 'msg': 'nope'}));
      } else {
        final isSeries = path.endsWith('/1');
        request.response.write(
          _fixture(isSeries ? 'stream_series' : 'stream_movie'),
        );
      }
    } else if (path.startsWith('/action/download/id/')) {
      if (!linkSuccess) {
        request.response.write(jsonEncode({'success': false, 'msg': 'nope'}));
      } else {
        final isSeries = path.endsWith('/1');
        request.response.write(
          _fixture(isSeries ? 'download_series' : 'download_movie'),
        );
      }
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  setUp(() async {
    linkSuccess = true;
    searches.clear();
    imdbSearches.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(respond);
    final root = Uri.parse('http://127.0.0.1:${server.port}');
    searchUrl = root.resolve('/search');
    actionUrl = root.resolve('/action');
    tempDir = await Directory.systemTemp.createTemp('thirtynama-test');
    sessionFile = File('${tempDir.path}/session.json');
    await sessionFile.writeAsString(jsonEncode({'access_token': 'token'}));
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  ThirtyNamaProvider provider() => ThirtyNamaProvider(
    http: ProviderHttp(),
    logger: MemoryLogger(),
    sessionFile: sessionFile,
    searchUrl: searchUrl,
    actionUrl: actionUrl,
  );

  test(
    'movie resolve returns hls first then quality-ordered downloads',
    () async {
      final specs = await provider().resolve(_inception);
      expect(specs.first.kind, SourceKind.hlsUrl);
      expect(specs.first.quality, '1080p');
      final file = specs.firstWhere((s) => s.kind == SourceKind.httpUrl);
      expect(file.quality, '2160p');
      expect(file.uri.toString(), contains('Movie_2160p.mkv'));
    },
  );

  test('episode resolve picks only the requested episode', () async {
    final specs = await provider().resolve(_breakingBadS02E03);
    final files = specs.where((s) => s.kind == SourceKind.httpUrl);
    expect(files, isNotEmpty);
    for (final spec in files) {
      expect(spec.uri.toString(), contains('s02e03'));
    }
    expect(specs.any((s) => s.uri.toString().contains('s02e04')), isFalse);
    expect(specs.any((s) => s.uri.toString().contains('s01e03')), isFalse);
    final hls = specs.where((s) => s.kind == SourceKind.hlsUrl);
    expect(hls.every((s) => s.uri.toString().contains('s02e03')), isTrue);
  });

  test('match on page 2 of the fuzzy title search is found', () async {
    final specs = await provider().resolve(
      const MediaItem(
        id: 'paged',
        title: 'Paged Film',
        kind: MediaKind.movie,
        imdbId: 'tt5555555',
      ),
    );
    expect(specs, isNotEmpty);
  });

  test('looks the title up with the site search by IMDb id', () async {
    await provider().resolve(_inception);
    expect(imdbSearches, ['tt1375666']);
    expect(searches, isEmpty);
  });

  test('entry with no IMDb id is found by same title and year', () async {
    final specs = await provider().resolve(
      const MediaItem(
        id: 'mob',
        title: 'MobLand',
        kind: MediaKind.movie,
        imdbId: 'tt31510819',
        year: 2025,
      ),
    );
    expect(specs, isNotEmpty);
    expect(imdbSearches, ['tt31510819']);
    expect(searches, ['MobLand']);
  });

  test(
    'Coyote vs. Acme is found by its IMDb id (real response shape)',
    () async {
      final specs = await provider().resolve(
        const MediaItem(
          id: 'coyote',
          title: 'Coyote vs. Acme',
          kind: MediaKind.movie,
          imdbId: 'tt1756855',
          year: 2026,
        ),
      );
      expect(specs, isNotEmpty);
      expect(imdbSearches, ['tt1756855']);
      expect(searches, isEmpty);
    },
  );

  test('name fallback drops the vs word', () async {
    // IMDb id the site search does not know: falls back to the name index.
    final specs = await provider().resolve(
      const MediaItem(
        id: 'coyote',
        title: 'Coyote vs. Acme',
        kind: MediaKind.movie,
        imdbId: 'tt7777777',
        year: 2026,
      ),
    );
    expect(specs, isNotEmpty);
    expect(searches, ['Coyote Acme']);
  });

  test('wrong IMDb id is not_found', () async {
    const item = MediaItem(
      id: 'x',
      title: 'Inception',
      kind: MediaKind.movie,
      imdbId: 'tt9999999',
    );
    await expectLater(
      provider().resolve(item),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.not_found',
        ),
      ),
    );
  });

  test('link failure is auth_required', () async {
    linkSuccess = false;
    await expectLater(
      provider().resolve(_inception),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.auth_required',
        ),
      ),
    );
  });

  test('missing session file is auth_required', () async {
    await sessionFile.delete();
    await expectLater(
      provider().resolve(_inception),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.auth_required',
        ),
      ),
    );
  });

  test('item without imdbId is not_found', () async {
    const item = MediaItem(id: 'x', title: 'No Id', kind: MediaKind.movie);
    await expectLater(
      provider().resolve(item),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.not_found',
        ),
      ),
    );
  });
}
