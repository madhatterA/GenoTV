import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late TmdbClient client;
  late List<Uri> requests;
  late Object Function(Uri) respond;
  Map<String, Object?> title(int id, {bool tv = false}) => {
    'id': id,
    tv ? 'name' : 'title': 'Title $id',
    tv ? 'first_air_date' : 'release_date': '2020-06-01',
    'genre_ids': [28, 18],
    'origin_country': ['US'],
    'popularity': id,
    'vote_average': id,
    'vote_count': 300,
  };
  setUp(() async {
    requests = [];
    respond = (_) => {
      'results': [title(1)],
      'total_pages': 2,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests.add(r.uri);
      r.response.write(jsonEncode(respond(r.uri)));
      await r.response.close();
    });
    temp = await Directory.systemTemp.createTemp('tmdb-pages');
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
    for (final sort in ['popularity', 'rating', 'releaseDate', 'title']) {
      test('discover $tv $sort exact mapping', () async {
        final result = await client.titlePage(
          isTv: tv,
          page: 2,
          genreIds: [28, 18],
          countryCode: 'US',
          yearFrom: 2000,
          yearTo: 2020,
          sort: sort,
        );
        expect(requests.single.path, '/discover/${tv ? 'tv' : 'movie'}');
        final date = tv ? 'first_air_date' : 'primary_release_date';
        expect(requests.single.queryParameters, {
          'page': '2',
          'include_adult': 'false',
          'with_genres': '28,18',
          'with_origin_country': 'US',
          '$date.gte': '2000-01-01',
          '$date.lte': '2020-12-31',
          'sort_by': switch (sort) {
            'rating' => 'vote_average.desc',
            'releaseDate' => '$date.desc',
            'title' => tv ? 'name.asc' : 'title.asc',
            _ => 'popularity.desc',
          },
          if (sort == 'rating') 'vote_count.gte': '200',
          'language': 'en-US',
        });
        expect(result.hasMore, isFalse);
      });
    }
  }
  test('movie person cast and crew mapping; cap 500', () async {
    respond = (_) => {
      'results': [title(1)],
      'total_pages': 900,
    };
    expect((await client.titlePage(isTv: false, personId: 7)).nextPage, 2);
    expect(requests.last.queryParameters['with_cast'], '7');
    expect(
      (await client.titlePage(
        isTv: false,
        personId: 7,
        crew: true,
        page: 500,
      )).hasMore,
      isFalse,
    );
    expect(requests.last.queryParameters['with_crew'], '7');
  });
  test('TV person cached, deduped, filtered, sorted and local pages', () async {
    respond = (_) => {
      'cast': [
        for (var i = 1; i <= 25; i++) title(i, tv: true),
        title(25, tv: true),
      ],
      'crew': [title(99, tv: true)],
    };
    final first = await client.titlePage(
      isTv: true,
      personId: 7,
      genreIds: [28, 18],
      countryCode: 'US',
      yearFrom: 2020,
      yearTo: 2020,
    );
    expect(first.items, hasLength(20));
    expect(first.items.first.id, 25);
    final last = await client.titlePage(isTv: true, personId: 7, page: 2);
    expect(last.items, hasLength(5));
    expect(last.hasMore, isFalse);
    expect(
      (await client.titlePage(
        isTv: true,
        personId: 7,
        crew: true,
      )).items.single.id,
      99,
    );
    expect(requests, hasLength(1));
    expect(requests.single.path, '/person/7/tv_credits');
  });
  test('search skips empty filtered pages with real continuation', () async {
    respond = (uri) => {
      'results': [
        {
          ...title(int.parse(uri.queryParameters['page']!)),
          'genre_ids': uri.queryParameters['page'] == '1' ? [18] : [28],
        },
      ],
      'total_pages': 3,
    };
    final page = await client.titlePage(
      isTv: false,
      searchText: 'hello',
      genreIds: [28],
    );
    expect(page.items.single.id, 2);
    expect(page.nextPage, 3);
    expect(requests.map((r) => r.queryParameters['page']), ['1', '2']);
    expect(requests.last.queryParameters['query'], 'hello');
    expect(requests.last.queryParameters.containsKey('with_genres'), isFalse);
  });
  test('movie search country loads origin_country details', () async {
    respond = (uri) => uri.path == '/movie/1'
        ? {
            'origin_country': ['US'],
          }
        : {
            'results': [
              {...title(1)}..remove('origin_country'),
            ],
            'total_pages': 1,
          };
    expect(
      (await client.titlePage(
        isTv: false,
        searchText: 'hello',
        countryCode: 'US',
      )).items.single.id,
      1,
    );
    expect(requests.map((r) => r.path), ['/search/movie', '/movie/1']);
  });
  test(
    'plain search never fetches movie details; empty end is final',
    () async {
      respond = (_) => {
        'results': [title(1)],
        'total_pages': 1,
      };
      expect(
        (await client.titlePage(isTv: false, searchText: 'hello')).items,
        hasLength(1),
      );
      expect(requests, hasLength(1));
      expect(
        (await client.titlePage(
          isTv: false,
          searchText: 'hello',
          genreIds: [999],
        )).hasMore,
        isFalse,
      );
    },
  );
  test('TV person local sort and filters', () async {
    respond = (_) => {
      'cast': [
        {...title(1, tv: true), 'name': 'Z'},
        {...title(2, tv: true), 'name': 'A', 'first_air_date': '2021-01-01'},
        {...title(3, tv: true), 'vote_count': 199},
      ],
    };
    expect(
      (await client.titlePage(
        isTv: true,
        personId: 1,
        sort: 'title',
      )).items.first.id,
      2,
    );
    expect(
      (await client.titlePage(
        isTv: true,
        personId: 1,
        sort: 'releaseDate',
      )).items.first.id,
      2,
    );
    expect(
      (await client.titlePage(
        isTv: true,
        personId: 1,
        sort: 'rating',
      )).items.map((t) => t.id),
      [3, 2, 1],
    );
    expect(
      (await client.titlePage(
        isTv: true,
        personId: 1,
        yearTo: 2020,
        countryCode: 'GB',
      )).items,
      isEmpty,
    );
    expect(
      (await client.titlePage(
        isTv: true,
        personId: 1,
        yearFrom: 2021,
      )).items.single.id,
      2,
    );
  });
  test('TV search filters retain low votes for local sorting', () async {
    respond = (_) => {
      'results': [
        title(1, tv: true),
        {...title(2, tv: true), 'vote_count': 199},
        {
          ...title(3, tv: true),
          'origin_country': ['GB'],
        },
        {...title(4, tv: true), 'first_air_date': '2010-01-01'},
      ],
      'total_pages': 1,
    };
    expect(
      (await client.titlePage(
        isTv: true,
        searchText: 'tv',
        countryCode: 'US',
        yearFrom: 2019,
        yearTo: 2020,
        genreIds: [28, 18],
        sort: 'rating',
      )).items.map((t) => t.id),
      [1, 2],
    );
    expect(requests.single.path, '/search/tv');
  });
  test(
    'movie detail failure surfaces instead of dropping country matches',
    () async {
      respond = (uri) => uri.path == '/movie/1'
          ? 'invalid details'
          : {
              'results': [
                {...title(1)}..remove('origin_country'),
              ],
              'total_pages': 1,
            };
      await expectLater(
        client.titlePage(isTv: false, searchText: 'hello', countryCode: 'US'),
        throwsA(isA<ContentSourceFailure>()),
      );
    },
  );
  test('empty search stops at total pages and cap500', () async {
    respond = (_) => {'results': [], 'total_pages': 999};
    expect(
      (await client.titlePage(
        isTv: true,
        searchText: 'none',
        page: 500,
      )).hasMore,
      isFalse,
    );
    expect(requests.single.queryParameters['page'], '500');
  });
  test('invalid page/sort/mixed base never sends a request', () async {
    await expectLater(
      client.titlePage(isTv: false, page: 501),
      throwsArgumentError,
    );
    await expectLater(
      client.titlePage(isTv: false, page: 0),
      throwsArgumentError,
    );
    await expectLater(
      client.titlePage(isTv: false, sort: 'bad'),
      throwsArgumentError,
    );
    await expectLater(
      client.titlePage(isTv: false, personId: 1, searchText: 'bad'),
      throwsArgumentError,
    );
    expect(requests, isEmpty);
  });
  test('options cache genres per kind and countries', () async {
    respond = (uri) => uri.path == '/configuration/countries'
        ? {}
        : {
            'genres': [
              {'id': 28, 'name': 'Action'},
            ],
          };
    expect((await client.genres(isTv: false)).single.id, 28);
    await client.genres(isTv: false);
    await client.genres(isTv: true);
    expect(requests, hasLength(2));
    final countries = await client.countries();
    expect(countries, hasLength(36));
    expect(countries.map((c) => c.code).toSet(), {
      'US',
      'GB',
      'FR',
      'DE',
      'IT',
      'ES',
      'JP',
      'KR',
      'CN',
      'HK',
      'TW',
      'IN',
      'IR',
      'TR',
      'RU',
      'CA',
      'AU',
      'MX',
      'BR',
      'AR',
      'SE',
      'DK',
      'NO',
      'FI',
      'NL',
      'BE',
      'IE',
      'PL',
      'CH',
      'AT',
      'NZ',
      'TH',
      'EG',
      'NG',
      'ZA',
      'IL',
    });
    final names = countries.map((c) => c.name).toList();
    expect(names, [...names]..sort());
    expect(() => countries.add(countries.first), throwsUnsupportedError);
    await client.countries();
    expect(requests, hasLength(2));
  });
}
