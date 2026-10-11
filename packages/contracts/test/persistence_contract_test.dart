import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaybackProgress', () {
    test('round-trips every field through copyWith and equality', () {
      final original = PlaybackProgress(
        mediaId: 'movie-1',
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 120),
        updatedAt: DateTime.utc(2024, 1, 1),
        completed: false,
        audioTrackId: 'audio-1',
        subtitleTrackId: 'sub-1',
      );

      final copy = original.copyWith(
        position: const Duration(minutes: 20),
        completed: true,
      );

      expect(copy, isNot(original));
      expect(copy.mediaId, original.mediaId);
      expect(copy.duration, original.duration);
      expect(copy.audioTrackId, original.audioTrackId);
      expect(copy.subtitleTrackId, original.subtitleTrackId);
      expect(copy.position, const Duration(minutes: 20));
      expect(copy.completed, isTrue);

      final roundTripped = copy.copyWith(position: const Duration(minutes: 10), completed: false);
      expect(roundTripped, original);
    });

    test('rejects a non-UTC updatedAt', () {
      expect(
        () => PlaybackProgress(
          mediaId: 'movie-1',
          position: Duration.zero,
          duration: const Duration(minutes: 90),
          updatedAt: DateTime(2024, 1, 1),
          completed: false,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('preserves the instant across a timezone change', () {
      final local = DateTime(2024, 6, 15, 10, 30);
      final utc = local.toUtc();

      final progress = PlaybackProgress(
        mediaId: 'movie-1',
        position: Duration.zero,
        duration: const Duration(minutes: 90),
        updatedAt: utc,
        completed: false,
      );

      expect(progress.updatedAt.isUtc, isTrue);
      expect(progress.updatedAt.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    });
  });

  group('deriveSourceKey', () {
    SourceSpec spec({
      Map<String, String> headers = const {},
      String uri = 'https://Example.com/movie.mp4',
      String? fileHint,
    }) =>
        SourceSpec(kind: SourceKind.httpUrl, uri: Uri.parse(uri), headers: headers, fileHint: fileHint);

    test('is stable across two SourceSpecs that differ only in headers', () {
      final a = deriveSourceKey(spec(headers: const {'Authorization': 'Bearer abc'}));
      final b = deriveSourceKey(spec(headers: const {'Authorization': 'Bearer xyz-different'}));
      expect(a, b);
    });

    test('SourceSpec headers are immutable after construction', () {
      final input = <String, String>{'Authorization': 'Bearer one'};
      final value = SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('https://example.com/movie.mp4'),
        headers: input,
      );

      input['Authorization'] = 'Bearer two';
      expect(value.headers['Authorization'], 'Bearer one');
      expect(() => value.headers['X-Test'] = 'nope', throwsA(isA<UnsupportedError>()));
    });

    test('differs when uri differs', () {
      final a = deriveSourceKey(spec(uri: 'https://example.com/movie-a.mp4'));
      final b = deriveSourceKey(spec(uri: 'https://example.com/movie-b.mp4'));
      expect(a, isNot(b));
    });

    test('differs when fileHint differs', () {
      final a = deriveSourceKey(spec(fileHint: 'file-a'));
      final b = deriveSourceKey(spec(fileHint: 'file-b'));
      expect(a, isNot(b));
    });

    test('is stable across a URI differing only in host case', () {
      final a = deriveSourceKey(spec(uri: 'https://Example.com/movie.mp4'));
      final b = deriveSourceKey(spec(uri: 'https://example.com/movie.mp4'));
      expect(a, b);
    });

    test('is stable across a URI differing only in a trailing slash', () {
      final a = deriveSourceKey(spec(uri: 'https://example.com/movie'));
      final b = deriveSourceKey(spec(uri: 'https://example.com/movie/'));
      expect(a, b);
    });
  });

  group('ProviderFailure', () {
    test('is directly constructible with no pre-defined leaves', () {
      const failure = ProviderFailure(code: 'provider.fixture.unreachable', message: 'unreachable');
      expect(failure.code, 'provider.fixture.unreachable');
    });
  });

  test('MediaPage items are an immutable snapshot', () {
    final items = <MediaItem>[
      const MediaItem(id: 'one', title: 'One', kind: MediaKind.movie),
    ];
    final page = MediaPage(items: items, total: 1, hasMore: false);

    items.clear();
    expect(page.items, hasLength(1));
    expect(() => page.items.add(const MediaItem(
          id: 'two',
          title: 'Two',
          kind: MediaKind.movie,
        )), throwsA(isA<UnsupportedError>()));
  });
}
