import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:core/core.dart';

/// `package:http` client with the same direct-first / backup-proxy routing
/// as `ProviderHttp` (Playtorrio's scrapers use `package:http`).
class RoutedHttpClient extends http.BaseClient {
  RoutedHttpClient({BackupRouter? router, HttpClient? client})
    : _router = router ?? BackupRouter(),
      _client = client ?? HttpClient();

  final BackupRouter _router;
  final HttpClient _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
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
  void close() => _client.close(force: true);
}
