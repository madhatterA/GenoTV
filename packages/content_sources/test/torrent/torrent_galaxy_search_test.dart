import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/torrent_galaxy/$name.html').readAsStringSync();

const _inception = MediaItem(
  id: 'm',
  title: 'Inception',
  kind: MediaKind.movie,
  year: 2010,
);
const _episode = MediaItem(
  id: 'e',
  title: 'Breaking Bad',
  kind: MediaKind.episode,
  seasonNumber: 2,
  episodeNumber: 3,
);

void main() {
  late HttpServer server;
  late TorrentGalaxySearch search;
  late MemoryLogger logger;
  late List<String> paths;
  // Detail pages not named here answer 500 (one failing detail page).
  late Map<String, String> details;
  var listStatus = 200;
  var listOverride = '';

  setUp(() async {
    listStatus = 200;
    listOverride = '';
    paths = [];
    details = {
      '/post-detail/974191/': 'detail_inception',
      '/post-detail/8e4b47/': 'detail_bb_s02e03',
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      paths.add(path);
      final response = request.response;
      if (path.startsWith('/get-posts/')) {
        response.statusCode = listStatus;
        response.write(
          listOverride.isNotEmpty
              ? listOverride
              : _fixture(
                  path.contains('Breaking') ? 'bb_list' : 'inception_list',
                ),
        );
      } else {
        final key = details.keys.where(path.startsWith).firstOrNull;
        if (key == null) {
          response.statusCode = 500;
        } else {
          response.write(_fixture(details[key]!));
        }
      }
      await response.close();
    });
    logger = MemoryLogger();
    search = TorrentGalaxySearch(
      http: ProviderHttp(),
      logger: logger,
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
  });
  tearDown(() => server.close(force: true));

  test('movie: filtered rows, one good detail page, failures logged', () async {
    final results = await search.search(_inception);
    expect(paths.first, '/get-posts/keywords:Inception%202010');
    expect(results, hasLength(1));
    expect(results.single.infoHash, '520f5bb299060c2cd62192e602f1c2157e9d277f');
    expect(results.single.source, 'TorrentGalaxy');
    expect(results.single.fileName, 'Inception 2010 1080p AV1 10Bit DKong.mkv');
    expect(results.single.leechers, 494);
    expect(
      logger.records.where((r) => r.message.contains('failed')),
      isNotEmpty,
    );
    // Non-matching titles (audio, software) never get a detail fetch.
    expect(paths.where((p) => p.contains('inception-with-c')), isEmpty);
  });

  test('episode: S02E03 only, other episodes never fetched', () async {
    final results = await search.search(_episode);
    expect(paths.first, '/get-posts/keywords:Breaking%20Bad%20s02');
    expect(results, hasLength(1));
    expect(results.single.releaseName, contains('S02E03'));
    expect(results.single.fileName, endsWith('H 265-XEBEC.mkv'));
    expect(results.single.infoHash, '3339d601498ddefcf100576f7da67ce8a0d47684');
    expect(paths.where((p) => p.contains('s02e04')), isEmpty);
  });

  test('every detail page failing throws, list 500 throws', () async {
    details = {};
    await expectLater(
      search.search(_inception),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.unavailable',
        ),
      ),
    );
    listStatus = 500;
    await expectLater(
      search.search(_inception),
      throwsA(isA<ContentSourceFailure>()),
    );
  });

  test('page without a table is invalidResponse; empty table is []', () async {
    listOverride = '<html><body>challenge</body></html>';
    await expectLater(
      search.search(_inception),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.invalid_response',
        ),
      ),
    );
    listOverride = '<div class="tgxtable"></div>';
    expect(await search.search(_inception), isEmpty);
  });
}
