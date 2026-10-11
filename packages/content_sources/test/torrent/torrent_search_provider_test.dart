import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

const _item = MediaItem(
  id: 'e',
  title: 'Breaking Bad',
  kind: MediaKind.episode,
  seasonNumber: 2,
  episodeNumber: 3,
);

String _magnet(String hash, String name) =>
    'magnet:?xt=urn:btih:$hash&dn=$name';
const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _c = 'cccccccccccccccccccccccccccccccccccccccc';
const _d = 'dddddddddddddddddddddddddddddddddddddddd';

TorrentResult _r(String hash, String name, int seeders, String source) =>
    TorrentResult.fromMagnet(
      _magnet(hash, name),
      releaseName: name,
      source: source,
      seeders: seeders,
    );

void main() {
  late MemoryLogger logger;
  setUp(() => logger = MemoryLogger());

  TorrentSearchProvider provider(List<TorrentSearch> s) =>
      TorrentSearchProvider(searches: s, logger: logger);

  test(
    'dedupes by hash, drops 0 seeders, sorts quality then seeders',
    () async {
      final specs = await provider([
        (_) async => [
          _r(_a, 'BB S02E03 720p', 50, 'Knaben'),
          _r(_b, 'BB S02E03 1080p', 5, 'Knaben'),
          _r(_d, 'BB S02E03 1080p dead', 0, 'Knaben'),
        ],
        (_) async => [
          _r(_a.toUpperCase(), 'BB S02E03 720p again', 99, 'TGx'),
          _r(_c, 'BB S02E03 2160p', 1, 'TGx'),
          _r(_d.replaceFirst('d', 'e'), 'BB S02E03 1080p', 9, 'TGx'),
        ],
      ]).resolve(_item);
      expect(specs.map((s) => s.label!.split('\n').first), [
        'BB S02E03 2160p',
        'BB S02E03 1080p',
        'BB S02E03 1080p',
        'BB S02E03 720p',
      ]);
      expect(
        specs.map((s) => s.uri.toString().split('btih:')[1].split('&')[0]),
        [_c, _d.replaceFirst('d', 'e'), _b, _a],
      );
      expect(
        specs.every((s) => s.seasonNumber == 2 && s.episodeNumber == 3),
        isTrue,
      );
      expect(specs.every((s) => s.kind == SourceKind.torrentMagnet), isTrue);
    },
  );

  test('one failing search: other results returned, failure logged', () async {
    final specs = await provider([
      (_) async => throw const ContentSourceFailure.network(),
      (_) async => [_r(_a, 'BB 1080p', 3, 'TGx')],
    ]).resolve(_item);
    expect(specs, hasLength(1));
    expect(logger.records.any((r) => r.message.contains('failed')), isTrue);
  });

  test('both failing: first failure thrown', () async {
    await expectLater(
      provider([
        (_) async => throw const ContentSourceFailure.network(),
        (_) async => throw const ContentSourceFailure.unavailable(),
      ]).resolve(_item),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.network',
        ),
      ),
    );
  });

  test('empty title is notFound; browse/search are empty', () async {
    final p = provider([(_) async => []]);
    await expectLater(
      p.resolve(const MediaItem(id: 'x', title: ' ', kind: MediaKind.movie)),
      throwsA(
        isA<ContentSourceFailure>().having(
          (f) => f.code,
          'code',
          'provider.not_found',
        ),
      ),
    );
    expect((await p.search('x')).items, isEmpty);
    expect(p.id, 'torrents');
    expect(p.displayName, 'Torrents');
  });
}
