import 'dart:io';

import 'package:contracts/testing.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  late HttpServer upstream;
  final cache = Directory.systemTemp.createTempSync('contract-cache-');
  tearDownAll(() => cache.delete(recursive: true));
  final payload = List<int>.generate(64 * 1024, (index) => index % 251);
  setUpAll(() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.method == 'HEAD') {
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = payload.length;
      } else {
        final raw = request.headers.value(HttpHeaders.rangeHeader);
        var start = 0;
        var end = payload.length - 1;
        if (raw != null && raw.startsWith('bytes=')) {
          final bounds = raw.substring(6).split('-');
          start = int.parse(bounds.first);
          end = bounds.length > 1 && bounds.last.isNotEmpty
              ? int.parse(bounds.last)
              : end;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/${payload.length}',
          );
        }
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = end - start + 1;
        request.response.add(payload.sublist(start, end + 1));
      }
      await request.response.close();
    });
  });
  tearDownAll(() => upstream.close(force: true));
  runStreamSourceContractTests(
    () => createStreamSource(logger: MemoryLogger(), cacheDir: cache),
    spec: () => SourceSpec(
      kind: SourceKind.httpUrl,
      uri: Uri.parse('http://127.0.0.1:${upstream.port}/fixture.bin'),
    ),
    readRange: _readRange,
    unreachableSpec: () => SourceSpec(
      kind: SourceKind.httpUrl,
      uri: Uri.parse('http://127.0.0.1:1/unreachable.bin'),
    ),
  );

  test('a signed URL far longer than a file name still downloads', () async {
    final source = createStreamSource(
      logger: MemoryLogger(),
      cacheDir: await Directory.systemTemp.createTemp('long-url-'),
    );
    final handle = await source.open(
      SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse(
          'http://127.0.0.1:${upstream.port}/${'a' * 400}/fixture.bin',
        ),
      ),
    );
    try {
      final bytes = await _readRange(handle.playbackUri, ByteRange(0, 99));
      expect(bytes, payload.sublist(0, 100));
    } finally {
      await handle.dispose();
    }
  });
}

Future<List<int>> _readRange(Uri uri, ByteRange range) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${range.start}-${range.endInclusive}',
    );
    final response = await request.close();
    return await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
  } finally {
    client.close(force: true);
  }
}
