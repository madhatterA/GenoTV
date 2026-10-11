import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'package:video_player/title_grid_source.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late TmdbCatalogue catalogue;
  final requests = <Uri>[];

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('title-grid-source-');
    final token = File('${directory.path}/token')
      ..writeAsStringSync('test-key');
    catalogue = TmdbCatalogue(
      client: TmdbClient(
        http: ProviderHttp(),
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      ),
    );
    server.listen((request) async {
      requests.add(request.uri);
      final tv = request.uri.path.contains('tv');
      final item = <String, Object>{
        'id': 42,
        tv ? 'name' : 'title': 'A title',
        tv ? 'first_air_date' : 'release_date': '2020-06-01',
        'poster_path': '/poster.jpg',
        'backdrop_path': '/backdrop.jpg',
        'genre_ids': [18, 28],
        'origin_country': ['GB'],
        'popularity': 12.5,
        'vote_average': 8.5,
        'vote_count': 400,
      };
      request.response.write(
        jsonEncode(
          request.uri.path.contains('/person/')
              ? {
                  'cast': [],
                  'crew': [item],
                }
              : {
                  'page': 1,
                  'total_pages': 2,
                  'results': [item],
                },
        ),
      );
      await request.response.close();
    });
  });

  tearDown(() async {
    await catalogue.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('UI query maps to discover and preserves title metadata', () async {
    final query = TitleQuery(
      kind: TitleKind.movie,
      genreIds: [18, 28],
      countryCode: 'GB',
      yearFrom: 2010,
      yearTo: 2022,
      sort: TitleSort.rating,
    );
    final result = await loadTmdbTitlePage(catalogue, query, 1);
    expect(requests.single.path, '/discover/movie');
    expect(
      requests.single.queryParameters,
      containsPair('with_genres', '18,28'),
    );
    expect(
      requests.single.queryParameters,
      containsPair('with_origin_country', 'GB'),
    );
    expect(
      requests.single.queryParameters,
      containsPair('primary_release_date.gte', '2010-01-01'),
    );
    expect(
      requests.single.queryParameters,
      containsPair('primary_release_date.lte', '2022-12-31'),
    );
    expect(
      requests.single.queryParameters,
      containsPair('sort_by', 'vote_average.desc'),
    );
    expect(result.nextPage, 2);
    expect(result.items.single.id, 'tmdb:movie:42');
    expect(result.items.single.year, 2020);
    expect(
      result.items.single.artwork.toString(),
      contains('/w500/poster.jpg'),
    );
    final metadata = result.metadata['tmdb:movie:42']!;
    expect(metadata.popularity, 12.5);
    expect(metadata.rating, 8.5);
    expect(metadata.genreIds, [18, 28]);
    expect(metadata.countryCodes, ['GB']);
    expect(
      catalogue.backdrops['tmdb:movie:42'].toString(),
      contains('/original/backdrop.jpg'),
    );
  });

  test('TV person crew uses ruled credits path and local paging', () async {
    final result = await loadTmdbTitlePage(
      catalogue,
      TitleQuery(
        kind: TitleKind.tv,
        base: TitleBase.person,
        personId: 9,
        personRole: TitlePersonRole.crew,
        sort: TitleSort.title,
      ),
      1,
    );
    expect(requests.single.path, '/person/9/tv_credits');
    expect(result.items.single.id, 'tmdb:tv:42');
    expect(result.nextPage, isNull);
  });

  test('search base sends text to the typed search endpoint', () async {
    await loadTmdbTitlePage(
      catalogue,
      TitleQuery(
        kind: TitleKind.tv,
        base: TitleBase.search,
        searchText: 'A title',
        sort: TitleSort.releaseDate,
      ),
      1,
    );
    expect(requests.single.path, '/search/tv');
    expect(requests.single.queryParameters, containsPair('query', 'A title'));
    expect(requests.single.queryParameters.containsKey('sort_by'), isFalse);
  });
}
