import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:content_sources/src/torrent/release_text.dart' as text;
import 'package:content_sources/src/torrent/title_filter.dart';
import 'package:content_sources/src/torrent/torrent_result.dart';

void main() {
  test('torrent metadata retains group, peers and known filename at load', () {
    const item = MediaItem(id: 'm', title: 'Film', kind: MediaKind.movie);
    for (final group in ['YTS', 'YIFY', 'RARBG', 'Tigole', 'QxR', 'PSA']) {
      final result = TorrentResult.fromMagnet(
        'magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10',
        releaseName: 'Film.2020.1080p.x265-[$group]',
        source: 'Knaben',
        fileName: 'Film.2020.1080p.x265-$group.mkv',
        seeders: 12,
        leechers: 3,
      );
      expect(result.releaseGroup, group);
      final spec = result.toSourceSpec(item);
      expect(spec.fileHint, 'Film.2020.1080p.x265-$group.mkv');
      expect(spec.label, contains('Release group: $group'));
      expect(spec.label, contains('Seeders: 12'));
      expect(spec.label, contains('Leechers: 3'));
    }
    final unknown = TorrentResult.fromMagnet(
      'magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10',
      releaseName: 'Film.2020.1080p',
      source: 'Knaben',
    ).toSourceSpec(item);
    expect(unknown.fileHint, isNull);
    expect(unknown.label, contains('Release group: Torrent'));
    expect(unknown.label, isNot(contains('Leechers:')));
    expect(
      TorrentResult.fromMagnet(
        'magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10',
        releaseName: 'Film.2020.1080p',
        source: 'Knaben',
        sourceProvider: 'The Pirate Bay',
      ).releaseGroup,
      'The Pirate Bay',
    );
  });
  test('release readers preserve size, quality, codec and seeders', () {
    expect(text.sizeBytes('1.4 GB'), 1503238553);
    expect(text.sizeBytes('GiB 1,4'), 1503238553);
    expect(text.sizeBytes('2 TiB'), 2199023255552);
    expect(text.sizeBytes('400 MB'), 419430400);
    expect(text.sizeBytes('1 KB'), 1024);
    expect(text.sizeBytes('unknown'), isNull);
    expect(text.fileSize('GiB 1,4'), '1,4 GIB');
    for (final row in [
      ('2160p', '4K', 4),
      ('UHD', '4K', 4),
      ('1080p', '1080p', 3),
      ('720p', '720p', 2),
      ('480p', '480p', 1),
      ('unknown', null, 0),
    ]) {
      expect(text.quality(row.$1), row.$2);
      expect(text.qualityRank(row.$1), row.$3);
    }
    for (final row in [
      ('HEVC', 'HEVC'),
      ('x265', 'HEVC'),
      ('h.265', 'HEVC'),
      ('h265', 'HEVC'),
      ('x264', 'H.264'),
      ('h.264', 'H.264'),
      ('h264', 'H.264'),
      ('AVC', 'H.264'),
      ('AV1', 'AV1'),
      ('unknown', null),
    ]) {
      expect(text.codec(row.$1), row.$2);
    }
    for (final row in [
      ('👥 123', 123),
      ('👤 4', 4),
      ('🌱 8', 8),
      ('⚡ 9', 9),
      ('Seeders: 42', 42),
      ('5 seeds', 5),
      ('[6 s]', 6),
      ('/ 7 peers', 7),
      ('8 / 10', 8),
      ('unknown', null),
    ]) {
      expect(text.seeders(row.$1), row.$2, reason: row.$1);
    }
  });

  test('HDR and seeder readers do not accept unrelated text or emoji', () {
    for (final value in ['DVD', 'Adventure', 'SDR']) {
      expect(text.isHDR(value), isFalse, reason: value);
    }
    for (final value in ['HDR', 'HDR10+', 'Dolby Vision', 'DV']) {
      expect(text.isHDR(value), isTrue, reason: value);
    }
  });
  test('seeder emoji require exact code points', () {
    expect(text.seeders('🎬 123'), isNull);
  });

  // Real public-film magnets: https://webtorrent.io/free-torrents (2026-10-02).
  // Each source also has a case/base32 variant to prove canonical identity.
  final magnets = <(String, String)>[
    (
      'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.torrent',
      'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
    ),
    (
      'magnet:?xt=urn:btih:DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.torrent',
      'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
    ),
    (
      'magnet:?xt=urn:btih:c9e15763f722f23e98a29decdfae341b98d53056&dn=Cosmos+Laundromat&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fcosmos-laundromat.torrent',
      'c9e15763f722f23e98a29decdfae341b98d53056',
    ),
    (
      'magnet:?xt=urn:btih:C9E15763F722F23E98A29DECDFAE341B98D53056&dn=Cosmos+Laundromat&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fcosmos-laundromat.torrent',
      'c9e15763f722f23e98a29decdfae341b98d53056',
    ),
    (
      'magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10&dn=Sintel&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fsintel.torrent',
      '08ada5a7a6183aae1e09d831df6748d566095a10',
    ),
    (
      'magnet:?xt=urn:btih:BCW2LJ5GDA5K4HQJ3AY56Z2I2VTASWQQ&dn=Sintel&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fsintel.torrent',
      '08ada5a7a6183aae1e09d831df6748d566095a10',
    ),
  ];
  for (final row in magnets) {
    test('real magnet ${magnets.indexOf(row) + 1}', () {
      final result = TorrentResult.fromMagnet(
        row.$1,
        releaseName: 'Sintel 2160p',
        source: 'fixture',
        sizeBytes: 1503238553,
        seeders: 123,
      );
      expect(result.infoHash, row.$2);
      expect(result.trackers, [
        'udp://explodie.org:6969',
        'udp://tracker.coppersurfer.tk:6969',
        'udp://tracker.empire-js.us:1337',
        'udp://tracker.leechers-paradise.org:6969',
        'udp://tracker.opentrackr.org:1337',
        'wss://tracker.btorrent.xyz',
        'wss://tracker.fastcast.nz',
        'wss://tracker.openwebtorrent.com',
      ]);
      final item = MediaItem(
        id: 'sintel',
        title: 'Sintel',
        kind: MediaKind.episode,
        seasonNumber: 2,
        episodeNumber: 3,
        subtitle: 'Pilot',
      );
      final spec = result.toSourceSpec(item);
      expect(spec.kind, SourceKind.torrentMagnet);
      expect(spec.uri.queryParameters['dn'], result.releaseName);
      expect(spec.uri.queryParametersAll['tr'], result.trackers);
      expect(spec.uri.queryParameters['xt'], 'urn:btih:${row.$2}');
      expect(spec.quality, '2160p');
      expect(
        spec.label,
        'Sintel 2160p\n1.4 GB\nRelease group: Torrent\nSeeders: 123',
      );
      expect(spec.expectedBytes, 1503238553);
      expect(
        (spec.seasonNumber, spec.episodeNumber, spec.episodeTitle),
        (2, 3, 'Pilot'),
      );
      final again = TorrentResult.fromMagnet(
        spec.uri.toString(),
        releaseName: result.releaseName,
        source: result.source,
      );
      expect(again.infoHash, result.infoHash);
      expect(again.trackers, result.trackers);
      expect(
        () => result.trackers.add('udp://changed'),
        throwsUnsupportedError,
      );
    });
  }
  test('magnet name and repeated trackers survive URI encoding', () {
    const magnet =
        'magnet:?tr=https%3A%2F%2Ftracker.example%2Fannounce%3Fa%3D1%26b%3Dtwo+words&xt=URN:BTIH:BCW2LJ5GDA5K4HQJ3AY56Z2I2VTASWQQ&tr=udp%3A%2F%2Ftracker.example%3A80&tr=udp%3A%2F%2Ftracker.example%3A80';
    final result = TorrentResult.fromMagnet(
      magnet,
      releaseName: 'Sintel & Friends + extras',
      source: 'fixture',
    );
    final spec = result.toSourceSpec(
      const MediaItem(id: 's', title: 'Sintel', kind: MediaKind.movie),
    );
    expect(spec.uri.queryParameters['dn'], result.releaseName);
    expect(spec.uri.queryParametersAll['tr'], result.trackers);
    expect(
      result.trackers.first,
      'https://tracker.example/announce?a=1&b=two words',
    );
    expect(spec.expectedBytes, isNull);
    expect(spec.quality, isNull);
    expect(spec.seasonNumber, isNull);
    expect(spec.episodeTitle, isNull);
  });
  test('reject malformed magnets and invalid hash encodings', () {
    for (final value in [
      'https://example/urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10',
      'magnet:?dn=missing',
      'magnet:?xt=urn:btih:deadbeef',
      'magnet:?xt=urn:btih:ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
      'magnet:?xt=urn:btih:11111111111111111111111111111111',
      'magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10!',
    ]) {
      expect(
        () => TorrentResult.fromMagnet(
          value,
          releaseName: 'bad',
          source: 'fixture',
        ),
        throwsFormatException,
        reason: value,
      );
    }
  });

  final parser = ParseTorrentTitle();
  final rows = <(String, String, int?, int?, bool)>[
    ('Inception', 'Inception.2010.1080p.BluRay', null, null, true),
    ('Inception', 'Interstellar.2014.1080p', null, null, false),
    ('The Matrix', 'The.Matrix.1999.2160p', null, null, true),
    ('Matrix', 'The.Matrix.1999.2160p', null, null, false),
    (
      'Dune',
      'Dune.1984.1080p',
      null,
      null,
      true,
    ), // Different-year remake deliberately passes.
    ('Spider-Man', 'Spider.Man.2002.720p', null, null, true),
    (
      '2001 A Space Odyssey',
      '2001 A Space Odyssey 1968 1080p',
      null,
      null,
      true,
    ),
    ('Inception', 'Inception.Extras.2010.1080p', null, null, false),
    ('Breaking Bad', 'Breaking.Bad.S02E03.1080p', 2, 3, true),
    ('Breaking Bad', 'Breaking.Bad.S01E03.1080p', 2, 3, false),
    ('Breaking Bad', 'Breaking.Bad.S02E04.1080p', 2, 3, false),
    ('Breaking Bad', 'Breaking.Bad.S02.1080p', 2, 3, true),
    ('Breaking Bad', 'Breaking.Bad.S01.1080p', 2, 3, false),
    ('Breaking Bad', 'Breaking.Bad.E03.1080p', 2, 3, true),
    ('Breaking Bad', 'Breaking.Bad.E04.1080p', 2, 3, false),
    ('Breaking Bad', 'Breaking.Bad.1080p', 2, 3, true),
    ('Breaking Bad', 'Better.Call.Saul.S02E03.1080p', 2, 3, false),
    ('Breaking Bad', 'Breaking.Bad.S02E03.1080p', null, 3, true),
    ('Breaking Bad', 'Breaking.Bad.S02E04.1080p', 2, null, true),
    ('Breaking Bad', 'Breaking.Bad.S02E03.1080p', null, null, true),
  ];
  for (final row in rows) {
    test('filter ${rows.indexOf(row) + 1}: ${row.$2}', () {
      final item = MediaItem(
        id: 'test',
        title: row.$1,
        kind: row.$3 != null || row.$4 != null || row.$1 == 'Breaking Bad'
            ? MediaKind.episode
            : MediaKind.movie,
        year: 2021,
        seasonNumber: row.$3,
        episodeNumber: row.$4,
      );
      expect(matchesRequest(parser.parse(row.$2), item), row.$5);
    });
  }
}
