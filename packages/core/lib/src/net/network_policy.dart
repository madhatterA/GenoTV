import 'dart:async';
import 'dart:io';

/// The app's one network rule (owner, 2026-10-29): every connection tries
/// https first, falls back to http when https cannot connect, and is never
/// refused because of a certificate. Dart code gets it by calling
/// [installNetworkPolicy] once per isolate that opens connections; engines
/// that dial by themselves (aria2, mpv) take [httpsFirstUri] and
/// [verifyCertificates].
const bool verifyCertificates = false;

/// How long an https attempt may take before the plain http URL is used.
const Duration httpsConnectTimeout = Duration(seconds: 4);

/// Test/diagnostic hook: called with the URL asked for and the URL the
/// connection actually used (https, or http after a fallback).
void Function(Uri requested, Uri used)? networkPolicyObserver;

/// Hosts that never speak a real https certificate chain (this machine, the
/// LAN): left on their own scheme, no probe delay.
bool isLocalHost(String host) {
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  if (ip.type == InternetAddressType.IPv4) {
    final b = ip.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
  return (ip.rawAddress[0] & 0xfe) == 0xfc; // fc00::/7
}

// host:port -> when https last failed to connect; skipped for a while so one
// http-only host costs one failed attempt, not one per request.
final Map<String, DateTime> _httpsFailedAt = <String, DateTime>{};
const Duration _httpsRetryAfter = Duration(minutes: 10);

bool _eligible(Uri url, bool Function(String) isLocal) {
  if (url.scheme != 'http' || url.host.isEmpty || isLocal(url.host)) {
    return false;
  }
  final failed = _httpsFailedAt['${url.host}:${url.port}'];
  return failed == null || DateTime.now().difference(failed) > _httpsRetryAfter;
}

void _markFailed(Uri url) =>
    _httpsFailedAt['${url.host}:${url.port}'] = DateTime.now();

/// The https form of an http URL, same host and port. The default http port
/// maps to 443.
Uri _upgrade(Uri url) => url.replace(
  scheme: 'https',
  port: url.hasPort && url.port != 80 ? url.port : null,
);

/// For engines that open the connection themselves: the https URL when the
/// host accepts a TLS connection (any certificate), else [url] unchanged.
Future<Uri> httpsFirstUri(
  Uri url, {
  bool Function(String host) isLocal = isLocalHost,
}) async {
  if (!_eligible(url, isLocal)) return url;
  final https = _upgrade(url);
  try {
    final socket = await SecureSocket.connect(
      https.host,
      https.port,
      timeout: httpsConnectTimeout,
      onBadCertificate: (_) => true,
    );
    socket.destroy();
    return https;
  } on Object {
    _markFailed(url);
    return url;
  }
}

/// Installs the rule for every `HttpClient` (and `package:http`) created in
/// this isolate afterwards. Pass [isLocal] only in tests.
void installNetworkPolicy({bool Function(String host) isLocal = isLocalHost}) {
  HttpOverrides.global = _PolicyOverrides(isLocal);
}

class _PolicyOverrides extends HttpOverrides {
  _PolicyOverrides(this._isLocal);
  final bool Function(String) _isLocal;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = super.createHttpClient(context);
    if (!verifyCertificates) inner.badCertificateCallback = (_, _, _) => true;
    return _HttpsFirstClient(inner, _isLocal);
  }
}

/// Forwards everything to [_inner]; only `openUrl` (which every get/post/...
/// ends in) tries https first.
class _HttpsFirstClient implements HttpClient {
  _HttpsFirstClient(this._inner, this._isLocal);
  final HttpClient _inner;
  final bool Function(String) _isLocal;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await _open(method, url);
    networkPolicyObserver?.call(url, request.uri);
    return request;
  }

  Future<HttpClientRequest> _open(String method, Uri url) async {
    if (!_eligible(url, _isLocal)) return _inner.openUrl(method, url);
    try {
      return await _inner
          .openUrl(method, _upgrade(url))
          .timeout(httpsConnectTimeout);
    } on Object {
      _markFailed(url);
      return _inner.openUrl(method, url);
    }
  }

  Uri _url(String host, int port, String path) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: path.startsWith('/') ? path : '/$path',
  );
  @override
  Future<HttpClientRequest> open(String m, String h, int p, String path) =>
      openUrl(m, _url(h, p, path));
  @override
  Future<HttpClientRequest> get(String h, int p, String path) =>
      open('get', h, p, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('get', url);
  @override
  Future<HttpClientRequest> post(String h, int p, String path) =>
      open('post', h, p, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('post', url);
  @override
  Future<HttpClientRequest> put(String h, int p, String path) =>
      open('put', h, p, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('put', url);
  @override
  Future<HttpClientRequest> delete(String h, int p, String path) =>
      open('delete', h, p, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('delete', url);
  @override
  Future<HttpClientRequest> patch(String h, int p, String path) =>
      open('patch', h, p, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('patch', url);
  @override
  Future<HttpClientRequest> head(String h, int p, String path) =>
      open('head', h, p, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('head', url);

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f,
  ) => _inner.connectionFactory = f;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials c) =>
      _inner.addCredentials(url, realm, c);
  @override
  void addProxyCredentials(
    String h,
    int p,
    String realm,
    HttpClientCredentials c,
  ) => _inner.addProxyCredentials(h, p, realm, c);
  @override
  set authenticate(Future<bool> Function(Uri, String, String?)? f) =>
      _inner.authenticate = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String, int, String, String?)? f,
  ) => _inner.authenticateProxy = f;
  // Certificates never block (see [verifyCertificates]); callers' callbacks
  // are accepted and ignored.
  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? callback,
  ) {}
  @override
  set findProxy(String Function(Uri)? f) => _inner.findProxy = f;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}
