import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

/// The cache limit frees bytes behind the play head, so the bytes on disk
/// stay about one window long. The popover's "downloaded" must still grow
/// with real progress (bug: it sat at ~1% of the file while playing).
void main() {
  test('HTTP downloaded bytes keep growing past the cache window', () async {
    const size = 48 * 1024 * 1024;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final chunk = List<int>.filled(1024 * 1024, 7);
    final serverSub = upstream.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (request.method == 'HEAD') {
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = size;
        await request.response.close();
        return;
      }
      var start = 0, end = size - 1;
      if (range != null) {
        final parts = range.substring(6).split('-');
        start = int.parse(parts.first);
        end = parts.last.isEmpty ? size - 1 : int.parse(parts.last);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-$end/$size',
        );
      }
      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      try {
        var sent = 0;
        final len = end - start + 1;
        while (sent < len) {
          final n = (len - sent) > chunk.length ? chunk.length : len - sent;
          request.response.add(chunk.sublist(0, n));
          sent += n;
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await request.response.close();
      } catch (_) {}
    });
    final cache = await Directory.systemTemp.createTemp('probe-');
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
    final handle = await source.open(
      SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://127.0.0.1:${upstream.port}/m.bin'),
      ),
      options: const TransportOptions(cacheLimitBytes: 8 * 1024 * 1024),
    );
    final client = HttpClient();
    final req = await client.getUrl(handle.playbackUri);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final resp = await req.close();
    var read = 0;
    final sub2 = resp.listen((d) => read += d.length);
    final pacer = Stream.periodic(const Duration(milliseconds: 100))
        .listen((_) {
          sub2.pause();
          Future<void>.delayed(const Duration(milliseconds: 90), sub2.resume);
        });
    var last = 0;
    var peak = 0;
    for (var i = 0; i < 14; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final stats = await (handle as TransportStatsProvider).readStats();
      expect(stats.totalBytes, size);
      expect(
        stats.downloadedBytes,
        greaterThanOrEqualTo(last),
        reason: 'never goes back',
      );
      last = stats.downloadedBytes;
      peak = last;
      if (last >= size) break;
    }
    // Far more than the 8 MiB cache window.
    expect(peak, greaterThan(3 * 8 * 1024 * 1024));
    await pacer.cancel();
    await sub2.cancel();
    client.close(force: true);
    await handle.dispose();
    await source.dispose();
    await serverSub.cancel();
    await upstream.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
