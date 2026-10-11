import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late TmdbClient client;
  final requests = <Uri>[];
  late Object Function(Uri) respond;
  setUp(() async {
    requests.clear();
    respond = (_) => {
      'results': [
        {
          'id': 1,
          'title': 'First',
          'name': 'First',
          'genre_ids': [28],
          'release_date': '2020-01-01',
          'first_air_date': '2020-01-01',
          'popularity': 1,
        },
        {
          'id': 2,
          'title': 'Second',
          'name': 'Second',
          'genre_ids': [18],
          'release_date': '2010-01-01',
          'first_air_date': '2010-01-01',
          'popularity': 2,
        },
      ],
      'total_pages': 3,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response.write(jsonEncode(respond(request.uri)));
      await request.response.close();
    });
    temp = await Directory.systemTemp.createTemp('trending-grid');
    client = TmdbClient(
      http: ProviderHttp(),
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });
  for (final tv in [false, true]) {
    test('trending $tv week endpoint, real pages, local filters', () async {
      final page = await client.titlePage(
        isTv: tv,
        trending: true,
        page: 2,
        genreIds: [28],
        yearFrom: 2019,
        sort: 'title',
      );
      expect(page.items.map((t) => t.id), [1]);
      expect(page.nextPage, 3);
      expect(requests.single.path, '/trending/${tv ? 'tv' : 'movie'}/week');
      expect(requests.single.queryParameters['page'], '2');
      expect(requests.single.queryParameters.keys, isNot(contains('sort_by')));
      expect(
        requests.single.queryParameters.keys,
        isNot(contains('with_genres')),
      );
    });
  }
  test('movie trending country resolves missing origin_country', () async {
    respond = (uri) => uri.path == '/movie/1'
        ? {
            'origin_country': ['US'],
          }
        : {
            'results': [
              {'id': 1, 'title': 'First'},
            ],
            'total_pages': 1,
          };
    expect(
      (await client.titlePage(
        isTv: false,
        trending: true,
        countryCode: 'US',
      )).items.single.id,
      1,
    );
    expect(requests.map((r) => r.path), ['/trending/movie/week', '/movie/1']);
  });
  test('person default kind dedupes clicked role credits', () async {
    respond = (_) => {
      'cast': [
        {'id': 1, 'media_type': 'movie'},
        {'id': 1, 'media_type': 'movie'},
        {'id': 2, 'media_type': 'tv'},
        {'id': 3, 'media_type': 'tv'},
      ],
      'crew': [
        {'id': 4, 'media_type': 'movie'},
        {'id': 5, 'media_type': 'movie'},
      ],
    };
    expect(await client.personCreditCounts(7), (movies: 1, tv: 2));
    expect(await client.personCreditCounts(7, crew: true), (movies: 2, tv: 0));
    expect(requests.map((r) => r.path).toSet(), {'/person/7/combined_credits'});
  });
}
