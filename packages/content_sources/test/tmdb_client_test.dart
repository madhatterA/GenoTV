import 'dart:io';
import 'dart:convert';

import 'package:content_sources/content_sources.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/tmdb/$name.json').readAsStringSync();

void main() {
  late HttpServer server;
  late Uri baseUrl;
  late Directory tempDir;
  bool unauthorized = false;

  setUp(() async {
    unauthorized = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      if (unauthorized) {
        request.response.statusCode = 401;
        await request.response.close();
        return;
      }
      // Keyless: the backup proxy adds the key (BACKUP_PROXY.md).
      expect(request.uri.queryParameters.containsKey('api_key'), isFalse);
      expect(request.uri.queryParameters['language'], 'en-US');
      final path = request.uri.path;
      if (path == '/discover/movie') {
        expect(request.uri.queryParameters['with_genres'], '28');
      }
      final body = switch (path) {
        '/trending/movie/week' => _fixture('trending_movie'),
        '/search/multi' => _fixture('search_inception'),
        '/movie/27205' => jsonEncode({
          ...jsonDecode(_fixture('movie_27205')) as Map<String, dynamic>,
          'keywords': {
            'keywords': [
              {'id': 123, 'name': 'dream'},
            ],
          },
          'credits': {
            'crew': [
              {
                'name': 'Director Name',
                'job': 'Director',
                'profile_path': '/director.jpg',
              },
            ],
            'cast': [
              {'name': 'Actor Name', 'character': 'Lead', 'profile_path': null},
            ],
          },
        }),
        '/discover/movie' => _fixture('trending_movie'),
        '/person/9/combined_credits' => jsonEncode({
          'cast': [
            {'id': 1, 'media_type': 'movie', 'title': 'Low', 'popularity': 5},
            {'id': 2, 'media_type': 'tv', 'name': 'High', 'popularity': 50},
            {'id': 1, 'media_type': 'movie', 'title': 'Low', 'popularity': 5},
            {'id': 3, 'media_type': 'person', 'name': 'Skip'},
          ],
          'crew': [
            {
              'id': 4,
              'media_type': 'movie',
              'title': 'Dir',
              'job': 'Director',
              'popularity': 20,
            },
            {'id': 5, 'media_type': 'movie', 'title': 'Cam', 'job': 'Camera'},
          ],
        }),
        '/tv/1396' => _fixture('tv_1396'),
        '/tv/1396/season/2' => _fixture('tv_1396_season_2'),
        _ => throw StateError('unexpected path $path'),
      };
      request.response.write(body);
      await request.response.close();
    });
    tempDir = await Directory.systemTemp.createTemp('tmdb-test');
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  TmdbClient client() => TmdbClient(http: ProviderHttp(), baseUrl: baseUrl);

  test('trending parses movie results', () async {
    final results = await client().trending(isTv: false);
    expect(results, isNotEmpty);
    expect(results.every((t) => !t.isTv), isTrue);
    expect(results.every((t) => t.title.isNotEmpty), isTrue);
  });

  test('searchMulti keeps movie and tv, drops person', () async {
    final results = await client().searchMulti('Inception');
    expect(results.any((t) => t.id == 27205 && !t.isTv), isTrue);
  });

  test('movie parses details including imdb id and year', () async {
    final details = await client().movie(27205);
    expect(details.imdbId, 'tt1375666');
    expect(details.year, 2010);
    expect(details.runtimeMinutes, isNotNull);
    expect(details.genres, isNotEmpty);
    expect(details.genreIds.first.id, 28);
    expect(
      details.countries.any(
        (c) => c.name == 'United Kingdom' && c.code == 'GB',
      ),
      isTrue,
    );
    expect(details.keywords.single.name, 'dream');
    expect(details.people.map((p) => p.name), ['Director Name', 'Actor Name']);
    expect(details.people.first.profilePath, '/director.jpg');
    expect(details.people.first.isCrew, isTrue);
    expect(details.people.last.isCrew, isFalse);
  });

  test('paged discover parses results with typed filters', () async {
    final page = await client().titlePage(isTv: false, genreIds: [28]);
    expect(page.items, isNotEmpty);
    await expectLater(
      client().titlePage(isTv: false, sort: 'invalid'),
      throwsArgumentError,
    );
  });

  test('tv parses details including imdb id and seasons', () async {
    final details = await client().tv(1396);
    expect(details.imdbId, 'tt0903747');
    expect(details.seasons.any((s) => s.number == 2), isTrue);
  });

  test('season parses episodes', () async {
    final detail = await client().season(1396, 2);
    expect(detail.episodes, hasLength(13));
    expect(
      detail.episodes.firstWhere((e) => e.episodeNumber == 3).name,
      'Bit by a Dead Bee',
    );
  });

  test('year rule: short or non-numeric date yields null', () {
    expect(tmdbYearOf(null), isNull);
    expect(tmdbYearOf(''), isNull);
    expect(tmdbYearOf('abc'), isNull);
    expect(tmdbYearOf('2010-07-15'), 2010);
  });

  test('HTTP 401 surfaces authRequired', () async {
    unauthorized = true;
    await expectLater(
      client().trending(isTv: false),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.auth_required',
        ),
      ),
    );
  });

  test('person credit counts separate clicked cast and crew roles', () async {
    expect(await client().personCreditCounts(9), (movies: 1, tv: 1));
    expect(await client().personCreditCounts(9, crew: true), (
      movies: 2,
      tv: 0,
    ));
  });
}
