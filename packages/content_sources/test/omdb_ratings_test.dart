import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late MemoryLogger logger;
  Map<String, Object?> body = {};
  var hits = 0;
  Map<String, String> lastQuery = {};

  setUp(() async {
    hits = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits++;
      lastQuery = request.uri.queryParameters;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    dir = await Directory.systemTemp.createTemp('omdb-test');
    logger = MemoryLogger();
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  OmdbRatings client() {
    return OmdbRatings(
      http: ProviderHttp(),
      logger: logger,
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
    );
  }

  test('returns IMDb and Rotten Tomatoes by imdb id', () async {
    body = {
      'Response': 'True',
      'imdbRating': '8.8',
      'Ratings': [
        {'Source': 'Internet Movie Database', 'Value': '8.8/10'},
        {'Source': 'Rotten Tomatoes', 'Value': '87%'},
      ],
    };
    final r = await client().ratings('tt1375666');
    expect(r.imdb, '8.8');
    expect(r.rottenTomatoes, '87%');
    // Keyless: the backup proxy adds the key (BACKUP_PROXY.md).
    expect(lastQuery, {'i': 'tt1375666'});
  });

  test('only one score present shows only that one', () async {
    body = {
      'Response': 'True',
      'imdbRating': 'N/A',
      'Ratings': [
        {'Source': 'Rotten Tomatoes', 'Value': '91%'},
      ],
    };
    final r = await client().ratings('tt1');
    expect(r.imdb, isNull);
    expect(r.rottenTomatoes, '91%');
  });

  test('OMDb error response gives empty ratings and a warning', () async {
    body = {'Response': 'False', 'Error': 'Invalid API key!'};
    final r = await client().ratings('tt1');
    expect(r.isEmpty, isTrue);
    expect(
      logger.records.any((e) => e.message.contains('Invalid API key')),
      isTrue,
    );
  });
}
