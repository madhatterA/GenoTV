import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/play_flow/stream_display.dart';

SourceSpec _spec(
  String path, {
  String? quality,
  String? label,
  String? fileHint,
  SourceKind kind = SourceKind.httpUrl,
}) => SourceSpec(
  kind: kind,
  uri: Uri.parse('https://cdn.example/$path?token=private'),
  quality: quality,
  label: label,
  fileHint: fileHint,
);

void main() {
  test('torrent metadata uses retained group, peers and honest info label', () {
    final release = SourceSpec(
      kind: SourceKind.torrentMagnet,
      uri: Uri.parse('magnet:?xt=urn:btih:abc'),
      label: 'Film.2020.1080p.x265-YIFY\nRelease group: YIFY\nSeeders: 12\nLeechers: 3',
    );
    final display = parseStreamDisplay(release, providerName: 'Torrent');
    expect(display.name, 'YIFY');
    expect(display.seeders, 12);
    expect(display.fileName, 'Film.2020.1080p.x265-YIFY');
    expect(display.release, isTrue);
    final known = SourceSpec(
      kind: release.kind,
      uri: release.uri,
      label: release.label,
      fileHint: 'Film.2020.1080p.x265-YIFY.mkv',
    );
    expect(parseStreamDisplay(known, providerName: 'Torrent').release, isFalse);
  });
  test('all detected badges, release group and decoded filename', () {
    final display = parseStreamDisplay(
      _spec('Movie.2026.2160p.HDR10%2B.DV.10bit.x265.CC-CtrlHD.mkv'),
      providerName: '30nama',
    );
    expect(display.badges, ['4K', 'HDR10+', 'DV', '10-bit', 'H.265', 'CC']);
    expect(display.name, 'CtrlHD');
    expect(
      display.fileName,
      'Movie.2026.2160p.HDR10+.DV.10bit.x265.CC-CtrlHD.mkv',
    );
  });

  test(
    'structured quality and codec win over filename; missing specs stay absent',
    () {
      final display = parseStreamDisplay(
        _spec('Movie.2160p.x265.mkv', quality: '1080p', label: 'H.264'),
        providerName: 'DigiMoviez',
      );
      expect(display.badges, ['1080p', 'H.264']);
      expect(display.name, 'DigiMoviez');
    },
  );

  test('case insensitive filename variants and false positives', () {
    expect(
      parseStreamDisplay(
        _spec('Show.4K.DoVi.10BIT.HEVC.Subs-Tigole.mkv'),
        providerName: '30nama',
      ).badges,
      ['4K', 'DV', '10-bit', 'H.265', 'CC'],
    );
    expect(
      parseStreamDisplay(
        _spec('Film.720p.AVC.mkv'),
        providerName: '30nama',
      ).badges,
      ['720p', 'H.264'],
    );
    expect(
      parseStreamDisplay(
        _spec('adventure.ccc.hdrama.x2655.mkv'),
        providerName: '30nama',
      ).badges,
      isEmpty,
    );
  });

  test(
    'live-style filename detects SoftSub and group before trailing tags',
    () {
      final display = parseStreamDisplay(
        _spec(
          'Inception.2010.2160p.10bit.HDR.BluRay.x265-Pahe.SoftSub.DigiMoviez.mkv',
        ),
        providerName: 'DigiMoviez',
      );
      expect(display.badges, ['4K', 'HDR', '10-bit', 'H.265', 'CC']);
      expect(display.name, 'Pahe');
    },
  );

  test('audio tag after a hyphen is not a release group', () {
    final display = parseStreamDisplay(
      _spec('Inception_2010_2160p_HDR_x265_BluRay_REMUX_DTS-HD_FraMeSToR.mkv'),
      providerName: '30nama',
    );
    expect(display.name, '30nama');
  });

  test('provider filename hint takes priority and hides URL query', () {
    final display = parseStreamDisplay(
      _spec('opaque', fileHint: 'Actual%20Film.1080p.mkv'),
      providerName: '30nama',
    );
    expect(display.fileName, 'Actual Film.1080p.mkv');
    expect(display.badges, ['1080p']);
    expect(display.fileName, isNot(contains('private')));
  });

  test('multiple HLS variants collapse to Auto and preserve file stream', () {
    final hls720 = _spec(
      '720.m3u8',
      kind: SourceKind.hlsUrl,
      label: 'HLS 720p',
    );
    final auto = _spec('auto.m3u8', kind: SourceKind.hlsUrl, label: 'HLS Auto');
    final file = _spec('movie.mkv');
    expect(collapseHls([hls720, file, auto]), [auto, file]);
    expect(collapseHls([file]), [file]);
    expect(parseStreamDisplay(auto, providerName: '30nama').badges, ['HLS']);
  });

  test('HDR10 and HDR10Plus are told apart; lowercase names work', () {
    List<String> badges(String name) =>
        parseStreamDisplay(_spec(name), providerName: 'p').badges;
    expect(badges('film.2160p.hdr10.x265.mkv'), ['4K', 'HDR', 'H.265']);
    expect(badges('film.2160p.hdr10plus.x265.mkv'), ['4K', 'HDR10+', 'H.265']);
    expect(badges('film.1080p.web-dl.h264.mkv'), ['1080p', 'H.264']);
  });

  test('look-alike tokens are not badges', () {
    List<String> badges(String name) =>
        parseStreamDisplay(_spec(name), providerName: 'p').badges;
    expect(badges('Film.1080p.HDRip.DVDRip.mkv'), ['1080p']);
    expect(badges('Film.WEBRip.Subtitled.Extras.mkv'), isEmpty);
    expect(badges('Film.mkv'), isEmpty);
    expect(badges('Film.1080p.x264-CC.mkv'), ['1080p', 'H.264']);
    expect(badges('Film.2020.480p.x264.Subaru.mkv'), ['480p', 'H.264']);
  });

  test('a bare % in a name or hint is kept, not decoded', () {
    expect(
      streamFileName(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('https://x/a.mkv'),
          fileHint: 'Movie 100% Uncut.mkv',
        ),
      ),
      'Movie 100% Uncut.mkv',
    );
    expect(
      () => streamFileName(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('https://x/Movie%20100%25%20Uncut%.mkv'),
        ),
      ),
      returnsNormally,
    );
    expect(
      streamFileName(
        SourceSpec(
          kind: SourceKind.torrentMagnet,
          uri: Uri.parse('magnet:?xt=urn:btih:aaa&dn=Movie%20100%25%20Uncut'),
        ),
      ),
      'Movie 100% Uncut',
    );
  });

  test('site-named streams: site name, real quality, never collapsed', () {
    SourceSpec hls(String site, String q) => SourceSpec(
      kind: SourceKind.hlsUrl,
      uri: Uri.parse('https://$site.example/master.m3u8'),
      quality: q,
      fileHint: '$site · $q',
      label: 'Site: $site\n$site · $q',
    );
    final streams = [hls('CineSrc', '1080p'), hls('Movy', '2160p')];
    expect(collapseHls(streams), hasLength(2));
    final display = parseStreamDisplay(
      streams[1],
      providerName: 'Playtorrio Direct',
    );
    expect(display.name, 'Movy');
    expect(display.badges, ['4K', 'HLS']);
    expect(display.fileName, 'Movy · 2160p');
    final unnamed = [
      for (final q in ['720p', '1080p'])
        SourceSpec(
          kind: SourceKind.hlsUrl,
          uri: Uri.parse('https://a/$q.m3u8'),
          label: 'HLS · $q',
        ),
    ];
    expect(collapseHls(unnamed), hasLength(1));
  });
}
