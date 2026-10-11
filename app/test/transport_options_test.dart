import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/transport_options.dart';

SourceSpec _spec(SourceKind kind, String name) =>
    SourceSpec(kind: kind, uri: Uri.parse('https://example.com/$name'));

void main() {
  test('defaults map to an all-Auto TransportOptions', () {
    expect(
      transportOptionsFor(SettingsValues(MemorySettingsStore())),
      const TransportOptions(),
    );
  });

  test('every Streaming and Downloads choice reaches TransportOptions', () async {
    final values = SettingsValues(MemorySettingsStore());
    Future<void> set(String id, Object v) => values.write(settingById(id), v);
    await set('streaming.cacheSizeLimit', '5 GB');
    await set('streaming.quality', '4 Mbps');
    await set('downloads.bandwidthLimit', 500.0);
    await set('downloads.torrentDownLimit', 250.0);
    await set('downloads.torrentUpLimit', 100.0);
    await set('streaming.maxHttpConnections', 8.0);
    await set('streaming.connectionTimeout', 20.0);
    await set('streaming.retryCount', 3.0);
    await set('streaming.proxy', 'http://127.0.0.1:8118');
    await set('streaming.userAgent', 'Agent/1');
    await set('streaming.headers', 'X-A: 1\nbad line\n  X-B :  two words ');
    await set('streaming.tls', "Don't verify");
    await set('downloads.connectionLimit', 90.0);
    await set('downloads.peerLimit', 30.0);
    await set('downloads.seeding', 'ratio');
    await set('downloads.tracker', 'udp://t1/a\n\n http://t2/b ');
    await set('downloads.dht', false);
    await set('downloads.pex', false);
    expect(
      transportOptionsFor(values),
      const TransportOptions(
        cacheLimitBytes: 5 * 1024 * 1024 * 1024,
        streamDownloadBytesPerSecond: 500000,
        globalDownloadBytesPerSecond: 512000,
        torrentDownloadBytesPerSecond: 256000,
        torrentUploadBytesPerSecond: 102400,
        maxHttpConnections: 8,
        connectTimeoutSeconds: 20,
        retryCount: 3,
        proxy: 'http://127.0.0.1:8118',
        userAgent: 'Agent/1',
        headers: {'X-A': '1', 'X-B': 'two words'},
        verifyTls: false,
        connectionsLimit: 90,
        peerLimit: 30,
        seeding: SeedingMode.ratio,
        trackers: ['udp://t1/a', 'http://t2/b'],
        dht: false,
        pex: false,
      ),
    );
    await set('downloads.seeding', 'duration');
    expect(transportOptionsFor(values).seeding, SeedingMode.duration);
    await set('streaming.quality', 'Original');
    expect(transportOptionsFor(values).streamDownloadBytesPerSecond, 0);
  });

  test('protocol preference orders sources; Auto keeps the provider order', () {
    final http = _spec(SourceKind.httpUrl, 'a');
    final hls = _spec(SourceKind.hlsUrl, 'b');
    final magnet = _spec(SourceKind.torrentMagnet, 'c');
    final file = _spec(SourceKind.torrentFile, 'd');
    final mixed = [magnet, http, file, hls];
    expect(orderByProtocol(mixed, 'Auto'), mixed);
    expect(orderByProtocol(mixed, 'HTTP'), [http, hls, magnet, file]);
    expect(orderByProtocol(mixed, 'Torrent'), [magnet, file, http, hls]);
    expect(orderByProtocol([http, hls], 'Torrent'), [http, hls]);
  });

  test('the provider wrapper orders by the current setting', () async {
    final http = _spec(SourceKind.httpUrl, 'a');
    final magnet = _spec(SourceKind.torrentMagnet, 'c');
    var protocol = 'Auto';
    final provider = ProtocolOrderedProvider(
      _Provider([http, magnet]),
      () => protocol,
    );
    final item = MediaItem(id: 'x', title: 'x', kind: MediaKind.movie);
    expect(await provider.resolve(item), [http, magnet]);
    protocol = 'Torrent';
    expect(await provider.resolve(item), [magnet, http]);
  });
}

final class _Provider implements SourceProvider {
  _Provider(this.sources);
  final List<SourceSpec> sources;
  @override
  String get id => 'p';
  @override
  String get displayName => 'p';
  @override
  Future<MediaPage> browse(BrowseQuery query) => throw UnimplementedError();
  @override
  Future<MediaPage> search(String query, {int limit = 50}) =>
      throw UnimplementedError();
  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async => sources;
  @override
  Future<void> dispose() async {}
}
