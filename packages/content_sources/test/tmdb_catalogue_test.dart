import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:contracts/testing/source_provider_contract.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/tmdb/$name.json').readAsStringSync();

/// A synthetic 60-title trending pool (20 per TMDB page, 3 pages) used only
/// for exercising `browse`'s offset/limit paging math — the real fixtures
/// only capture a single live page.
Map<String, dynamic> _syntheticTrendingPage(int page) {
  final start = (page - 1) * 20;
  final results = [
    for (var i = start; i < start + 20 && i < 60; i++)
      {
        'id': 9000 + i,
        'title': 'Synthetic $i',
        'release_date': '2020-01-01',
        'poster_path': '/p$i.jpg',
      },
  ];
  return {'page': page, 'total_pages': 3, 'results': results};
}

void main() {
  late HttpServer server;
  late Uri baseUrl;
  late Directory tempDir;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final path = request.uri.path;
      final page =
          int.tryParse(request.uri.queryParameters['page'] ?? '1') ?? 1;
      String body;
      switch (path) {
        case '/trending/movie/week':
          body = jsonEncode(_syntheticTrendingPage(page));
        case '/search/multi':
          final query = request.uri.queryParameters['query'];
          body = query == 'Breaking Bad'
              ? _fixture('search_breaking_bad')
              : _fixture('search_inception');
        case '/':
          body = jsonEncode({
            'Response': 'True',
            'imdbRating': '8.8',
            'Ratings': [
              {'Source': 'Rotten Tomatoes', 'Value': '87%'},
            ],
          });
        case '/movie/27205':
          body = _fixture('movie_27205');
        case '/tv/1396':
          body = _fixture('tv_1396');
        case '/tv/1396/season/2':
          body = _fixture('tv_1396_season_2');
        default:
          request.response.statusCode = 404;
          await request.response.close();
          return;
      }
      request.response.write(body);
      await request.response.close();
    });
    tempDir = await Directory.systemTemp.createTemp('tmdb-catalogue-test');
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  TmdbCatalogue catalogue() => TmdbCatalogue(
    client: TmdbClient(http: ProviderHttp(), baseUrl: baseUrl),
  );

  runSourceProviderContractTests(catalogue);

  test(
    'original language survives movie/show details and episode mapping',
    () async {
      final cat = catalogue();
      final movie = await cat.details(
        const MediaItem(
          id: 'tmdb:movie:27205',
          title: 'Inception',
          kind: MediaKind.movie,
        ),
      );
      expect(movie.originalLanguage, 'en');
      expect(movie.item.originalLanguage, 'en');
      final show = await cat.details(
        const MediaItem(
          id: 'tmdb:tv:1396',
          title: 'Breaking Bad',
          kind: MediaKind.episode,
        ),
      );
      expect(show.originalLanguage, 'en');
      expect(show.item.originalLanguage, 'en');
      final episodes = await cat.episodes(show.item, 2);
      expect(episodes, isNotEmpty);
      expect(episodes.every((e) => e.originalLanguage == 'en'), isTrue);
    },
  );

  test('id/kind: movies and shows get the documented id formats', () async {
    final page = await catalogue().browse(const BrowseQuery(limit: 1));
    expect(page.items.single.id, 'tmdb:movie:9000');
    expect(page.items.single.kind, MediaKind.movie);
  });

  test(
    'search maps movies and shows to the right kind/id/seasonNumber',
    () async {
      final movies = await catalogue().search('Inception');
      expect(
        movies.items.any(
          (i) => i.id == 'tmdb:movie:27205' && i.kind == MediaKind.movie,
        ),
        isTrue,
      );

      final shows = await catalogue().search('Breaking Bad');
      final show = shows.items.firstWhere((i) => i.id == 'tmdb:tv:1396');
      expect(show.kind, MediaKind.episode);
      expect(show.seasonNumber, isNull);
    },
  );

  test('blank search returns an empty page without a request', () async {
    final page = await catalogue().search('   ');
    expect(page.items, isEmpty);
  });

  test('resolve is always empty', () async {
    final items = await catalogue().resolve(
      const MediaItem(
        id: 'tmdb:movie:27205',
        title: 'Inception',
        kind: MediaKind.movie,
      ),
    );
    expect(items, isEmpty);
  });

  test(
    'offset/limit paging math: offset 25 limit 10 -> page 2 skip 5',
    () async {
      final page = await catalogue().browse(
        const BrowseQuery(offset: 25, limit: 10),
      );
      expect(page.items, hasLength(10));
      expect(page.items.first.id, 'tmdb:movie:9025');
      expect(page.items.last.id, 'tmdb:movie:9034');
      expect(page.hasMore, isTrue);
    },
  );

  test('season 0 is removed and seasons are ascending', () async {
    final seasons = await catalogue().seasons(
      const MediaItem(
        id: 'tmdb:tv:1396',
        title: 'Breaking Bad',
        kind: MediaKind.episode,
        tmdbId: 1396,
      ),
    );
    expect(seasons.every((s) => s.number != 0), isTrue);
    expect(
      seasons.map((s) => s.number),
      orderedEquals([...seasons.map((s) => s.number)]..sort()),
    );
  });

  test('episode subtitle formatting is S%02dE%02d · <name>', () async {
    final items = await catalogue().episodes(
      const MediaItem(
        id: 'tmdb:tv:1396',
        title: 'Breaking Bad',
        kind: MediaKind.episode,
        imdbId: 'tt0903747',
        tmdbId: 1396,
        year: 2008,
      ),
      2,
    );
    final ep3 = items.firstWhere((e) => e.episodeNumber == 3);
    expect(ep3.subtitle, 'S02E03 · Bit by a Dead Bee');
    expect(ep3.id, 'tmdb:tv:1396:s2e3');
    expect(ep3.imdbId, 'tt0903747');
    expect(ep3.title, 'Breaking Bad');
    expect(ep3.year, 2008);
  });

  test('details carry IMDb and RT ratings from OMDb', () async {
    final withOmdb = TmdbCatalogue(
      client: TmdbClient(http: ProviderHttp(), baseUrl: baseUrl),
      omdb: OmdbRatings(
        http: ProviderHttp(),
        logger: MemoryLogger(),
        baseUrl: baseUrl,
      ),
    );
    final item = (await withOmdb.search('Inception')).items.first;
    final details = await withOmdb.details(item);
    expect(details.ratings.imdb, '8.8');
    expect(details.ratings.rottenTomatoes, '87%');
    final without = await catalogue().details(item);
    expect(without.ratings.imdb, isNull);
    expect(without.ratings.rottenTomatoes, isNull);
    expect(without.ratings.tmdb, '8.4');
  });

  group('TMDB rating backup when OMDb has no score', () {
    final omdbFull = {
      'Response': 'True',
      'imdbRating': '8.8',
      'Ratings': [
        {'Source': 'Rotten Tomatoes', 'Value': '87%'},
      ],
    };

    Future<TitleRatings> ratingsWith(
      Map<String, Object?> omdbBody, {
      double? vote,
    }) async {
      final dir = await Directory.systemTemp.createTemp('vote');
      addTearDown(() => dir.delete(recursive: true));
      final omdbServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => omdbServer.close(force: true));
      omdbServer.listen((r) async {
        r.response.write(jsonEncode(omdbBody));
        await r.response.close();
      });
      final tmdbServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => tmdbServer.close(force: true));
      tmdbServer.listen((r) async {
        final movie =
            jsonDecode(_fixture('movie_27205')) as Map<String, dynamic>;
        movie['vote_average'] = vote;
        r.response.write(jsonEncode(movie));
        await r.response.close();
      });
      final cat = TmdbCatalogue(
        client: TmdbClient(
          http: ProviderHttp(),
          baseUrl: Uri.parse('http://127.0.0.1:${tmdbServer.port}'),
        ),
        omdb: OmdbRatings(
          http: ProviderHttp(),
          logger: MemoryLogger(),
          baseUrl: Uri.parse('http://127.0.0.1:${omdbServer.port}/'),
        ),
      );
      final item = (await catalogue().search('Inception')).items.first;
      return (await cat.details(item)).ratings;
    }

    test('OMDb full: IMDb and RT, no TMDB', () async {
      final r = await ratingsWith(omdbFull, vote: 7.01);
      expect((r.imdb, r.rottenTomatoes, r.tmdb), ('8.8', '87%', null));
    });

    test('OMDb IMDb only: just IMDb, no TMDB', () async {
      final r = await ratingsWith({
        'Response': 'True',
        'imdbRating': '6.2',
        'Ratings': [],
      }, vote: 7.01);
      expect((r.imdb, r.rottenTomatoes, r.tmdb), ('6.2', null, null));
    });

    test('OMDb N/A falls back to TMDB vote, one decimal', () async {
      final r = await ratingsWith({
        'Response': 'True',
        'imdbRating': 'N/A',
        'Ratings': [],
      }, vote: 7.01);
      expect((r.imdb, r.rottenTomatoes, r.tmdb), (null, null, '7.0'));
    });

    test('OMDb lookup refused falls back to TMDB vote', () async {
      final r = await ratingsWith({
        'Response': 'False',
        'Error': 'Incorrect IMDb ID.',
      }, vote: 8.374);
      expect(r.tmdb, '8.4');
    });

    test('TMDB zero or missing vote shows nothing', () async {
      const na = {'Response': 'True', 'imdbRating': 'N/A', 'Ratings': []};
      expect((await ratingsWith(na, vote: 0)).isEmpty, isTrue);
      expect((await ratingsWith(na, vote: null)).isEmpty, isTrue);
    });
  });
}
