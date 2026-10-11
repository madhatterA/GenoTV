import 'dart:async';
import 'dart:io';

/// The personal backup proxy (planning/features/BACKUP_PROXY.md). One place.
/// Port 2053 is deliberate (Cloudflare HTTPS port; 443 is taken).
final Uri backupProxy = Uri.parse('https://genotv.cubernets.com:2053');

/// Metadata APIs whose keys live on the proxy: always routed there.
const Set<String> proxyOnlyHosts = {
  'api.themoviedb.org',
  'www.omdbapi.com',
  'omdbapi.com',
};

const Duration directHeaderDeadline = Duration(seconds: 3);
const Duration _routeTimeout = Duration(seconds: 30);

final RegExp _mediaPath = RegExp(
  r'\.(mp4|mkv|avi|mov|webm|m4v|wmv|flv|ts|m2ts|m4s|m3u8?|mpd|'
  r'mp3|aac|m4a|flac|ogg|opus|wav|ac3|eac3|dts|mka)$',
  caseSensitive: false,
);

/// Video/audio never goes through the proxy: media file extensions and any
/// Range/If-Range request stay direct (the server refuses them too).
bool isMediaRequest(Uri uri, Map<String, String> headers) =>
    _mediaPath.hasMatch(uri.path) ||
    headers.keys.any((k) {
      final key = k.toLowerCase();
      return key == 'range' || key == 'if-range';
    });

/// `https://host/path?q` → `PROXY/host/path?q` (raw query unchanged). Null
/// when the proxy cannot express the target (non-https, explicit port).
Uri? proxyUriFor(Uri target, {Uri? proxy}) {
  final base = proxy ?? backupProxy;
  if (target.scheme != 'https' || target.hasPort && target.port != 443) {
    return null;
  }
  final path = target.path.isEmpty ? '/' : target.path;
  final query = target.hasQuery ? '?${target.query}' : '';
  return Uri.parse('${base.origin}${base.path}/${target.host}$path$query');
}

/// Maps a proxy URL (a same-origin redirect the proxy rewrote to its own
/// path, `/host/...`) back to the provider URL it stands for; the provider
/// keeps [original]'s scheme.
Uri _unproxied(Uri uri, Uri proxy, Uri original) {
  if (uri.origin != proxy.origin) return uri;
  final segments = uri.pathSegments.skip(proxy.pathSegments.length).toList();
  if (segments.isEmpty) return uri;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return Uri.parse(
    '${original.scheme}://${segments.first}/${segments.skip(1).join('/')}$query',
  );
}

const Set<String> _credentialHeaders = {
  'authorization',
  'cookie',
  'proxy-authorization',
};

/// Direct first, the backup proxy after [deadline] without response
/// headers (owner rules, BACKUP_PROXY.md Phase 2):
/// - TMDb/OMDb always via the proxy (it injects the keys);
/// - GET/HEAD: direct; on a network error or no headers within [deadline],
///   cancel it and retry once via the proxy. HTTP errors are real answers;
/// - POST: a HEAD reachability check picks the route, then the POST is sent
///   exactly once;
/// - media and Range requests are direct only, never the proxy;
/// - redirects are followed here, each hop routed on its own, credentials
///   dropped when the origin changes.
class BackupRouter {
  BackupRouter({
    Uri? proxy,
    this.deadline = directHeaderDeadline,
    Uri? Function(Uri target)? proxyUriOf,
  }) : proxy = proxy ?? backupProxy,
       _proxyUriOf = proxyUriOf;

  final Uri proxy;
  final Duration deadline;

  /// Tests map local http targets; production uses [proxyUriFor].
  final Uri? Function(Uri target)? _proxyUriOf;

  Uri? _viaProxy(Uri target) =>
      (_proxyUriOf ?? (t) => proxyUriFor(t, proxy: proxy))(target);

  Future<HttpClientResponse> send(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, String> headers, {
    List<int>? body,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) async {
    var current = uri;
    var currentMethod = method;
    var currentBody = body;
    var currentHeaders = Map<String, String>.of(headers);
    for (var hop = 0; ; hop++) {
      final (:response, :sentTo) = await _route(
        client,
        currentMethod,
        current,
        currentHeaders,
        currentBody,
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (!followRedirects ||
          !response.isRedirect ||
          location == null ||
          hop >= maxRedirects) {
        return response;
      }
      await response.drain<void>();
      // The proxy sends same-origin redirects as its own `/host/...` path:
      // resolve against the URL actually requested, then map back.
      final next = _unproxied(sentTo.resolve(location), proxy, current);
      if (next.origin != current.origin) {
        currentHeaders = {
          for (final e in currentHeaders.entries)
            if (!_credentialHeaders.contains(e.key.toLowerCase()))
              e.key: e.value,
        };
      }
      final status = response.statusCode;
      if (status == 303 ||
          (currentMethod == 'POST' && (status == 301 || status == 302))) {
        currentMethod = 'GET';
        currentBody = null;
      }
      current = next;
    }
  }

  Future<({HttpClientResponse response, Uri sentTo})> _route(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, String> headers,
    List<int>? body,
  ) async {
    final viaProxy = _viaProxy(uri);
    if (isMediaRequest(uri, headers) || viaProxy == null) {
      return (
        response: await _open(
          client,
          method,
          uri,
          headers,
          body,
          _routeTimeout,
        ),
        sentTo: uri,
      );
    }
    if (proxyOnlyHosts.contains(uri.host)) {
      return (
        response: await _open(
          client,
          method,
          viaProxy,
          headers,
          body,
          _routeTimeout,
        ),
        sentTo: viaProxy,
      );
    }
    if (method == 'GET' || method == 'HEAD') {
      try {
        return (
          response: await _open(client, method, uri, headers, body, deadline),
          sentTo: uri,
        );
      } on Object catch (error) {
        if (!_isNetwork(error)) rethrow;
      }
      return (
        response: await _open(
          client,
          method,
          viaProxy,
          headers,
          body,
          _routeTimeout,
        ),
        sentTo: viaProxy,
      );
    }
    // POST (or any method with side effects): never sent twice.
    var direct = true;
    try {
      final probe = await _open(client, 'HEAD', uri, headers, null, deadline);
      await probe.drain<void>();
    } on Object catch (error) {
      if (!_isNetwork(error)) rethrow;
      direct = false;
    }
    return (
      response: await _open(
        client,
        method,
        direct ? uri : viaProxy,
        headers,
        body,
        _routeTimeout,
      ),
      sentTo: direct ? uri : viaProxy,
    );
  }

  static bool _isNetwork(Object error) =>
      error is TimeoutException ||
      error is SocketException ||
      error is TlsException ||
      error is HttpException ||
      error is OSError;

  /// Opens [uri] and waits for response headers within [limit]; on timeout
  /// the request is aborted (a connect still pending is aborted on arrival).
  static Future<HttpClientResponse> _open(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, String> headers,
    List<int>? body,
    Duration limit,
  ) async {
    HttpClientRequest? request;
    var abandoned = false;
    Future<HttpClientResponse> run() async {
      final opened = await client.openUrl(method, uri);
      request = opened;
      if (abandoned) {
        opened.abort();
        throw TimeoutException('request abandoned', limit);
      }
      opened.followRedirects = false;
      for (final e in headers.entries) {
        opened.headers.set(e.key, e.value);
      }
      if (body != null) opened.add(body);
      return opened.close();
    }

    final pending = run();
    try {
      return await pending.timeout(limit);
    } on TimeoutException {
      abandoned = true;
      request?.abort();
      // The abandoned attempt ends in an abort error nobody waits for.
      pending.ignore();
      rethrow;
    }
  }
}
