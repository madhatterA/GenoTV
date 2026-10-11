/// What a torrent does once its stream closes.
enum SeedingMode {
  /// Remove it from the session.
  off,

  /// Keep seeding until uploaded / downloaded reaches 1.0.
  ratio,

  /// Keep seeding for 30 minutes.
  duration,
}

/// Per-stream transport settings handed to `StreamSource.open`.
///
/// Every number is 0 for Auto / unlimited, every text is empty for none.
/// The `*Global*` fields and the torrent rate and connection limits are also
/// applied live to the running session; the rest take effect on the next
/// stream.
class TransportOptions {
  const TransportOptions({
    this.cacheLimitBytes,
    this.streamDownloadBytesPerSecond = 0,
    this.globalDownloadBytesPerSecond = 0,
    this.torrentDownloadBytesPerSecond = 0,
    this.torrentUploadBytesPerSecond = 0,
    this.maxHttpConnections = 0,
    this.connectTimeoutSeconds = 0,
    this.retryCount = 0,
    this.proxy = '',
    this.userAgent = '',
    this.headers = const {},
    this.verifyTls = true,
    this.connectionsLimit = 0,
    this.peerLimit = 0,
    this.seeding = SeedingMode.off,
    this.trackers = const [],
    this.dht = true,
    this.pex = true,
  });

  /// Most disk the media cache may use, in bytes. Null means Auto: the
  /// transport derives the limit from the free space of the cache volume
  /// when the stream opens.
  final int? cacheLimitBytes;

  /// Cap on this stream's download rate (aria2 `max-download-limit`, libtorrent
  /// per-torrent download limit).
  final int streamDownloadBytesPerSecond;

  /// Cap on all transfers (aria2 `max-overall-download-limit`, libtorrent
  /// session `download_rate_limit`).
  final int globalDownloadBytesPerSecond;

  /// Torrent-only caps (libtorrent `download_rate_limit` / `upload_rate_limit`);
  /// the lower of this and the global cap wins.
  final int torrentDownloadBytesPerSecond;
  final int torrentUploadBytesPerSecond;

  /// aria2 `max-connection-per-server` and `split`; 0 keeps today's 4.
  final int maxHttpConnections;

  /// aria2 `connect-timeout` / `timeout`, and `max-tries` (0 keeps aria2's).
  final int connectTimeoutSeconds;
  final int retryCount;

  /// aria2 `all-proxy`; libtorrent proxy type from the URL scheme
  /// (http or socks5).
  final String proxy;

  /// aria2 `user-agent`; libtorrent `user_agent`.
  final String userAgent;

  /// aria2 `header`. Headers a source supplies for a request still win.
  final Map<String, String> headers;

  /// aria2 `check-certificate`.
  final bool verifyTls;

  /// libtorrent `connections_limit`; per-torrent `max_connections`.
  final int connectionsLimit;
  final int peerLimit;

  final SeedingMode seeding;

  /// Extra tracker URLs appended to every torrent and magnet.
  final List<String> trackers;

  /// libtorrent `enable_dht`; `ut_pex` extension.
  final bool dht;
  final bool pex;

  List<Object?> get _fields => [
    cacheLimitBytes,
    streamDownloadBytesPerSecond,
    globalDownloadBytesPerSecond,
    torrentDownloadBytesPerSecond,
    torrentUploadBytesPerSecond,
    maxHttpConnections,
    connectTimeoutSeconds,
    retryCount,
    proxy,
    userAgent,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    verifyTls,
    connectionsLimit,
    peerLimit,
    seeding,
    Object.hashAll(trackers),
    dht,
    pex,
  ];

  @override
  bool operator ==(Object other) =>
      other is TransportOptions && _listEquals(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() => 'TransportOptions(${_fields.join(', ')})';
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
