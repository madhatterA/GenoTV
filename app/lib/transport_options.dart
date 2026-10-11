import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

const int _gib = 1024 * 1024 * 1024;
const int _kib = 1024;
const int _mbit = 125000;

/// Transport options for the next stream, from the saved settings.
TransportOptions transportOptionsFor(SettingsValues values) {
  int number(String id) => values.read<double>(settingById(id)).round();
  String text(String id) => values.read<String>(settingById(id)).trim();
  return TransportOptions(
    cacheLimitBytes: _cacheLimitBytes(text('streaming.cacheSizeLimit')),
    streamDownloadBytesPerSecond: _qualityBytes(text('streaming.quality')),
    globalDownloadBytesPerSecond: number('downloads.bandwidthLimit') * _kib,
    torrentDownloadBytesPerSecond: number('downloads.torrentDownLimit') * _kib,
    torrentUploadBytesPerSecond: number('downloads.torrentUpLimit') * _kib,
    maxHttpConnections: number('streaming.maxHttpConnections'),
    connectTimeoutSeconds: number('streaming.connectionTimeout'),
    retryCount: number('streaming.retryCount'),
    proxy: text('streaming.proxy'),
    userAgent: text('streaming.userAgent'),
    headers: parseHeaders(text('streaming.headers')),
    verifyTls: text('streaming.tls') != "Don't verify",
    connectionsLimit: number('downloads.connectionLimit'),
    peerLimit: number('downloads.peerLimit'),
    seeding: switch (text('downloads.seeding')) {
      'ratio' => SeedingMode.ratio,
      'duration' => SeedingMode.duration,
      _ => SeedingMode.off,
    },
    trackers: [
      for (final line in text('downloads.tracker').split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ],
    dht: values.read<bool>(settingById('downloads.dht')),
    pex: values.read<bool>(settingById('downloads.pex')),
  );
}

/// "Name: value" per line; a line without a colon is ignored.
Map<String, String> parseHeaders(String text) {
  final headers = <String, String>{};
  for (final line in text.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    headers[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
  }
  return headers;
}

/// Auto and Original are uncapped (no transcoding exists); "N Mbps" caps the
/// stream's transport rate.
int _qualityBytes(String choice) {
  final match = RegExp(r'^(\d+) Mbps$').firstMatch(choice);
  return match == null ? 0 : int.parse(match[1]!) * _mbit;
}

/// "Auto" leaves the choice to the transport (30% of the free space).
int? _cacheLimitBytes(String choice) => switch (choice) {
  '2 GB' => 2 * _gib,
  '5 GB' => 5 * _gib,
  '10 GB' => 10 * _gib,
  '20 GB' => 20 * _gib,
  _ => null,
};

/// Puts the preferred protocol's sources first (stable; Auto keeps the
/// provider's own order).
List<SourceSpec> orderByProtocol(List<SourceSpec> sources, String protocol) {
  bool preferred(SourceSpec s) => switch (protocol) {
    'HTTP' => s.kind == SourceKind.httpUrl || s.kind == SourceKind.hlsUrl,
    'Torrent' =>
      s.kind == SourceKind.torrentMagnet || s.kind == SourceKind.torrentFile,
    _ => false,
  };
  if (protocol != 'HTTP' && protocol != 'Torrent') return sources;
  return [...sources.where(preferred), ...sources.where((s) => !preferred(s))];
}

/// A provider whose `resolve` lists sources in the user's protocol order.
final class ProtocolOrderedProvider implements SourceProvider {
  ProtocolOrderedProvider(this._inner, this._protocol);
  final SourceProvider _inner;
  final String Function() _protocol;

  @override
  String get id => _inner.id;
  @override
  String get displayName => _inner.displayName;
  @override
  Future<MediaPage> browse(BrowseQuery query) => _inner.browse(query);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) =>
      _inner.search(query, limit: limit);
  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async =>
      orderByProtocol(await _inner.resolve(item), _protocol());
  @override
  Future<void> dispose() => _inner.dispose();
}
