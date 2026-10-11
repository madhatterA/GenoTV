import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late KnabenSearch search;
  late List<String> paths;
  var status = 200;
  var override = '';

  setUp(() async {
    status = 200;
    override = '';
    paths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.statusCode = status;
      final file = request.uri.path.contains('Breaking')
          ? 'breaking_bad_s02'
          : 'inception';
      request.response.write(
        override.isNotEmpty
            ? override
            : File('test/fixtures/knaben/$file.html').readAsStringSync(),
      );
      await request.response.close();
    });
    search = KnabenSearch(
      http: ProviderHttp(),
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
  });
  tearDown(() => server.close(force: true));

  test(
    'movie fixture: query has year, results are exact-title hashes',
    () async {
      final results = await search.search(
        const MediaItem(
          id: 'm',
          title: 'Inception',
          kind: MediaKind.movie,
          year: 2010,
        ),
      );
      expect(paths.single, '/search/Inception%202010/0/1/seeders');
      expect(results.length, greaterThanOrEqualTo(3));
      expect(results.first.leechers, 66);
      expect(results.first.fileName, isNull);
      for (final r in results) {
        expect(r.infoHash, matches(RegExp(r'^[0-9a-f]{40}$')));
        expect(r.source, 'Knaben');
      }
    },
  );

  test('episode fixture: S02E03 or S02 packs only', () async {
    final results = await search.search(
      const MediaItem(
        id: 'e',
        title: 'Breaking Bad',
        kind: MediaKind.episode,
        seasonNumber: 2,
        episodeNumber: 3,
      ),
    );
    expect(paths.single, '/search/Breaking%20Bad%20s02/0/1/seeders');
    expect(results, isNotEmpty);
    for (final r in results) {
      expect(
        RegExp(
          r'S02E03|S02(?!E)|Season 2',
          caseSensitive: false,
        ).hasMatch(r.releaseName),
        isTrue,
        reason: r.releaseName,
      );
    }
  });

  test('500 response surfaces a failure, not an empty list', () async {
    status = 500;
    expect(
      search.search(
        const MediaItem(id: 'm', title: 'Inception', kind: MediaKind.movie),
      ),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.unavailable',
        ),
      ),
    );
  });

  test('page without a table is invalidResponse; empty table is []', () async {
    override = '<html><body>blocked</body></html>';
    await expectLater(
      search.search(
        const MediaItem(id: 'm', title: 'X', kind: MediaKind.movie),
      ),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.invalid_response',
        ),
      ),
    );
    override = '<table><tbody></tbody></table>';
    expect(
      await search.search(
        const MediaItem(id: 'm', title: 'X', kind: MediaKind.movie),
      ),
      isEmpty,
    );
  });

  test('unreachable server surfaces network failure', () async {
    await server.close(force: true);
    await expectLater(
      search.search(
        const MediaItem(id: 'm', title: 'X', kind: MediaKind.movie),
      ),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.network',
        ),
      ),
    );
  });
}
