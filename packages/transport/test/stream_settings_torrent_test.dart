import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

import 'support/settings_proof.dart';

const _hash = '0123456789abcdef0123456789abcdef01234567';

void main() {
  late Directory dir;
  late LtFfiSession session;
  late String defaultAgent;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('transport-settings-lt-');
    session = TorrentSession(savePath: dir.path).native;
    defaultAgent = session.setting('user_agent');
  });
  tearDown(() async {
    await session.dispose();
    await dir.delete(recursive: true);
  });

  void row(String setting, String value, String sent, String got, String want) {
    readbackRow(
      setting: setting,
      value: value,
      sent: sent,
      readBack: got,
      pass: got == want,
    );
    expect(got, want, reason: '$setting=$value ($sent)');
  }

  test('session settings read back from the real libtorrent session', () {
    applyTorrentSessionOptions(session, const TransportOptions(), defaultAgent);
    row(
      'downloads.bandwidthLimit',
      '0',
      'download_rate_limit=0',
      session.setting('download_rate_limit'),
      '0',
    );
    row(
      'downloads.torrentUpLimit',
      '0',
      'upload_rate_limit=0',
      session.setting('upload_rate_limit'),
      '0',
    );
    row(
      'downloads.connectionLimit',
      'Auto (0)',
      'connections_limit=60',
      session.setting('connections_limit'),
      '60',
    );
    row(
      'downloads.dht',
      'On',
      'enable_dht=1',
      session.setting('enable_dht'),
      '1',
    );
    row(
      'streaming.userAgent',
      'default',
      'user_agent=<libtorrent default>',
      session.setting('user_agent'),
      defaultAgent,
    );
    row(
      'streaming.proxy',
      'default',
      'proxy_type=0',
      session.setting('proxy_type'),
      '0',
    );

    applyTorrentSessionOptions(
      session,
      const TransportOptions(
        globalDownloadBytesPerSecond: 400000,
        torrentDownloadBytesPerSecond: 300000,
        torrentUploadBytesPerSecond: 200000,
        connectionsLimit: 80,
        dht: false,
        userAgent: 'Probe/1.0',
        proxy: 'socks5://user:pw@127.0.0.1:1080',
      ),
      defaultAgent,
    );
    row(
      'downloads.bandwidthLimit + torrentDownLimit',
      '400000 + 300000',
      'download_rate_limit=300000 (lower wins)',
      session.setting('download_rate_limit'),
      '300000',
    );
    row(
      'downloads.torrentUpLimit',
      '200000',
      'upload_rate_limit=200000',
      session.setting('upload_rate_limit'),
      '200000',
    );
    row(
      'downloads.connectionLimit',
      '80',
      'connections_limit=80',
      session.setting('connections_limit'),
      '80',
    );
    row(
      'downloads.dht',
      'Off',
      'enable_dht=0',
      session.setting('enable_dht'),
      '0',
    );
    row(
      'streaming.userAgent',
      'Probe/1.0',
      'user_agent=Probe/1.0',
      session.setting('user_agent'),
      'Probe/1.0',
    );
    row(
      'streaming.proxy',
      'socks5://user:pw@127.0.0.1:1080',
      'proxy_type=3 (socks5_pw)',
      session.setting('proxy_type'),
      '3',
    );
    row(
      'streaming.proxy',
      'socks5://user:pw@127.0.0.1:1080',
      'proxy_hostname=127.0.0.1',
      session.setting('proxy_hostname'),
      '127.0.0.1',
    );
    row(
      'streaming.proxy',
      'socks5://user:pw@127.0.0.1:1080',
      'proxy_port=1080',
      session.setting('proxy_port'),
      '1080',
    );

    applyTorrentSessionOptions(
      session,
      const TransportOptions(proxy: 'http://127.0.0.1:8118'),
      defaultAgent,
    );
    row(
      'streaming.proxy',
      'http://127.0.0.1:8118',
      'proxy_type=4 (http)',
      session.setting('proxy_type'),
      '4',
    );
    applyTorrentSessionOptions(
      session,
      const TransportOptions(globalDownloadBytesPerSecond: 150000),
      defaultAgent,
    );
    row(
      'downloads.bandwidthLimit',
      '150000',
      'download_rate_limit=150000',
      session.setting('download_rate_limit'),
      '150000',
    );
  });

  test('per-torrent options read back from the torrent handle', () {
    final torrent = session.addMagnet(
      'magnet:?xt=urn:btih:$_hash',
      savePath: dir.path,
    );
    configureTorrent(torrent, const TransportOptions());
    row(
      'streaming.quality',
      'Auto',
      'download_limit=0 (libtorrent: unlimited = -1)',
      torrent.option('download_limit'),
      '-1',
    );
    row('downloads.pex', 'On', 'pex=1', torrent.option('pex'), '1');
    final unlimited = torrent.option('max_connections');
    readbackRow(
      setting: 'downloads.peerLimit',
      value: 'Auto (0)',
      sent: 'max_connections=-1',
      readBack: unlimited,
      pass: true,
    );
    configureTorrent(
      torrent,
      const TransportOptions(
        streamDownloadBytesPerSecond: 500000,
        peerLimit: 40,
        pex: false,
        trackers: ['http://127.0.0.1:1/announce', 'udp://127.0.0.1:2/a'],
      ),
    );
    row(
      'streaming.quality',
      '4 Mbps',
      'download_limit=500000',
      torrent.option('download_limit'),
      '500000',
    );
    row(
      'downloads.peerLimit',
      '40',
      'max_connections=40',
      torrent.option('max_connections'),
      '40',
    );
    row('downloads.pex', 'Off', 'pex=0', torrent.option('pex'), '0');
    final trackers = torrent.option('tracker').split('\n');
    row(
      'downloads.tracker',
      '2 URLs',
      'add_tracker x2',
      trackers.where((t) => t.contains('127.0.0.1')).join(' '),
      'http://127.0.0.1:1/announce udp://127.0.0.1:2/a',
    );
  });

  test('seeding and live apply on a real stream', () async {
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: Directory.current.path);
    final ready = Completer<String>();
    final sub = fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('magnet=') && !ready.isCompleted) {
            ready.complete(line.substring('magnet='.length));
          }
        });
    final errors = fixture.stderr.listen((_) {});
    final cache = await dir.createTemp('seed-');
    final source = StreamSourceImpl(logger: QuietLogger(), cacheDir: cache);
    try {
      final magnet = await ready.future.timeout(const Duration(seconds: 30));
      final spec = SourceSpec(
        kind: SourceKind.torrentMagnet,
        uri: Uri.parse(magnet),
      );
      final handle = await source
          .open(
            spec,
            options: const TransportOptions(
              seeding: SeedingMode.duration,
              userAgent: 'Live/1',
            ),
          )
          .timeout(const Duration(seconds: 35));
      expect(await fetchRange(handle.playbackUri, 0, 4096), 4096);
      final native = source.nativeTorrentSession!;
      row(
        'streaming.userAgent (via open)',
        'Live/1',
        'user_agent',
        native.setting('user_agent'),
        'Live/1',
      );
      await source.applyGlobalOptions(
        const TransportOptions(
          seeding: SeedingMode.duration,
          torrentDownloadBytesPerSecond: 777000,
          torrentUploadBytesPerSecond: 333000,
          connectionsLimit: 55,
        ),
      );
      row(
        'downloads.torrentDownLimit (live)',
        '777000',
        'applyGlobalOptions',
        native.setting('download_rate_limit'),
        '777000',
      );
      row(
        'downloads.torrentUpLimit (live)',
        '333000',
        'applyGlobalOptions',
        native.setting('upload_rate_limit'),
        '333000',
      );
      row(
        'downloads.connectionLimit (live)',
        '55',
        'applyGlobalOptions',
        native.setting('connections_limit'),
        '55',
      );
      await handle.dispose();
      row(
        'downloads.seeding',
        'duration',
        'torrent kept after close',
        '${source.seedingCount}',
        '1',
      );
      // Reopening the same torrent takes it back from the seeding list.
      final again = await source
          .open(spec)
          .timeout(const Duration(seconds: 35));
      row(
        'downloads.seeding',
        'reopened',
        'seeding entry released',
        '${source.seedingCount}',
        '0',
      );
      await again.dispose();
      row(
        'downloads.seeding',
        'Off (reopened with default options)',
        'torrent removed on close',
        '${source.seedingCount}',
        '0',
      );
    } finally {
      await source.dispose();
      await sub.cancel();
      await errors.cancel();
      fixture.kill(ProcessSignal.sigterm);
      await fixture.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          fixture.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
    }
    expect(source.seedingCount, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
