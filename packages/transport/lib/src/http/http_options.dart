import 'dart:io';

import 'package:contracts/contracts.dart';

/// Headers sent to the origin: the user's custom headers, overridden by the
/// ones the source itself supplies (SourceSpec wins per request).
Map<String, String> originHeaders(SourceSpec spec, TransportOptions options) {
  final own = {for (final k in spec.headers.keys) k.toLowerCase()};
  return {
    for (final e in options.headers.entries)
      if (!own.contains(e.key.toLowerCase())) e.key: e.value,
    ...spec.headers,
  };
}

/// The proxy URL, or null for none. Only an http(s) proxy is supported on the
/// HTTP path (Dart's HttpClient and aria2 have no SOCKS); anything else
/// surfaces as a typed failure instead of being ignored.
Uri? httpProxy(TransportOptions options) {
  if (options.proxy.isEmpty) return null;
  final uri = Uri.tryParse(options.proxy);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    throw TransportFailure.httpUnreachable(
      cause: 'invalid proxy "${options.proxy}"',
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw TransportFailure.httpUnreachable(
      cause: 'proxy scheme "${uri.scheme}" is not supported for HTTP sources',
    );
  }
  return uri;
}

/// Applies the user-agent, proxy, TLS and connect-timeout settings to the
/// client that reaches the origin (probe and seek windows).
HttpClient configureOriginClient(HttpClient client, TransportOptions options) {
  if (options.userAgent.isNotEmpty) client.userAgent = options.userAgent;
  if (options.connectTimeoutSeconds > 0) {
    client.connectionTimeout = Duration(seconds: options.connectTimeoutSeconds);
  }
  final proxy = httpProxy(options);
  if (proxy != null) {
    client.findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}';
    if (proxy.userInfo.isNotEmpty) {
      final parts = proxy.userInfo.split(':');
      client.addProxyCredentials(
        proxy.host,
        proxy.port,
        '',
        HttpClientBasicCredentials(
          Uri.decodeComponent(parts.first),
          Uri.decodeComponent(parts.skip(1).join(':')),
        ),
      );
    }
  }
  if (!options.verifyTls) client.badCertificateCallback = (_, _, _) => true;
  return client;
}

int _lowestLimit(int a, int b) => a <= 0 ? b : (b <= 0 ? a : (a < b ? a : b));

/// aria2 per-download options for the transfer itself (limits, connections,
/// timeouts, tries). Empty values leave aria2's own defaults.
Map<String, String> aria2TransferOptions(TransportOptions options) {
  final limit = _lowestLimit(
    options.streamDownloadBytesPerSecond,
    options.globalDownloadBytesPerSecond,
  );
  return {
    if (options.maxHttpConnections > 0) ...{
      'split': '${options.maxHttpConnections}',
      'max-connection-per-server': '${options.maxHttpConnections}',
    },
    if (options.connectTimeoutSeconds > 0) ...{
      'connect-timeout': '${options.connectTimeoutSeconds}',
      'timeout': '${options.connectTimeoutSeconds}',
    },
    if (options.retryCount > 0) 'max-tries': '${options.retryCount + 1}',
    if (limit > 0) 'max-download-limit': '$limit',
  };
}

/// aria2 options for a download that reaches the origin itself (no bounded
/// window): proxy and user agent.
Map<String, String> aria2OriginOptions(TransportOptions options) {
  final proxy = httpProxy(options);
  return {
    ...aria2TransferOptions(options),
    if (proxy != null)
      'all-proxy': '${proxy.scheme}://${proxy.host}:${proxy.port}',
    if (options.userAgent.isNotEmpty) 'user-agent': options.userAgent,
  };
}
