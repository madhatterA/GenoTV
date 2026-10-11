import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:core/core.dart';
import 'package:transport/transport.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isolated native 200 MiB window trace', () async {
    final media = File('/tmp/ch03-p00b-rulings-fixtures/b.bin');
    final total = media.lengthSync();
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      final match = RegExp(r'bytes=(\d+)-(\d*)')
          .firstMatch(request.headers.value('range') ?? '');
      final start = match == null ? 0 : int.parse(match[1]!);
      final end = match == null || match[2]!.isEmpty
          ? total - 1
          : int.parse(match[2]!);
      request.response.headers.set('accept-ranges', 'bytes');
      request.response.contentLength = end - start + 1;
      if (match != null) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'content-range',
          'bytes $start-$end/$total',
        );
      }
      if (request.method != 'HEAD') {
        final clock = Stopwatch()..start();
        var sent = 0;
        await for (final bytes in media.openRead(start, end + 1)) {
          request.response.add(bytes);
          sent += bytes.length;
          final due = sent * 1000 ~/ (200 * 1024 * 1024);
          if (due > clock.elapsedMilliseconds) {
            await Future<void>.delayed(
              Duration(milliseconds: due - clock.elapsedMilliseconds),
            );
          }
        }
      }
      await request.response.close();
    });
    final cache = await Directory.systemTemp.createTemp('http-window-trace-');
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
    final client = HttpClient();
    final clock = Stopwatch()..start();
    try {
      final handle = await source.open(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('http://127.0.0.1:${origin.port}/b.bin'),
        ),
        options: const TransportOptions(cacheLimitBytes: 512 * 1024 * 1024),
      );
      final request = await client.getUrl(handle.playbackUri);
      request.headers.set('range', 'bytes=0-${total - 1}');
      final response = await request.close();
      final iterator = StreamIterator(response);
      var bytes = 0;
      var maxWait = 0;
      Digest? actual;
      final hash = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback(
          (values) => actual = values.single,
        ),
      );
      while (true) {
        final start = clock.elapsedMilliseconds;
        final has = await iterator.moveNext().timeout(
          const Duration(seconds: 2),
        );
        final wait = clock.elapsedMilliseconds - start;
        if (wait > maxWait) maxWait = wait;
        if (!has) break;
        bytes += iterator.current.length;
        hash.add(iterator.current);
      }
      hash.close();
      expect(bytes, total);
      expect(actual, await sha256.bind(media.openRead()).first);
      expect(maxWait, lessThan(2000));
      // ignore: avoid_print
      print(
        'RESULT 200MiB byte-exact SHA256=$actual longestWait=${maxWait}ms elapsed=${clock.elapsedMilliseconds}ms',
      );
      await handle.dispose();
    } finally {
      client.close(force: true);
      await source.dispose();
      await origin.close(force: true);
      await cache.delete(recursive: true);
    }
  });
}
