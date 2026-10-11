import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/composition.dart';
import 'package:video_player/play_flow.dart';

const _episodes = [
  MediaItem(
    id: 's1e1',
    title: 'Pilot',
    kind: MediaKind.episode,
    seasonNumber: 1,
    episodeNumber: 1,
  ),
  MediaItem(
    id: 's1e2',
    title: 'Finale',
    kind: MediaKind.episode,
    seasonNumber: 1,
    episodeNumber: 2,
  ),
  MediaItem(
    id: 's2e1',
    title: 'Return',
    kind: MediaKind.episode,
    seasonNumber: 2,
    episodeNumber: 1,
  ),
];

SourceSpec _stream(String quality) => SourceSpec(
  kind: SourceKind.httpUrl,
  uri: Uri.parse('https://example.invalid/$quality.mp4'),
  quality: quality,
);

void main() {
  final low = _stream('720p');
  final high = _stream('1080p');

  for (final index in [0, 1]) {
    test('resolves the next loaded episode at index $index', () async {
      final provider = _Provider([low, high]);
      final resolve = AppComposition.nextEpisodeFrom(
        _episodes,
        PlayProviderEntry(id: 'selected', name: 'Selected', provider: provider),
      );

      final next = await resolve(_episodes[index], high);
      expect(next?.media, same(_episodes[index + 1]));
      expect(next?.source, same(high));
      expect(provider.requested, [same(_episodes[index + 1])]);
    });
  }

  test(
    'uses the first stream when the previous quality is unavailable',
    () async {
      final provider = _Provider([low]);
      final resolve = AppComposition.nextEpisodeFrom(
        _episodes,
        PlayProviderEntry(id: 'selected', name: 'Selected', provider: provider),
      );
      expect((await resolve(_episodes.first, high))?.source, same(low));
    },
  );

  for (final episodes in [_episodes, const <MediaItem>[]]) {
    test('terminal, missing or empty episode list does not resolve', () async {
      final provider = _Provider([high]);
      final resolve = AppComposition.nextEpisodeFrom(
        episodes,
        PlayProviderEntry(id: 'selected', name: 'Selected', provider: provider),
      );
      expect(await resolve(_episodes.last, high), isNull);
      expect(
        await resolve(
          const MediaItem(
            id: 'missing',
            title: 'Missing',
            kind: MediaKind.episode,
          ),
          high,
        ),
        isNull,
      );
      expect(provider.requested, isEmpty);
    });
  }

  test(
    'unavailable provider and empty stream list have no next source',
    () async {
      final unavailable = AppComposition.nextEpisodeFrom(
        _episodes,
        const PlayProviderEntry(
          id: 'unavailable',
          name: 'Unavailable',
          unavailableMessage: 'Unavailable',
        ),
      );
      expect(await unavailable(_episodes.first, high), isNull);

      final provider = _Provider([]);
      final empty = AppComposition.nextEpisodeFrom(
        _episodes,
        PlayProviderEntry(id: 'selected', name: 'Selected', provider: provider),
      );
      expect(await empty(_episodes.first, high), isNull);
      expect(provider.requested, [same(_episodes[1])]);
    },
  );

  test('provider failure propagates to the session', () async {
    final failure = StateError('provider unavailable');
    final provider = _Provider([], failure: failure);
    final resolve = AppComposition.nextEpisodeFrom(
      _episodes,
      PlayProviderEntry(id: 'selected', name: 'Selected', provider: provider),
    );
    await expectLater(resolve(_episodes.first, high), throwsA(same(failure)));
  });
}

final class _Provider extends FixtureProviderStub {
  _Provider(this.streams, {this.failure});

  final List<SourceSpec> streams;
  final Object? failure;
  final requested = <MediaItem>[];

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    requested.add(item);
    if (failure case final error?) throw error;
    return streams;
  }
}
