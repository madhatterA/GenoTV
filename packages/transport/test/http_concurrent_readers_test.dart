import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

import 'support/settings_proof.dart';

/// A player streams a whole-file-cached mkv from byte 0 while it also reads
/// the index at the file end. The end read must not wait for the sequential
/// reader (real DigiMoviez stall, 2026-10-11).
void main() {
  test('index read at the file end completes while a sequential read streams', () async {
    final cache = await Directory.systemTemp.createTemp('transport-readers-');
    final origin = await ProofOrigin.start(
      size: 300 * 1024 * 1024,
      chunkDelay: const Duration(milliseconds: 40),
    );
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
    final handle = await source.open(
      SourceSpec(kind: SourceKind.httpUrl, uri: origin.uri),
    );
    try {
      final sequential = _read(handle.playbackUri, 0, origin.size - 1, 12 * 1024 * 1024);
      await Future<void>.delayed(const Duration(seconds: 2));
      final watch = Stopwatch()..start();
      final tail = await _read(
        handle.playbackUri,
        origin.size - 2 * 1024 * 1024,
        origin.size - 1,
        2 * 1024 * 1024,
      ).timeout(const Duration(seconds: 15));
      expect(tail, 2 * 1024 * 1024);
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
      expect(await sequential.timeout(const Duration(seconds: 60)), 12 * 1024 * 1024);
    } finally {
      await handle.dispose();
      await source.dispose();
      await origin.close();
      await cache.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<int> _read(Uri uri, int start, int end, int cap) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    var n = 0;
    await for (final c in response) {
      n += c.length;
      if (n >= cap) break;
    }
    return n;
  } finally {
    client.close(force: true);
  }
}
