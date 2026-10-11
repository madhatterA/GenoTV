import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP status, JSON and network failures', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = ProviderHttp();
    server.listen((request) async {
      expect(request.headers.value('user-agent'), 'Mozilla/5.0');
      switch (request.uri.path) {
        case '/auth':
          request.response.statusCode = 401;
        case '/missing':
          request.response.statusCode = 404;
        case '/error':
          request.response.statusCode = 500;
        case '/bad':
          request.response.write('bad');
        case '/redirect':
          await request.response.redirect(
            Uri.parse('http://127.0.0.1:${server.port}/ok'),
          );
        default:
          request.response.write('{"ok":true}');
      }
      await request.response.close();
    });
    final root = Uri.parse('http://127.0.0.1:${server.port}');
    expect(await http.getJson(root.resolve('/ok')), {'ok': true});
    expect(await http.getJson(root.resolve('/redirect')), {'ok': true});
    expect(
      await http.getText(root.resolve('/missing'), allowNotFound: true),
      isNull,
    );
    await expectLater(
      http.getJson(root.resolve('/auth')),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.auth_required',
        ),
      ),
    );
    await expectLater(
      http.getJson(root.resolve('/bad')),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.invalid_response',
        ),
      ),
    );
    await expectLater(
      http.getJson(root.resolve('/missing')),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.not_found',
        ),
      ),
    );
    await expectLater(
      http.getJson(root.resolve('/error')),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.unavailable',
        ),
      ),
    );
    http.close();
    await server.close(force: true);
    final closed = ProviderHttp();
    await expectLater(
      closed.getText(root.resolve('/ok')),
      throwsA(
        isA<ContentSourceFailure>().having(
          (e) => e.code,
          'code',
          'provider.network',
        ),
      ),
    );
    closed.close();
  });

  test('session, quality, size and ordering', () async {
    final dir = await Directory.systemTemp.createTemp('provider-test');
    try {
      final file = File('${dir.path}/session.json');
      await file.writeAsString('{"token":"abc"}');
      expect(await readSessionToken(file, 'token'), 'abc');
      await expectLater(
        readSessionToken(file, 'missing'),
        throwsA(isA<ContentSourceFailure>()),
      );
      final missingFile = File('${dir.path}/no-such-file.json');
      await expectLater(
        readSessionToken(missingFile, 'token'),
        throwsA(isA<ContentSourceFailure>()),
      );
      final malformedFile = File('${dir.path}/malformed.json');
      await malformedFile.writeAsString('not json');
      await expectLater(
        readSessionToken(malformedFile, 'token'),
        throwsA(isA<ContentSourceFailure>()),
      );
      expect(parseQuality('x265 BluRay 2160p'), '2160p');
      expect(parseQuality('4K'), '2160p');
      expect(parseQuality('1080p Full HD'), '1080p');
      expect(parseQuality('240p'), '240p');
      expect(parseQuality('خودکار'), isNull);
      expect(parseSizeBytes('2.80 GB'), 3006477107);
      expect(parseSizeBytes('400 MB'), 419430400);
      expect(parseSizeBytes('66.25 GB'), 71135395840);
      expect(parseSizeBytes('1,024'), 1024);
      expect(parseSizeBytes('abc'), isNull);
      final specs = orderStreams([
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('https://x/a'),
          quality: '720p',
        ),
        SourceSpec(kind: SourceKind.hlsUrl, uri: Uri.parse('https://x/b')),
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('https://x/c'),
          quality: '1080p',
        ),
      ]);
      expect(specs.map((e) => e.uri.path).toList(), ['/b', '/c', '/a']);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
