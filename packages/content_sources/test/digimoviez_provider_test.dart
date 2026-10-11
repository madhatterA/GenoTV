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

String _fixture(String name, {String ext = 'json'}) =>
    File('test/fixtures/digimoviez/$name.$ext').readAsStringSync();

void main() {
  late HttpServer server;
  late Uri siteRoot;
  late Uri apiRoot;
  late File sessionFile;
  late Directory tempDir;
  String detailFixture = 'detail_movie';
  bool detailUnauthorized = false;
  bool seriesPageMatches = true;
  bool otherThingFetched = false;

  Future<void> respond(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/tt1375666/') {
      request.response.write(_fixture('movie_page_inception', ext: 'html'));
    } else if (path == '/tt0000001/') {
      request.response.statusCode = 404;
    } else if (path == '/' && request.uri.queryParameters['s'] == 'Some Film') {
      final root = 'http://127.0.0.1:${server.port}';
      request.response.write(
        '<a href="$root/other-thing-2001/">x</a>'
        '<a href="$root/some-film-2023/">y</a>',
      );
    } else if (path == '/other-thing-2001/') {
      otherThingFetched = true;
      request.response.write('<body class="postid-5"></body>');
    } else if (path == '/some-film-2023/') {
      request.response.write(
        '<body class="postid-77"><a class="imdb_icon_holder" '
        'href="https://www.imdb.com/title/tt0000002">i</a></body>',
      );
    } else if (path == '/' && request.uri.queryParameters['s'] != null) {
      final root = 'http://127.0.0.1:${server.port}';
      request.response.write(
        _fixture(
          'search_breaking_bad',
          ext: 'html',
        ).replaceAll('{{HOST}}', root),
      );
    } else if (path == '/serie/breaking-bad-1/') {
      request.response.write(
        seriesPageMatches
            ? _fixture('serie_page_breaking_bad', ext: 'html')
            : '<body class="postid-1"></body>',
      );
    } else if (path == '/api/app/v1/get_movie_detail') {
      if (detailUnauthorized) {
        request.response.statusCode = 401;
      } else {
        request.response.write(_fixture(detailFixture));
      }
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  setUp(() async {
    detailFixture = 'detail_movie';
    detailUnauthorized = false;
    seriesPageMatches = true;
    otherThingFetched = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(respond);
    siteRoot = Uri.parse('http://127.0.0.1:${server.port}');
    apiRoot = siteRoot.resolve('/api/app/v1');
    tempDir = await Directory.systemTemp.createTemp('digimoviez-test');
    sessionFile = File('${tempDir.path}/session.json');
    await sessionFile.writeAsString(jsonEncode({'auth_token': 'token'}));
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  DigiMoviezProvider provider() => DigiMoviezProvider(
    http: ProviderHttp(),
    logger: MemoryLogger(),
    sessionFile: sessionFile,
    siteRoot: siteRoot,
    apiRoot: apiRoot,
  );

  test('movie resolve dedupes online/download duplicate', () async {
    final specs = await provider().resolve(_inception);
    final urls = specs.map((s) => s.uri.toString()).toSet();
    expect(urls.length, specs.length);
    expect(specs.any((s) => s.quality == '1080p'), isTrue);
    expect(specs.any((s) => s.quality == '2160p'), isTrue);
  });

  test(
    'episode resolve keeps only S02E03 via filename and season/part fallback',
    () async {
      detailFixture = 'detail_series';
      final specs = await provider().resolve(_breakingBadS02E03);
      final urls = specs.map((s) => s.uri.toString()).toList();
      expect(urls, contains(endsWith('Show.S02E03.720p.mkv')));
      expect(urls, contains(endsWith('show-part-3.mp4')));
      expect(urls.any((u) => u.contains('S02E04')), isFalse);
      expect(urls.any((u) => u.contains('s1-part-3')), isFalse);
    },
  );

  test('series page with wrong imdb_icon_holder is skipped', () async {
    detailFixture = 'detail_series';
    seriesPageMatches = false;
    await expectLater(
      provider().resolve(_breakingBadS02E03),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.not_found',
        ),
      ),
    );
  });

  test('movie whose /imdbId/ page is 404 is found by site search, title link first', () async {
    const item = MediaItem(
      id: 'some-film',
      title: 'Some Film',
      kind: MediaKind.movie,
      imdbId: 'tt0000002',
    );
    final specs = await provider().resolve(item);
    expect(specs, isNotEmpty);
    expect(otherThingFetched, isFalse);
  });

  test('movie 404 is not_found', () async {
    const item = MediaItem(
      id: 'missing',
      title: 'Missing',
      kind: MediaKind.movie,
      imdbId: 'tt0000001',
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

  test('empty links with need_subscription is auth_required', () async {
    detailFixture = 'detail_needs_subscription';
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

  test('detail HTTP 401 is auth_required', () async {
    detailUnauthorized = true;
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
}
