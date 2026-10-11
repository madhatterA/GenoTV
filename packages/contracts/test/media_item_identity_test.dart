import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('external identity fields participate in equality', () {
    const item = MediaItem(
      id: 'inception',
      title: 'Inception',
      kind: MediaKind.movie,
      imdbId: 'tt1375666',
      tmdbId: 27205,
      year: 2010,
      seasonNumber: 2,
      episodeNumber: 3,
    );
    const same = MediaItem(
      id: 'inception',
      title: 'Inception',
      kind: MediaKind.movie,
      imdbId: 'tt1375666',
      tmdbId: 27205,
      year: 2010,
      seasonNumber: 2,
      episodeNumber: 3,
    );
    expect(item, same);
    expect(item.hashCode, same.hashCode);
    expect(
      item,
      isNot(
        MediaItem(
          id: 'inception',
          title: 'Inception',
          kind: MediaKind.movie,
          imdbId: 'other',
          tmdbId: 27205,
          year: 2010,
          seasonNumber: 2,
          episodeNumber: 3,
        ),
      ),
    );
    expect(
      item,
      isNot(
        MediaItem(
          id: 'inception',
          title: 'Inception',
          kind: MediaKind.movie,
          imdbId: 'tt1375666',
          tmdbId: 1,
          year: 2010,
          seasonNumber: 2,
          episodeNumber: 3,
        ),
      ),
    );
    expect(
      item,
      isNot(
        MediaItem(
          id: 'inception',
          title: 'Inception',
          kind: MediaKind.movie,
          imdbId: 'tt1375666',
          tmdbId: 27205,
          year: 2011,
          seasonNumber: 2,
          episodeNumber: 3,
        ),
      ),
    );
    expect(
      item,
      isNot(
        MediaItem(
          id: 'inception',
          title: 'Inception',
          kind: MediaKind.movie,
          imdbId: 'tt1375666',
          tmdbId: 27205,
          year: 2010,
          seasonNumber: 1,
          episodeNumber: 3,
        ),
      ),
    );
    expect(
      item,
      isNot(
        MediaItem(
          id: 'inception',
          title: 'Inception',
          kind: MediaKind.movie,
          imdbId: 'tt1375666',
          tmdbId: 27205,
          year: 2010,
          seasonNumber: 2,
          episodeNumber: 4,
        ),
      ),
    );
  });
  test('original language is nullable and participates in identity', () {
    const unknown = MediaItem(
      id: 'title',
      title: 'Title',
      kind: MediaKind.movie,
    );
    const english = MediaItem(
      id: 'title',
      title: 'Title',
      kind: MediaKind.movie,
      originalLanguage: 'en',
    );
    const same = MediaItem(
      id: 'title',
      title: 'Title',
      kind: MediaKind.movie,
      originalLanguage: 'en',
    );
    const japanese = MediaItem(
      id: 'title',
      title: 'Title',
      kind: MediaKind.movie,
      originalLanguage: 'ja',
    );
    expect(unknown.originalLanguage, isNull);
    expect(english.originalLanguage, 'en');
    expect(english, same);
    expect(english.hashCode, same.hashCode);
    expect(english, isNot(unknown));
    expect(english, isNot(japanese));
  });
}
