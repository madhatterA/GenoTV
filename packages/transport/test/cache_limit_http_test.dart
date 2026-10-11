import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

const _mib = 1024 * 1024;
const _total = 32 * _mib;
const _limit = 12 * _mib;

Uint8List _bytes(int start, int count) {
  final out = Uint8List(count);
  for (var i = 0; i < count; i++) {
    final at = start + i;
    out[i] = (at * 31 + (at >> 8)) & 0xff;
  }
  return out;
}

void main() {
  test(
    'HTTP stream stays under the cache limit and re-fetches evicted data',
    () async {
      final cache = await Directory.systemTemp.createTemp('cache-limit-http-');
      addTearDown(() => cache.delete(recursive: true));
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((req) async {
        final m = RegExp(r'bytes=(\d+)-(\d*)')
            .firstMatch(req.headers.value('range') ?? '');
        final start = m == null ? 0 : int.parse(m[1]!);
        final end = m == null || m[2]!.isEmpty ? _total - 1 : int.parse(m[2]!);
        req.response.headers.set('accept-ranges', 'bytes');
        if (m != null) {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            'content-range',
            'bytes $start-$end/$_total',
          );
        }
        req.response.contentLength = end - start + 1;
        if (req.method != 'HEAD') {
          try {
            for (var at = start; at <= end; at += _mib) {
              final n = (end - at + 1).clamp(0, _mib);
              req.response.add(_bytes(at, n));
              await req.response.flush();
            }
          } on Object {
            // client closed mid-range (seek)
          }
        }
        await req.response.close().catchError((Object _) => req.response);
      });
      final fs = FsNative();
      final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
      final handle = await source.open(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('http://127.0.0.1:${origin.port}/m.bin'),
        ),
        options: TransportOptions(cacheLimitBytes: _limit),
      );
      int onDisk() => cache.listSync().whereType<File>().fold(
        0,
        (sum, f) => sum + fs.allocatedBytes(f.path),
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<int> read(int from, int to, {required bool sampleDisk}) async {
        final req = await client.getUrl(handle.playbackUri);
        req.headers.set('range', 'bytes=$from-$to');
        final res = await req.close();
        var at = from;
        var peak = 0;
        await for (final chunk in res) {
          expect(chunk, _bytes(at, chunk.length), reason: 'bytes at $at');
          at += chunk.length;
          if (sampleDisk && at % _mib < chunk.length) {
            final used = onDisk();
            if (used > peak) peak = used;
          }
        }
        expect(at, to + 1);
        return peak;
      }

      final peak = await read(0, _total - 1, sampleDisk: true);
      expect(peak, lessThanOrEqualTo(_limit + 12 * _mib));
      expect(
        peak,
        lessThan(_total),
        reason: 'eviction/pause kept data off disk',
      );
      final evicted = fs.allocatedBytes(
        cache.listSync().whereType<File>().first.path,
        offset: 3 * _mib,
        length: 2 * _mib,
      );
      expect(evicted, 0);
      expect(
        cache.listSync().whereType<File>().any(
          (f) => f.path.endsWith('.evicted'),
        ),
        isTrue,
        reason: 'crash recovery is marked before punching',
      );
      await handle.seekHint(3 * _mib);
      await read(3 * _mib, 5 * _mib - 1, sampleDisk: false);
      await handle.dispose();
      await source.dispose();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
