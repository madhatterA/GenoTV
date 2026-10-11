import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source display fields participate in equality', () {
    final uri = Uri.parse('https://example.com/movie.mp4');
    final spec = SourceSpec(
      kind: SourceKind.httpUrl,
      uri: uri,
      label: 'BluRay · 2.4 GB',
      quality: '1080p',
    );
    final same = SourceSpec(
      kind: SourceKind.httpUrl,
      uri: uri,
      label: 'BluRay · 2.4 GB',
      quality: '1080p',
    );
    expect(spec, same);
    expect(spec.hashCode, same.hashCode);
    expect(
      spec,
      isNot(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: uri,
          label: 'WEB-DL · 2.4 GB',
          quality: '1080p',
        ),
      ),
    );
    expect(
      spec,
      isNot(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: uri,
          label: 'BluRay · 2.4 GB',
          quality: '720p',
        ),
      ),
    );
  });

  test('episode hints are optional and participate in value identity', () {
    final uri = Uri.parse('magnet:?xt=urn:btih:0123456789abcdef');
    SourceSpec episode({int? season, int? number, String? title}) => SourceSpec(
      kind: SourceKind.torrentMagnet,
      uri: uri,
      seasonNumber: season,
      episodeNumber: number,
      episodeTitle: title,
    );

    final legacy = SourceSpec(kind: SourceKind.torrentMagnet, uri: uri);
    expect(legacy.seasonNumber, isNull);
    expect(legacy.episodeNumber, isNull);
    expect(legacy.episodeTitle, isNull);
    expect(legacy, episode());
    expect(legacy.hashCode, episode().hashCode);

    final spec = episode(season: 2, number: 7, title: 'Title');
    final same = episode(season: 2, number: 7, title: 'Title');
    expect(spec, same);
    expect(spec.hashCode, same.hashCode);
    expect(<SourceSpec>{spec, same}, hasLength(1));

    final different = [
      legacy,
      episode(season: 3, number: 7, title: 'Title'),
      episode(season: 2, number: 8, title: 'Title'),
      episode(season: 2, number: 7, title: 'Other'),
      episode(number: 7, title: 'Title'),
      episode(season: 2, title: 'Title'),
      episode(season: 2, number: 7),
    ];
    for (final value in different) {
      expect(spec, isNot(value));
    }
    expect(<SourceSpec>{spec, same, ...different}, hasLength(8));
  });
}
