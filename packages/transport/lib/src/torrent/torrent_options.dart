import 'package:contracts/contracts.dart';

import 'lt_ffi_session.dart';

// Every peer is a socket. A GUI app on macOS starts with a soft limit of 256
// descriptors for the whole process, and libtorrent's default of 200 peers
// exhausted it mid-playback (EMFILE took out logging, mpv and range reads).
const int _defaultConnections = 60;
const int _socks5 = 2;
const int _socks5Auth = 3;

int _lowest(int a, int b) => a <= 0 ? b : (b <= 0 ? a : (a < b ? a : b));

/// Applies the session-wide settings to the libtorrent session
/// (`settings_pack` names). [defaultUserAgent] is the session's own, restored
/// when the setting is empty.
void applyTorrentSessionOptions(
  LtFfiSession session,
  TransportOptions o,
  String defaultUserAgent,
) {
  final proxy = _torrentProxy(o.proxy);
  session.applySettings({
    'download_rate_limit':
        '${_lowest(o.globalDownloadBytesPerSecond, o.torrentDownloadBytesPerSecond)}',
    'upload_rate_limit': '${o.torrentUploadBytesPerSecond}',
    'connections_limit':
        '${o.connectionsLimit > 0 ? o.connectionsLimit : _defaultConnections}',
    'enable_dht': o.dht ? '1' : '0',
    'user_agent': o.userAgent.isEmpty ? defaultUserAgent : o.userAgent,
    'proxy_type': '${proxy.type}',
    'proxy_hostname': proxy.host,
    'proxy_port': '${proxy.port}',
    'proxy_username': proxy.user,
    'proxy_password': proxy.password,
    'proxy_peer_connections': proxy.type == _socks5 || proxy.type == _socks5Auth
        ? '1'
        : '0',
    'proxy_tracker_connections': '1',
  });
}

/// Applies the per-torrent limits, peer cap, PEX and extra trackers.
void configureTorrent(LtTorrent torrent, TransportOptions o) {
  torrent.applyOptions({
    'download_limit': '${o.streamDownloadBytesPerSecond}',
    'max_connections': '${o.peerLimit > 0 ? o.peerLimit : -1}',
    'pex': o.pex ? '1' : '0',
  });
  torrent.addTrackers(o.trackers);
}

({int type, String host, int port, String user, String password}) _torrentProxy(
  String url,
) {
  if (url.isEmpty) return (type: 0, host: '', port: 0, user: '', password: '');
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.host.isEmpty ||
      !const {'http', 'https', 'socks5'}.contains(uri.scheme)) {
    throw ArgumentError('proxy "$url" must be an http, https or socks5 URL');
  }
  final parts = uri.userInfo.split(':');
  final user = uri.userInfo.isEmpty ? '' : Uri.decodeComponent(parts.first);
  final password = Uri.decodeComponent(parts.skip(1).join(':'));
  final socks = uri.scheme == 'socks5';
  return (
    type: user.isEmpty ? (socks ? 2 : 4) : (socks ? 3 : 5),
    host: uri.host,
    port: uri.hasPort ? uri.port : (socks ? 1080 : 8080),
    user: user,
    password: password,
  );
}
