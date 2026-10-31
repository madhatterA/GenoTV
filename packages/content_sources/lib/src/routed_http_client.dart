import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:core/core.dart';

/// `package:http` client with the same direct-first / backup-proxy routing
/// as `ProviderHttp` (Playtorrio's scrapers use `package:http`).
///
/// By default every request runs on one shared background isolate: the TLS
/// handshakes of ~40 scrapers starting at once cost the TCL TV's UI thread
/// seconds (BoringSSL `bn_mul_mont`, 150-1000 ms frames on the detail page).
/// A test that passes its own [router] or [client] runs in-process instead.
class RoutedHttpClient extends http.BaseClient {
  RoutedHttpClient({BackupRouter? router, HttpClient? client})
    : _inline = router != null || client != null,
      _router = router ?? BackupRouter(),
      _client = client ?? HttpClient();

  final bool _inline;
  final BackupRouter _router;
  final HttpClient _client;

  static Future<SendPort>? _worker;

  static Future<SendPort> _spawn() async {
    final ready = ReceivePort();
    await Isolate.spawn(_serve, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    return port;
  }

  static void _serve(SendPort ready) {
    installNetworkPolicy(); // a new isolate does not inherit the app's
    final inbox = ReceivePort();
    final router = BackupRouter();
    final client = HttpClient();
    inbox.listen((Object? message) async {
      final m = message! as List<Object?>;
      final reply = m[0]! as SendPort;
      try {
        final response = await router.send(
          client,
          m[1]! as String,
          Uri.parse(m[2]! as String),
          Map<String, String>.from(m[3]! as Map),
          body: (m[4]! as Uint8List).isEmpty ? null : m[4]! as Uint8List,
          followRedirects: m[5]! as bool,
          maxRedirects: m[6]! as int,
        );
        final bytes = BytesBuilder(copy: false);
        await response.forEach(bytes.add);
        reply.send(<Object?>[
          response.statusCode,
          _headersOf(response),
          bytes.takeBytes(),
          response.isRedirect,
          response.reasonPhrase,
        ]);
      } on Object catch (error) {
        reply.send(error.toString());
      }
    });
    ready.send(inbox.sendPort);
  }

  static Map<String, String> _headersOf(HttpClientResponse response) {
    final headers = <String, String>{};
    response.headers.forEach(
      (name, values) => headers[name] = values.join(','),
    );
    return headers;
  }

  Future<http.StreamedResponse> _viaWorker(
    http.BaseRequest request,
    Uint8List body,
  ) async {
    final worker = await (_worker ??= _spawn());
    final reply = ReceivePort();
    worker.send(<Object?>[
      reply.sendPort,
      request.method,
      request.url.toString(),
      request.headers,
      body,
      request.followRedirects,
      request.maxRedirects,
    ]);
    final result = await reply.first;
    reply.close();
    if (result is String) throw http.ClientException(result, request.url);
    final r = result! as List<Object?>;
    final bytes = r[2]! as Uint8List;
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      r[0]! as int,
      contentLength: bytes.length,
      request: request,
      headers: Map<String, String>.from(r[1]! as Map),
      isRedirect: r[3]! as bool,
      reasonPhrase: r[4] as String?,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    if (!_inline) return _viaWorker(request, body);
    final response = await _router.send(
      _client,
      request.method,
      request.url,
      request.headers,
      body: body.isEmpty ? null : body,
      followRedirects: request.followRedirects,
      maxRedirects: request.maxRedirects,
    );
    final headers = <String, String>{};
    response.headers.forEach(
      (name, values) => headers[name] = values.join(','),
    );
    return http.StreamedResponse(
      response,
      response.statusCode,
      contentLength: response.contentLength == -1
          ? null
          : response.contentLength,
      request: request,
      headers: headers,
      isRedirect: response.isRedirect,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inline ? _client.close(force: true) : null;
}
