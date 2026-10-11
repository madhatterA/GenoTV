import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/ccloud/$name.json').readAsStringSync();

void main() {
  late HttpServer server;
  late CCloudProvider provider;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path.startsWith('/api/search/Inception/')) {
        request.response.write(_fixture('search_inception'));
      } else if (path.startsWith('/api/search/Breaking%20Bad/') ||
          path.startsWith('/api/search/Breaking Bad/')) {
        request.response.write(_fixture('search_breaking_bad'));
      } else if (path.startsWith('/api/season/by/serie/1670/')) {
        request.response.write(_fixture('seasons_breaking_bad'));
      } else if (path.startsWith(
            '/api/search/Spider%20Man%20Brand%20New%20Day/',
          ) ||
          path.startsWith('/api/search/Spider Man Brand New Day/')) {
        request.response.write(
          _fixture('search_inception')
              .replaceAll('"Inception"', '"Spider Man Brand New Day"')
              .replaceAll('"year": 2010', '"year": 2026'),
        );
      } else if (path.startsWith('/api/search/')) {
        request.response.write('{"channels":[],"posters":[]}');
      } else {
        request.response.statusCode = 500;
      }
      await request.response.close();
    });
    final live = Uri.parse('http://127.0.0.1:${server.port}');
    // First host refuses connections: proves the mirror fallback.
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadUri = Uri.parse('http://127.0.0.1:${dead.port}');
    await dead.close();
    provider = CCloudProvider(
      http: ProviderHttp(),
      logger: MemoryLogger(),
      roots: [deadUri, live],
    );
  });

  tearDown(() async {
    await provider.dispose();
    await server.close(force: true);
  });

  test('movie resolves every source, highest quality first', () async {
    final specs = await provider.resolve(
      const MediaItem(
        id: 'inception',
        title: 'Inception',
        kind: MediaKind.movie,
        year: 2010,
      ),
    );
    expect(specs, hasLength(5));
    expect(specs.first.quality, '1080p');
    expect(
      specs.first.fileHint,
      'Inception.2010.1080p.BluRay.SoftSub.DigiMoviez.mkv',
    );
    expect(specs.every((s) => s.kind == SourceKind.httpUrl), isTrue);
  });

  test('episode picks S02E03 from every season group', () async {
    final specs = await provider.resolve(
      const MediaItem(
        id: 'bb-s02e03',
        title: 'Breaking Bad',
        kind: MediaKind.episode,
        year: 2008,
        seasonNumber: 2,
        episodeNumber: 3,
      ),
    );
    expect(specs.map((s) => s.quality), ['1080p', '720p', '480p']);
    expect(specs.every((s) => s.uri.path.contains('S02E03')), isTrue);
    expect(specs.first.label, contains('فصل دوم 1080'));
  });

  test('punctuated title retries without punctuation', () async {
    final specs = await provider.resolve(
      const MediaItem(
        id: 'bnd',
        title: 'Spider-Man: Brand New Day',
        kind: MediaKind.movie,
        year: 2026,
      ),
    );
    expect(specs, hasLength(5));
  });

  test('wrong year is not matched to a different title', () async {
    await expectLater(
      provider.resolve(
        const MediaItem(
          id: 'x',
          title: 'Nothing Here',
          kind: MediaKind.movie,
          year: 1999,
        ),
      ),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.not_found',
        ),
      ),
    );
  });

  test('all hosts down surfaces a network failure', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final uri = Uri.parse('http://127.0.0.1:${dead.port}');
    await dead.close();
    final offline = CCloudProvider(
      http: ProviderHttp(),
      logger: MemoryLogger(),
      roots: [uri],
    );
    await expectLater(
      offline.resolve(
        const MediaItem(id: 'i', title: 'Inception', kind: MediaKind.movie),
      ),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.network',
        ),
      ),
    );
    await offline.dispose();
  });
}
