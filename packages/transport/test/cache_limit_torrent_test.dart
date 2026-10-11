import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

const _mib = 1024 * 1024;
const _total = 48 * _mib;
const _limit = 24 * _mib;

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
    'torrent stays under the cache limit and re-fetches evicted pieces',
    () async {
      final work = await Directory.systemTemp.createTemp(
        'cache-limit-torrent-',
      );
      addTearDown(() => work.delete(recursive: true));
      final media = File('${work.path}/seed/clip.bin')
        ..createSync(recursive: true);
      final raf = media.openSync(mode: FileMode.write);
      for (var at = 0; at < _total; at += _mib) {
        raf.writeFromSync(_bytes(at, _mib));
      }
      raf.closeSync();
      final seeder = await Process.start('python3', [
        'test/harness/torrent_seeder.py',
        media.path,
      ]);
      addTearDown(() => seeder.kill(ProcessSignal.sigkill));
      final magnet = Completer<String>();
      seeder.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('magnet=') && !magnet.isCompleted) {
              magnet.complete(line.substring(7));
            }
          });
      unawaited(seeder.stderr.drain<void>());
      final cache = Directory('${work.path}/cache')..createSync();
      final fs = FsNative();
      final logger = MemoryLogger();
    addTearDown(() {
      for (final r in logger.records) {
        printOnFailure('${r.level} ${r.message} ${r.error}');
      }
    });
    final source = StreamSourceImpl(logger: logger, cacheDir: cache);
      final handle = await source
          .open(
            SourceSpec(
              kind: SourceKind.torrentMagnet,
              uri: Uri.parse(
                await magnet.future.timeout(const Duration(seconds: 30)),
              ),
            ),
            options: const TransportOptions(cacheLimitBytes: _limit),
          )
          .timeout(const Duration(seconds: 60));
      int onDisk() => cache
          .listSync(recursive: true)
          .whereType<File>()
          .fold(0, (sum, f) => sum + fs.allocatedBytes(f.path));
      final sub = handle.status.listen((s) => printOnFailure('${DateTime.now().second}.${DateTime.now().millisecond} ${s.state} peers=${s.peersOrConnections} rate=${s.bytesPerSecond} avail=${s.available.ranges.map((r) => '${r.start >> 20}-${r.endInclusive >> 20}').join(',')}'));
    addTearDown(sub.cancel);
    final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<int> read(int from, int to) async {
        final req = await client.getUrl(handle.playbackUri);
        req.headers.set('range', 'bytes=$from-$to');
        final res = await req.close();
        var at = from;
        var peak = 0;
        await for (final chunk in res) {
          expect(chunk, _bytes(at, chunk.length), reason: 'bytes at $at');
          at += chunk.length;
          if (at % _mib < chunk.length) {
            final used = onDisk();
          printOnFailure('read ${at >> 20} MiB disk ${used >> 20} MiB');
            if (used > peak) peak = used;
          }
        }
        expect(at, to + 1);
        return peak;
      }

      final peak = await read(0, _total - 1);
      expect(peak, lessThanOrEqualTo(_limit + 8 * _mib));
      expect(peak, lessThan(_total), reason: 'eviction kept data off disk');
      final file = cache
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('clip.bin'));
      expect(
        fs.allocatedBytes(file.path, offset: 3 * _mib, length: 2 * _mib),
        lessThanOrEqualTo(16 * 1024),
      );
      await handle.seekHint(3 * _mib);
      await read(3 * _mib, 5 * _mib - 1);
      await handle.dispose();
      await source.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
