import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live Inception and Breaking Bad sources', () async {
    final provider = DigiMoviezProvider(
      http: ProviderHttp(),
      logger: MemoryLogger(),
    );
    try {
      final movie = await provider.resolve(
        const MediaItem(
          id: 'inception',
          title: 'Inception',
          kind: MediaKind.movie,
          imdbId: 'tt1375666',
        ),
      );
      expect(movie.any((e) => e.quality == '2160p'), isTrue);
      expect(movie.any((e) => e.quality == '1080p'), isTrue);
      for (final spec in movie) {
        // ignore: avoid_print
        print(
          'movie ${spec.kind} ${spec.quality} ${spec.label} ${spec.uri.host}',
        );
      }
      final episode = await provider.resolve(
        const MediaItem(
          id: 'breaking-bad-s02e03',
          title: 'Breaking Bad',
          kind: MediaKind.episode,
          imdbId: 'tt0903747',
          seasonNumber: 2,
          episodeNumber: 3,
        ),
      );
      expect(episode, isNotEmpty);
      expect(
        episode.every((e) => e.uri.path.toUpperCase().contains('S02E03')),
        isTrue,
      );
      for (final spec in episode) {
        // ignore: avoid_print
        print(
          'episode ${spec.kind} ${spec.quality} ${spec.label} ${spec.uri.host}',
        );
      }
      final file = movie.firstWhere(
        (e) => e.uri.path.toLowerCase().endsWith('.mkv'),
      );
      final client = HttpClient()..userAgent = 'Mozilla/5.0';
      try {
        final request = await client.getUrl(file.uri);
        request.headers.set('Range', 'bytes=0-3');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(
          (await response.fold<List<int>>([], (a, b) => a..addAll(b))).take(4),
          orderedEquals([0x1a, 0x45, 0xdf, 0xa3]),
        );
      } finally {
        client.close(force: true);
      }
      await expectLater(
        provider.resolve(
          const MediaItem(
            id: 'missing',
            title: 'Missing',
            kind: MediaKind.movie,
            imdbId: 'tt0000001',
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
    } finally {
      await provider.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
