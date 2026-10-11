import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'content_source_failure.dart';

class ProviderHttp {
  ProviderHttp([HttpClient? client, BackupRouter? router])
    : _client = client ?? _newClient(),
      _router = router ?? BackupRouter();

  /// Direct first, backup proxy on failure (see [BackupRouter]).
  final BackupRouter _router;

  static HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'Mozilla/5.0';

  HttpClient _client;

  Future<String?> getText(
    Uri uri, {
    Map<String, String> headers = const {},
    bool allowNotFound = false,
  }) => _request('GET', uri, headers: headers, allowNotFound: allowNotFound);

  Future<Object?> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    bool allowNotFound = false,
  }) async {
    final body = await getText(
      uri,
      headers: headers,
      allowNotFound: allowNotFound,
    );
    if (body == null) return null;
    try {
      return jsonDecode(body);
    } catch (error) {
      throw ContentSourceFailure.invalidResponse(error);
    }
  }

  Future<Object?> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async {
    final body = await _request(
      'POST',
      uri,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        ...headers,
      },
      body: form.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&'),
    );
    try {
      return jsonDecode(body!);
    } catch (error) {
      throw ContentSourceFailure.invalidResponse(error);
    }
  }

  Future<Object?> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _request(
      'POST',
      uri,
      headers: {'Content-Type': 'application/json', ...headers},
      body: jsonEncode(body),
    );
    try {
      return jsonDecode(response!);
    } catch (error) {
      throw ContentSourceFailure.invalidResponse(error);
    }
  }

  Future<String?> _request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    bool allowNotFound = false,
    String? body,
  }) async {
    try {
      final response = await _router.send(_client, method, uri, {
        'User-Agent': 'Mozilla/5.0',
        ...headers,
      }, body: body == null ? null : utf8.encode(body));
      if (response.statusCode == 404 && allowNotFound) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ContentSourceFailure.authRequired();
      }
      if (response.statusCode == 404) {
        throw const ContentSourceFailure.notFound();
      }
      if (response.statusCode >= 400) {
        throw const ContentSourceFailure.unavailable();
      }
      final bytes = await response
          .fold<List<int>>(<int>[], (out, chunk) => out..addAll(chunk))
          .timeout(const Duration(seconds: 30));
      return utf8
          .decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '');
    } on ContentSourceFailure {
      rethrow;
    } on FormatException catch (error) {
      throw ContentSourceFailure.invalidResponse(error);
    } on Object catch (error) {
      // After a network switch the pooled keep-alive sockets are dead; drop
      // them so the next request starts from a fresh connection.
      _client.close();
      _client = _newClient();
      throw ContentSourceFailure.network(error);
    }
  }

  void close() => _client.close(force: true);
}
