import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/player/stats/stats_format.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

/// Values copied from a real read of the bundled mpv 0.36 (see
/// packages/playback/test/engine_properties_test.dart).
const _engine = <String, String>{
  'file-format': 'mkv',
  'mpv-version': 'mpv 0.36.0',
  'current-vo': 'libmpv',
  'duration': '5821.000000',
  'time-pos': '612.500000',
  'video-codec': 'hevc ((null))',
  'video-params/w': '3840',
  'video-params/h': '2160',
  'video-params/dw': '1920',
  'video-params/dh': '1080',
  'video-params/pixelformat': 'yuv420p10le',
  'video-params/primaries': 'bt.2020',
  'video-params/gamma': 'pq',
  'container-fps': '23.976000',
  'estimated-vf-fps': '23.97',
  'video-bitrate': '18500000',
  'hwdec-current': 'videotoolbox',
  'frame-drop-count': '2',
  'decoder-frame-drop-count': '1',
  'avsync': '0.0012',
  'audio-codec': 'eac3 ((null))',
  'audio-params/hr-channels': '5.1(side)',
  'audio-params/samplerate': '48000',
  'audio-bitrate': '640000',
  'audio-out-params/format': 'spdif-eac3',
  'demuxer-cache-duration': '37.5',
  'demuxer-cache-state': '{"fw-bytes":96468992,"raw-input-rate":4096000}',
  'cache-speed': '4096000',
  'current-tracks/sub/lang': 'eng',
  'current-tracks/sub/codec': 'subrip',
  'sid': '1',
};

const _httpStats = TransportStats(
  downloadBytesPerSecond: 12.4 * 1024 * 1024,
  downloadedBytes: 1288490188,
  totalBytes: 8589934592,
  connections: 4,
);

const _torrentStats = TransportStats(
  downloadBytesPerSecond: 6.2 * 1024 * 1024,
  downloadedBytes: 2147483648,
  totalBytes: 12884901888,
  torrent: TorrentStats(
    uploadBytesPerSecond: 412 * 1024,
    seeds: 18,
    peers: 42,
    swarmSeeds: 310,
    swarmPeers: 57,
    piecesHave: 1024,
    piecesTotal: 6144,
    pieceSize: 2097152,
    availability: 12.37,
    infoHash: '0123456789abcdef0123456789abcdef01234567',
  ),
);

PlayerStatsSource _source(
  SourceKind kind,
  TransportStats? stats, {
  Uri? uri,
  int Function()? reads,
  bool varied = false,
}) {
  var tick = 0;
  return PlayerStatsSource(
    kind: kind,
    uri: uri,
    providerName: 'Fixture provider',
    readTransport: stats == null
        ? null
        : () async {
            reads?.call();
            if (!varied) return stats;
            // A believable ramp-and-dip history for the sparkline.
            const wave = [.4, .7, 1.0, .85, .5, .6, .95, 1.1, .8, .3, .65, .9];
            final factor = wave[tick++ % wave.length];
            return TransportStats(
              downloadBytesPerSecond: stats.downloadBytesPerSecond * factor,
              downloadedBytes: stats.downloadedBytes,
              totalBytes: stats.totalBytes,
              connections: stats.connections,
              torrent: stats.torrent,
            );
          },
    readEngine: (names) async => {
      for (final n in names)
        if (_engine.containsKey(n)) n: _engine[n]!,
    },
  );
}

final _http = _source(
  SourceKind.httpUrl,
  _httpStats,
  varied: true,
  uri: Uri.parse('https://cdn.example.org/movie.mkv'),
);
final _torrent = _source(
  SourceKind.torrentMagnet,
  _torrentStats,
  varied: true,
  uri: Uri.parse(
    'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
  ),
);

Widget _player(PlayerStatsSource? stats) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: PlayerScreen(
    controller: FakePlaybackController()
      ..setDuration(const Duration(minutes: 96)),
    videoSurface: const FakeVideoSurface(),
    formFactor: FormFactor.desktop,
    setSystemUiMode: (_) async {},
    stats: stats,
  ),
);

void main() {
  group('formatting', () {
    test('speed, size, eta and unknown', () {
      expect(formatSpeed(0), '0 B/s');
      expect(formatSpeed(1536), '1.5 KB/s');
      expect(formatSpeed(12.4 * 1024 * 1024), '12.4 MB/s');
      expect(formatSpeed(null), '—');
      expect(formatBytes(8589934592), '8.0 GB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
      expect(formatBytes(null), '—');
      expect(formatEta(const Duration(seconds: 65)), '1:05');
      expect(
        formatEta(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '2:03:04',
      );
      expect(formatEta(null), '—');
      expect(formatProgress(1288490188, 8589934592), '1.2 GB / 8.0 GB (15%)');
      expect(formatProgress(500, null), '500 B / —');
      expect(formatCodec('h264 ((null))'), 'h264');
      expect(formatCodec(null), '—');
      expect(bitDepthOfPixelFormat('yuv420p10le'), 10);
      expect(bitDepthOfPixelFormat('p010le'), 10);
      expect(bitDepthOfPixelFormat('yuv420p'), 8);
      expect(bitDepthOfPixelFormat('nv12'), 8);
      expect(bitDepthOfPixelFormat('weird'), isNull);
      expect(
        shortInfoHash('0123456789abcdef0123456789abcdef01234567'),
        '01234567…234567',
      );
    });

    test('time left needs a size and a speed', () {
      expect(_httpStats.timeLeft, isNotNull);
      const unknownSize = TransportStats(
        downloadBytesPerSecond: 1000,
        downloadedBytes: 10,
      );
      expect(unknownSize.timeLeft, isNull);
      const stalled = TransportStats(
        downloadBytesPerSecond: 0,
        downloadedBytes: 10,
        totalBytes: 100,
      );
      expect(stalled.timeLeft, isNull);
      expect(formatEta(stalled.timeLeft), '—');
    });
  });

  group('rows', () {
    Map<String, String> flat(PlayerStatsSource source, TransportStats? t) => {
      for (final g in buildStatsGroups(
        source,
        PlayerStatsSnapshot(transport: t, engine: _engine),
      ))
        for (final r in g.rows) '${g.title}/${r.label}': r.value,
    };

    test('HTTP source and network rows', () {
      final rows = flat(_http, _httpStats);
      expect(rows['Source/Provider'], 'Fixture provider');
      expect(rows['Source/Host'], 'cdn.example.org');
      expect(rows['Source/Protocol'], 'HTTPS');
      expect(rows['Source/TLS'], 'yes');
      expect(rows['Source/Connections'], '4');
      expect(rows['Network/Speed'], '12.4 MB/s');
      expect(rows['Network/Downloaded'], '1.2 GB / 8.0 GB (15%)');
      expect(rows['Network/Time left'], isNot('—'));
      expect(rows.keys.where((k) => k.contains('Info-hash')), isEmpty);
    });

    test('plain http is HTTP/1.1 without TLS', () {
      final rows = flat(
        _source(
          SourceKind.httpUrl,
          _httpStats,
          uri: Uri.parse('http://h/x.mkv'),
        ),
        _httpStats,
      );
      expect(rows['Source/Protocol'], 'HTTP/1.1');
      expect(rows['Source/TLS'], 'no');
    });

    test('torrent rows', () {
      final rows = flat(_torrent, _torrentStats);
      expect(rows['Source/Protocol'], 'BitTorrent (magnet)');
      expect(rows['Source/Connections'], '18 seeds / 42 peers');
      expect(rows['Network/Speed down'], '6.2 MB/s');
      expect(rows['Network/Speed up'], '412 KB/s');
      expect(rows['Network/Progress'], '2.0 GB / 12.0 GB (17%)');
      expect(rows['Network/Pieces'], '1024 / 6144');
      expect(rows['Network/Piece size'], '2.0 MB');
      expect(rows['Network/Swarm (tracker)'], '310 seeds / 57 peers');
      expect(rows['Network/Availability'], '12.37');
      expect(rows['Network/Info-hash'], '01234567…234567');
    });

    test('engine rows', () {
      final rows = flat(_http, _httpStats);
      expect(rows['Buffer/Buffered ahead'], '37.5 s');
      expect(rows['Buffer/Cache in memory'], '92.0 MB');
      expect(rows['Buffer/Cache read speed'], '3.9 MB/s');
      expect(rows['Video/Codec'], 'hevc');
      expect(rows['Video/Resolution'], '3840x2160');
      expect(rows['Video/Display size'], '1920x1080');
      expect(rows['Video/Frame rate'], '23.976 fps (playing 23.97)');
      expect(rows['Video/Bitrate'], '18500 kbit/s');
      expect(rows['Video/Pixel format'], 'yuv420p10le (10-bit)');
      expect(rows['Video/Colour'], 'bt.2020 / pq');
      expect(rows['Video/Hardware decoding'], 'yes (videotoolbox)');
      expect(rows['Video/Dropped frames'], 'decoder 1, output 2');
      expect(rows['Video/A/V sync'], '1.2 ms');
      expect(rows['Audio/Codec'], 'eac3');
      expect(rows['Audio/Channels'], '5.1(side)');
      expect(rows['Audio/Sample rate'], '48000 Hz');
      expect(rows['Audio/Output'], 'passthrough (spdif-eac3)');
      expect(rows['Subtitles/Track'], 'eng · subrip');
      expect(rows['Player/Container'], 'mkv');
      expect(rows['Player/Position'], '10:12 / 1:37:01');
      expect(rows['Player/Engine'], 'mpv 0.36.0, vo libmpv');
    });

    test('unknown values read as a dash and subtitles as off', () {
      final rows = {
        for (final g in buildStatsGroups(
          _source(SourceKind.localFile, null),
          const PlayerStatsSnapshot(engine: {'sid': 'no'}),
        ))
          for (final r in g.rows) '${g.title}/${r.label}': r.value,
      };
      expect(rows['Video/Codec'], '—');
      expect(rows['Video/Bitrate'], '—');
      expect(rows['Subtitles/Track'], 'off');
      expect(rows.keys.where((k) => k.startsWith('Network')), isEmpty);
    });

    test('copy text carries every value and the full info-hash', () {
      final text = statsAsText(
        buildStatsGroups(
          _torrent,
          const PlayerStatsSnapshot(transport: _torrentStats, engine: _engine),
        ),
      );
      expect(text, contains('[Source]'));
      expect(
        text,
        contains('Info-hash: 0123456789abcdef0123456789abcdef01234567'),
      );
      expect(text, contains('Codec: hevc'));
    });
  });

  group('polling', () {
    testWidgets('reads only while a surface is open', (tester) async {
      var reads = 0;
      final controller = PlayerStatsController(
        _source(SourceKind.httpUrl, _httpStats, reads: () => reads++),
      );
      addTearDown(controller.dispose);
      await tester.pump(const Duration(seconds: 5));
      expect(reads, 0);
      controller.start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(reads, greaterThanOrEqualTo(3));
      expect(controller.snapshot.downHistory, isNotEmpty);
      controller.stop();
      final after = reads;
      await tester.pump(const Duration(seconds: 5));
      expect(reads, after);
      expect(controller.isPolling, isFalse);
    });

    testWidgets('keeps the last 30 seconds of speed', (tester) async {
      final controller = PlayerStatsController(
        _source(SourceKind.httpUrl, _httpStats),
      )..start();
      addTearDown(controller.dispose);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(controller.snapshot.downHistory.length, 30);
      controller.stop();
    });
  });

  group('player', () {
    testWidgets('no download button for local files, no key without stats', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(_player(_source(SourceKind.localFile, null)));
      await tester.pump();
      expect(find.byKey(const ValueKey('player-box-stats')), findsNothing);
      // The overlay is still reachable with the keyboard for a local file.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(find.byKey(const ValueKey('stats-overlay')), findsOneWidget);
      expect(find.text('NETWORK'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(find.byKey(const ValueKey('stats-overlay')), findsNothing);
      await tester.pumpWidget(_player(null));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(find.byKey(const ValueKey('stats-overlay')), findsNothing);
    });

    for (final torrent in [false, true]) {
      final name = torrent ? 'torrent' : 'http';
      testWidgets('$name popover, advanced overlay, close', (tester) async {
        await setLogicalSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_player(torrent ? _torrent : _http));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('player-box-stats')));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('stats-popover')), findsOneWidget);
        expect(find.text('Download speed'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('stats-popover-Time left')),
          findsOneWidget,
        );
        expect(
          find.text('Upload speed'),
          torrent ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Seeds connected'),
          torrent ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Connections'),
          torrent ? findsNothing : findsOneWidget,
        );
        await expectLater(
          find.byType(PlayerScreen),
          matchesGoldenFile('goldens/player_stats_popover_$name.png'),
        );
        await tester.tap(find.byKey(const ValueKey('stats-advanced')));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('stats-popover')), findsNothing);
        expect(find.byKey(const ValueKey('stats-overlay')), findsOneWidget);
        expect(find.byKey(const ValueKey('stats-sparkline')), findsOneWidget);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await expectLater(
          find.byType(PlayerScreen),
          matchesGoldenFile('goldens/player_stats_overlay_$name.png'),
        );
        await tester.tap(find.byKey(const ValueKey('stats-close')));
        await tester.pump();
        expect(find.byKey(const ValueKey('stats-overlay')), findsNothing);
      });
    }

    for (final size in const [Size(1280, 800), Size(800, 500)]) {
      testWidgets(
        'overlay fits ${size.width.toInt()}x${size.height.toInt()} and scrolls to its last row',
        (tester) async {
          await setLogicalSize(tester, size);
          await tester.pumpWidget(_player(_torrent));
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          final panel = tester.getRect(
            find.byKey(const ValueKey('stats-overlay')),
          );
          expect(panel.top, greaterThanOrEqualTo(0));
          expect(panel.bottom, lessThanOrEqualTo(size.height - 16 + 0.01));
          final last = find.byKey(const ValueKey('stats-Player-Engine'));
          await tester.scrollUntilVisible(
            last,
            80,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('stats-overlay')),
              matching: find.byType(Scrollable),
            ),
          );
          expect(last, findsOneWidget);
          final row = tester.getRect(last);
          expect(row.bottom, lessThanOrEqualTo(panel.bottom));
          expect(row.top, greaterThanOrEqualTo(panel.top));
        },
      );
    }

    testWidgets('copy button puts every value on the clipboard', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_player(_torrent));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('stats-copy')));
      expect(
        copied,
        contains('Info-hash: 0123456789abcdef0123456789abcdef01234567'),
      );
      expect(copied, contains('Resolution: 3840x2160'));
    });
  });
}
