import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

int _fds() => (Process.runSync("lsof", ["-p", "$pid", "-Ff"]).stdout as String).split("\n").where((l) => l.startsWith("f")).length;

/// mpv-like load on a real torrent stream: open-ended ranges that are dropped
/// mid-body, seeks, bounded reads. The process fd count must not grow per
/// request (the real app ran out of descriptors and stalled).
void main() {
  test('range requests, aborts and seeks do not leak file descriptors', () async {
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: Directory.current.path);
    String? magnet;
    final ready = Completer<void>();
    final sub = fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('magnet=')) {
            magnet = line.substring('magnet='.length);
            if (!ready.isCompleted) ready.complete();
          }
        });
    final errs = fixture.stderr.drain<void>();
    final cache = await Directory.systemTemp.createTemp('transport-fd-');
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
    try {
      await ready.future.timeout(const Duration(seconds: 30));
      final handle = await source
          .open(SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(magnet!)))
          .timeout(const Duration(seconds: 35));
      Future<void> abortedGet(int start) async {
        final socket = await Socket.connect(
          handle.playbackUri.host,
          handle.playbackUri.port,
        );
        socket.write(
          'GET ${handle.playbackUri.path} HTTP/1.1\r\nHost: x\r\n'
          'Range: bytes=$start-\r\n\r\n',
        );
        final got = Completer<void>();
        socket.listen((_) {
          if (!got.isCompleted) got.complete();
        }, onError: (_) {});
        await got.future.timeout(const Duration(seconds: 20));
        socket.destroy();
      }

      Future<void> burst(int n) async {
        for (var i = 0; i < n; i++) {
          final start = (i * 1700003) % (28 * 1024 * 1024);
          await handle.seekHint(start);
          await abortedGet(start);
          final client = HttpClient();
          final request = await client.getUrl(handle.playbackUri);
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${start + 8191}');
          await (await request.close()).drain<void>();
          client.close(force: true);
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      await burst(5); // warm up: pools, lazily opened files
      final base = _fds();
      await burst(40);
      final after = _fds();
      // ignore: avoid_print
      print('fd baseline=$base after=$after');
      expect(after, lessThanOrEqualTo(base + 3));
      await handle.dispose();
    } finally {
      await source.dispose();
      await cache.delete(recursive: true);
      await sub.cancel();
      fixture.kill(ProcessSignal.sigterm);
      await errs;
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
