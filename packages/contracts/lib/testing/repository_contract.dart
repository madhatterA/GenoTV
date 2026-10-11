import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// One reusable suite per repository (§7), run by Chapter 04 against the
/// real drift implementations and by [fakes_pass_contract_test.dart]
/// against the in-memory fakes.
void runProgressRepositoryContractTests(ProgressRepository Function() create) {
  group('ProgressRepository contract', () {
    test('reading an absent key returns null, never throws', () async {
      final repo = create();
      expect(await repo.get('missing'), isNull);
    });

    test(
      'upsert then get round-trips every field, including DateTime precision',
      () async {
        final repo = create();
        final progress = PlaybackProgress(
          mediaId: 'movie-1',
          position: const Duration(minutes: 12, seconds: 34),
          duration: const Duration(hours: 2),
          updatedAt: DateTime.utc(2024, 3, 4, 5, 6, 7, 8),
          completed: false,
          audioTrackId: 'audio-1',
          subtitleTrackId: 'sub-1',
        );
        await repo.upsert(progress);
        expect(await repo.get('movie-1'), progress);
      },
    );

    test('watch emits the current value to a late subscriber and then on every change', () async {
      final repo = create();
      final first = PlaybackProgress(
        mediaId: 'movie-1',
        position: Duration.zero,
        duration: const Duration(hours: 1),
        updatedAt: DateTime.utc(2024),
        completed: false,
      );
      await repo.upsert(first);

      final seen = <PlaybackProgress>[];
      final sub = repo.watch('movie-1').listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(
        seen,
        isNotEmpty,
      ); // the late subscriber still saw the current value

      final second = first.copyWith(position: const Duration(minutes: 5));
      await repo.upsert(second);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, second);
      await sub.cancel();
    });

    test('continueWatching excludes completed items and orders by updatedAt descending', () async {
      final repo = create();
      final older = PlaybackProgress(
        mediaId: 'a',
        position: Duration.zero,
        duration: const Duration(hours: 1),
        updatedAt: DateTime.utc(2024, 1, 1),
        completed: false,
      );
      final newer = PlaybackProgress(
        mediaId: 'b',
        position: Duration.zero,
        duration: const Duration(hours: 1),
        updatedAt: DateTime.utc(2024, 1, 2),
        completed: false,
      );
      final done = PlaybackProgress(
        mediaId: 'c',
        position: Duration.zero,
        duration: const Duration(hours: 1),
        updatedAt: DateTime.utc(2024, 1, 3),
        completed: true,
      );
      await repo.upsert(older);
      await repo.upsert(newer);
      await repo.upsert(done);

      final result = await repo.continueWatching();
      expect(result.map((p) => p.mediaId).toList(), <String>['b', 'a']);
    });

    test('history includes finished and unfinished items, orders newest first and limits', () async {
      final repo = create();
      final older = PlaybackProgress(
        mediaId: 'older',
        position: const Duration(hours: 1),
        duration: const Duration(hours: 1),
        updatedAt: DateTime.utc(2024, 1, 1),
        completed: true,
      );
      final newer = older.copyWith(
        mediaId: 'newer',
        updatedAt: DateTime.utc(2024, 1, 2),
      );
      final unfinished = older.copyWith(
        mediaId: 'unfinished',
        updatedAt: DateTime.utc(2024, 1, 3),
        completed: false,
      );
      await repo.upsert(older);
      await repo.upsert(newer);
      await repo.upsert(unfinished);

      expect(await repo.history(), <PlaybackProgress>[
        unfinished,
        newer,
        older,
      ]);
      expect(await repo.history(limit: 1), <PlaybackProgress>[unfinished]);
      expect(await repo.history(limit: 0), isEmpty);
    });

    test(
      'concurrent writes to the same key do not interleave into a torn row',
      () async {
        final repo = create();
        final a = PlaybackProgress(
          mediaId: 'x',
          position: const Duration(seconds: 1),
          duration: const Duration(hours: 1),
          updatedAt: DateTime.utc(2024, 1, 1),
          completed: false,
        );
        final b = PlaybackProgress(
          mediaId: 'x',
          position: const Duration(seconds: 2),
          duration: const Duration(hours: 2),
          updatedAt: DateTime.utc(2024, 1, 2),
          completed: true,
        );
        await Future.wait(<Future<void>>[repo.upsert(a), repo.upsert(b)]);

        final result = await repo.get('x');
        expect(result == a || result == b, isTrue);
      },
    );
  });
}

void runFavouritesRepositoryContractTests(
  FavouritesRepository Function() create,
) {
  group('FavouritesRepository contract', () {
    test(
      'reading an absent key returns false / an empty list, never throws',
      () async {
        final repo = create();
        expect(await repo.isFavourite('missing'), isFalse);
        expect(await repo.all(), isEmpty);
      },
    );

    test('setFavourite then isFavourite/all round-trip', () async {
      final repo = create();
      await repo.setFavourite('movie-1', true);
      expect(await repo.isFavourite('movie-1'), isTrue);
      expect(await repo.all(), contains('movie-1'));
    });

    test('watchAll emits the current value to a late subscriber and then on every change', () async {
      final repo = create();
      final seen = <List<String>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(
        seen,
        isNotEmpty,
      ); // late subscriber still saw the current (empty) value

      await repo.setFavourite('movie-1', true);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, contains('movie-1'));
      await sub.cancel();
    });

    test(
      'concurrent writes to different keys do not interleave into a torn row',
      () async {
        final repo = create();
        await Future.wait(<Future<void>>[
          repo.setFavourite('a', true),
          repo.setFavourite('b', true),
        ]);
        expect(await repo.all(), containsAll(<String>['a', 'b']));
      },
    );
  });
}

void runNextUpRepositoryContractTests(NextUpRepository Function() create) {
  group('NextUpRepository contract', () {
    test('reading an absent key returns null, never throws', () async {
      final repo = create();
      expect(await repo.forSeries('missing'), isNull);
    });

    test('set then forSeries round-trips every field, including DateTime precision', () async {
      final repo = create();
      final entry = NextUpEntry(
        seriesId: 'series-1',
        mediaId: 'ep-2',
        season: 1,
        episode: 2,
        updatedAt: DateTime.utc(2024, 5, 6, 7, 8, 9),
      );
      await repo.set(entry);
      expect(await repo.forSeries('series-1'), entry);
    });

    test('clear removes the entry', () async {
      final repo = create();
      final entry = NextUpEntry(
        seriesId: 'series-1',
        mediaId: 'ep-2',
        season: 1,
        episode: 2,
        updatedAt: DateTime.utc(2024),
      );
      await repo.set(entry);
      await repo.clear('series-1');
      expect(await repo.forSeries('series-1'), isNull);
    });
  });
}

void runTransportStateRepositoryContractTests(
  TransportStateRepository Function() create,
) {
  group('TransportStateRepository contract', () {
    test(
      'reading an absent key returns null / an empty list, never throws',
      () async {
        final repo = create();
        expect(await repo.get('missing'), isNull);
        expect(await repo.all(), isEmpty);
        expect(await repo.torrentResumeData('missing'), isNull);
      },
    );

    test(
      'upsert then get round-trips every field, including DateTime precision',
      () async {
        final repo = create();
        final record = DownloadRecord(
          sourceKey: 'key-1',
          kind: SourceKind.httpUrl,
          filePath: '/tmp/x',
          totalBytes: 100,
          validator: 'etag-1',
          lastUsedAt: DateTime.utc(2024, 1, 1, 12),
        );
        await repo.upsert(record);
        expect(await repo.get('key-1'), record);
      },
    );

    test('torrent resume data round-trips', () async {
      final repo = create();
      final data = Uint8List.fromList(<int>[1, 2, 3]);
      await repo.putTorrentResumeData('hash-1', data);
      expect(await repo.torrentResumeData('hash-1'), data);
    });

    test(
      'concurrent writes to the same key do not interleave into a torn row',
      () async {
        final repo = create();
        final a = DownloadRecord(
          sourceKey: 'x',
          kind: SourceKind.httpUrl,
          totalBytes: 1,
          lastUsedAt: DateTime.utc(2024, 1, 1),
        );
        final b = DownloadRecord(
          sourceKey: 'x',
          kind: SourceKind.torrentMagnet,
          totalBytes: 2,
          lastUsedAt: DateTime.utc(2024, 1, 2),
        );
        await Future.wait(<Future<void>>[repo.upsert(a), repo.upsert(b)]);

        final result = await repo.get('x');
        expect(result == a || result == b, isTrue);
      },
    );
  });
}
