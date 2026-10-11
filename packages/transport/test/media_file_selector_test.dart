import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/media_file_selector.dart';
import 'package:transport/src/torrent/torrent_metadata.dart';

void main() {
  const selector = MediaFileSelector();

  test('selects the only file', () {
    expect(
      selector
          .select(
            _metadata(const [
              TorrentFile(path: 'movie.mkv', offset: 0, length: 10),
            ]),
          )
          .path,
      'movie.mkv',
    );
  });

  test('selects the largest video above the sample floor', () {
    final selected = selector.select(
      _metadata(const [
        TorrentFile(
          path: 'Sample/sample.mkv',
          offset: 0,
          length: 80 * 1024 * 1024,
        ),
        TorrentFile(
          path: 'Movie.mkv',
          offset: 80 * 1024 * 1024,
          length: 8 * 1024 * 1024 * 1024,
        ),
        TorrentFile(path: 'notes.txt', offset: 0, length: 100),
      ]),
    );
    expect(selected.path, 'Movie.mkv');
  });

  test('file hint wins and a miss names candidates', () {
    final metadata = _metadata(const [
      TorrentFile(path: 'extras/readme.txt', offset: 0, length: 10),
      TorrentFile(path: 'movie.mkv', offset: 10, length: 1000),
    ]);
    expect(
      selector.select(metadata, fileHint: 'readme.txt').path,
      'extras/readme.txt',
    );
    expect(
      () => selector.select(metadata, fileHint: 'missing'),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => '${failure.cause}',
          'candidate names',
          allOf(contains('extras/readme.txt'), contains('movie.mkv')),
        ),
      ),
    );
  });

  test('falls back to the largest non-video file', () {
    final selected = selector.select(
      _metadata(const [
        TorrentFile(path: 'small.dat', offset: 0, length: 10),
        TorrentFile(path: 'large.dat', offset: 10, length: 20),
      ]),
    );
    expect(selected.path, 'large.dat');
  });
  const mib = 1024 * 1024;
  TorrentFile file(String path, int size) =>
      TorrentFile(path: path, offset: 0, length: size * mib);
  final pack = _metadata([
    for (var episode = 1; episode <= 10; episode++)
      file(
        'Show.S02E${episode.toString().padLeft(2, '0')}.1080p.mkv',
        episode == 1 ? 4000 : 500,
      ),
    file('Sample/Show.S02E07.sample.mkv', 2000),
    file('Featurettes/Show.S02E07.mkv', 3000),
  ]);

  test('picks E07 from ten episodes and excludes sample and featurettes', () {
    expect(
      selector.select(pack, seasonNumber: 2, episodeNumber: 7).path,
      'Show.S02E07.1080p.mkv',
    );
  });

  test('picks a multi-episode range for E06', () {
    final metadata = _metadata([
      file('Show.S02E01.mkv', 4000),
      file('Show.S02E05-E08.mkv', 500),
    ]);
    expect(
      selector.select(metadata, seasonNumber: 2, episodeNumber: 6).path,
      'Show.S02E05-E08.mkv',
    );
  });

  test('gets season from the parent folder', () {
    final metadata = _metadata([
      file('Season 2/01 - Other.mkv', 4000),
      file('Season 2/07 - Title.mkv', 500),
    ]);
    expect(
      selector.select(metadata, seasonNumber: 2, episodeNumber: 7).path,
      'Season 2/07 - Title.mkv',
    );
  });

  test('omitted or partial episode hints keep largest-file behavior', () {
    for (final selected in [
      selector.select(pack),
      selector.select(pack, seasonNumber: 2),
      selector.select(pack, episodeNumber: 7),
      selector.select(pack, episodeTitle: 'Title'),
    ]) {
      expect(selected.path, 'Show.S02E01.1080p.mkv');
    }
  });

  test('matching hint wins even over a larger exact episode', () {
    final metadata = _metadata([
      file('folder/Show.S02E07.mp4', 500),
      file('Show.S02E07.mkv', 4000),
    ]);
    for (final hint in [
      'folder/Show.S02E07.mp4',
      'show.s02e07.mp4',
      'folder/',
    ]) {
      expect(
        selector
            .select(metadata, fileHint: hint, seasonNumber: 2, episodeNumber: 7)
            .path,
        'folder/Show.S02E07.mp4',
      );
    }
  });

  test('resolved wrong-episode hint yields to episode scoring', () {
    expect(
      selector
          .select(
            pack,
            fileHint: 'Show.S02E01.1080p.mkv',
            seasonNumber: 2,
            episodeNumber: 7,
          )
          .path,
      'Show.S02E07.1080p.mkv',
    );
  });

  test('unresolved hint still throws with candidate paths', () {
    expect(
      () => selector.select(
        pack,
        fileHint: 'missing',
        seasonNumber: 2,
        episodeNumber: 7,
      ),
      throwsA(
        isA<TransportFailure>().having(
          (f) => '${f.cause}',
          'candidate list',
          contains('Show.S02E07.1080p.mkv'),
        ),
      ),
    );
  });

  test('seasonless episode and seasonless range are ranked', () {
    for (final name in ['07 - Title.mkv', 'Show.E05-E08.mkv']) {
      expect(
        selector
            .select(
              _metadata([file('Show.S02E01.mkv', 4000), file(name, 500)]),
              seasonNumber: 2,
              episodeNumber: name.startsWith('07') ? 7 : 6,
            )
            .path,
        name,
      );
    }
  });

  test('episode title bonus breaks matching episode ties', () {
    expect(
      selector
          .select(
            _metadata([
              file('Show.S02E07.Other.mkv', 4000),
              file('Show.S02E07.The Title.mkv', 500),
            ]),
            seasonNumber: 2,
            episodeNumber: 7,
            episodeTitle: 'The Title',
          )
          .path,
      'Show.S02E07.The Title.mkv',
    );
  });

  test('upstream additional video and audio extensions participate', () {
    for (final ext in [
      'flv',
      'wmv',
      'iso',
      'mp3',
      'm4b',
      'm4a',
      'aac',
      'flac',
      'ogg',
      'opus',
      'wav',
      'wma',
    ]) {
      final name = 'Show.S02E07.$ext';
      expect(
        selector
            .select(
              _metadata([file('Show.S02E01.mkv', 4000), file(name, 500)]),
              seasonNumber: 2,
              episodeNumber: 7,
            )
            .path,
        name,
      );
    }
  });

  test('nonpositive episode score throws instead of largest-file fallback', () {
    final files = [
      file('Sample/Show.S02E07.mkv', 500),
      file('Show.S02E07.mkv', 1),
    ];
    expect(
      () =>
          selector.select(_metadata(files), seasonNumber: 2, episodeNumber: 7),
      throwsA(
        isA<TransportFailure>().having(
          (f) => '${f.cause}',
          'candidate list',
          allOf(contains(files[0].path), contains(files[1].path)),
        ),
      ),
    );
  });

  test(
    'wrong or unrecognized episodes fail even with size and title bonuses',
    () {
      for (final path in [
        'Show.S02E01.The Title.mkv',
        'Show.S03E07.The Title.mkv',
        'Show.S02E05-E06.The Title.mkv',
        'Show.E01.The Title.mkv',
        'Show.The Title.mkv',
        'Show.S02E070.The Title.mkv',
        'Show.S03E07.S02E07.The Title.mkv',
      ]) {
        for (final hint in [null, path]) {
          expect(
            () => selector.select(
              _metadata([file(path, 8000)]),
              fileHint: hint,
              seasonNumber: 2,
              episodeNumber: 7,
              episodeTitle: 'The Title',
            ),
            throwsA(
              isA<TransportFailure>()
                  .having(
                    (failure) => failure.code,
                    'typed failure',
                    'transport.torrent.file_not_found',
                  )
                  .having(
                    (failure) => '${failure.cause}',
                    'candidate list',
                    contains(path),
                  ),
            ),
          );
        }
      }
    },
  );

  test('a missing episode in a pack fails visibly', () {
    final files = pack.files.where((f) => !f.path.contains('S02E07')).toList();
    expect(
      () =>
          selector.select(_metadata(files), seasonNumber: 2, episodeNumber: 7),
      throwsA(isA<TransportFailure>()),
    );
  });

  test('a tiny real match cannot be replaced by a large wrong episode', () {
    expect(
      () => selector.select(
        _metadata([file('Show.S02E07.mkv', 1), file('Show.S02E01.mkv', 8000)]),
        seasonNumber: 2,
        episodeNumber: 7,
      ),
      throwsA(isA<TransportFailure>()),
    );
  });

  test('valid matches beat contradictory hints with title bonuses', () {
    final wrong = 'Show.S03E07.The Title.mkv';
    expect(
      selector
          .select(
            _metadata([file(wrong, 8000), file('Show.S02E07.Other.mkv', 500)]),
            fileHint: wrong,
            seasonNumber: 2,
            episodeNumber: 7,
            episodeTitle: 'The Title',
          )
          .path,
      'Show.S02E07.Other.mkv',
    );
  });

  test('empty torrent is rejected', () {
    expect(
      () => selector.select(_metadata([])),
      throwsA(isA<TransportFailure>()),
    );
  });
}

TorrentMetadata _metadata(List<TorrentFile> files) =>
    TorrentMetadata(files: files, pieceLength: 16 * 1024);
