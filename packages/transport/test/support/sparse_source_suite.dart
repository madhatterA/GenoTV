import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

/// Shared contract both [Aria2Backend] implementations must pass: given a
/// real local HTTP server serving a known payload, driving the backend
/// through [HttpSparseSource] — never `HttpClient`/RPC directly — must
/// produce a byte-exact file, verified by sha256, not merely "some bytes
/// arrived" (`planning/part-03-transport/chapter-02-http-source/
/// phase-05-platform-availability.md` Proof).
///
/// [createBackend] must return a fresh backend per call; the caller is
/// responsible for anything the backend itself requires to be present
/// (e.g. the libaria2 shim library) — a missing dependency must make the test
/// fail, never skip.
void runSparseBackendDownloadSuite(
  String label,
  Aria2Backend Function() createBackend,
) {
  test('$label: downloads a full file byte-exact (sha256-checked)', () async {
    final payload = List<int>.generate(200 * 1024, (i) => i % 251);
    final cache = await Directory.systemTemp.createTemp('sparse-suite-');
    final server = await _rangeServer(payload);
    final backend = createBackend();
    try {
      final outPath = '${cache.path}/out.bin';
      final spec = SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://127.0.0.1:${server.port}/media.bin'),
      );
      final jobId = await backend.addDownload(spec, outPath);
      final source = HttpSparseSource(
        file: File(outPath),
        totalBytes: payload.length,
        backend: backend,
        jobId: jobId,
      );
      source.startMonitoring();
      await source.waitFor(ByteRange(0, payload.length - 1));
      final downloaded = await File(outPath).readAsBytes();
      expect(
        await _sha256(downloaded),
        await _sha256(payload),
        reason: 'downloaded file must be byte-exact with the origin',
      );
      await source.dispose();
      await backend.remove(jobId);
    } finally {
      await backend.stop();
      await server.close();
      await cache.delete(recursive: true);
    }
  });

  test('$label: seeks mid-download before the earlier hole is filled', () async {
    final payload = List<int>.generate(
      16 * 1024 * 1024,
      (i) => (i * 17 + i ~/ 251) % 256,
    );
    final cache = await Directory.systemTemp.createTemp('sparse-seek-suite-');
    final releaseLinear = Completer<void>();
    final seekStarted = Completer<void>();
    final server = await _rangeServer(
      payload,
      delay: const Duration(milliseconds: 10),
      seekOffset: 10 * 1024 * 1024,
      seekEnd: 14 * 1024 * 1024 - 1,
      releaseLinear: releaseLinear,
      seekStarted: seekStarted,
    );
    final backend = createBackend();
    HttpSparseSource? source;
    try {
      final outPath = '${cache.path}/out.bin';
      final jobId = await backend.addDownload(
        SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('http://127.0.0.1:${server.port}/media.bin'),
        ),
        outPath,
      );
      source = HttpSparseSource(
        file: File(outPath),
        totalBytes: payload.length,
        backend: backend,
        jobId: jobId,
      )..startMonitoring();
      await source
          .waitFor(const ByteRange(0, 1024 * 1024 - 1))
          .timeout(const Duration(seconds: 15));
      const target = ByteRange(10 * 1024 * 1024, 14 * 1024 * 1024 - 1);
      const hole = ByteRange(3 * 1024 * 1024, 4 * 1024 * 1024 - 1);
      expect(source.available.containsRange(target), isFalse);
      expect(source.available.containsRange(hole), isFalse);
      await source.seekHint(target.start);
      await seekStarted.future.timeout(const Duration(seconds: 5));
      final sought = await source
          .read(target)
          .expand((chunk) => chunk)
          .toList()
          .timeout(const Duration(seconds: 15));
      expect(sought, payload.sublist(target.start, target.endInclusive + 1));
      expect(
        source.available.containsRange(hole),
        isFalse,
        reason: 'seek must relocate demand, not wait for the linear download',
      );
      releaseLinear.complete();
      final downloaded = await source
          .read(ByteRange(0, payload.length - 1))
          .expand((chunk) => chunk)
          .toList()
          .timeout(const Duration(seconds: 30));
      final originHash = await _sha256(payload);
      final outputHash = await _sha256(downloaded);
      expect(outputHash, originHash);
      expect(await _sha256(await File(outPath).readAsBytes()), originHash);
      // Test evidence includes the actual hashes and observed ordering.
      stderr.writeln(
        '$label seek=${target.start} earlierHoleAbsent=true origin_sha256=$originHash output_sha256=$outputHash',
      );
      await backend.remove(jobId);
    } finally {
      if (!releaseLinear.isCompleted) releaseLinear.complete();
      await source?.dispose();
      await backend.stop();
      await server.close();
      await cache.delete(recursive: true);
    }
  });
}

Future<_LocalRangeServer> _rangeServer(
  List<int> payload, {
  Duration delay = Duration.zero,
  int? seekOffset,
  int? seekEnd,
  Completer<void>? releaseLinear,
  Completer<void>? seekStarted,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // Not saved/cancelled explicitly: `HttpServer.close()` below tears down
  // the listener along with the server (same pattern would apply if this
  // were inlined in the test, as `http_end_to_end_test.dart` does).
  server.listen((request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (request.method == 'HEAD') {
      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = payload.length;
      await request.response.close();
      return;
    }
    var start = 0;
    var end = payload.length - 1;
    if (range != null) {
      final parts = range.substring(6).split('-');
      start = int.parse(parts.first);
      end = parts.last.isEmpty ? payload.length - 1 : int.parse(parts.last);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        'Content-Range',
        'bytes $start-$end/${payload.length}',
      );
    }
    if (start == seekOffset &&
        seekStarted != null &&
        !seekStarted.isCompleted) {
      seekStarted.complete();
    }
    request.response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    try {
      for (var offset = start; offset <= end; offset += 64 * 1024) {
        if (releaseLinear != null &&
            !(start >= seekOffset! && end <= seekEnd!) &&
            offset >= 2 * 1024 * 1024) {
          await releaseLinear.future;
        }
        final limit = (offset + 64 * 1024).clamp(offset, end + 1);
        request.response.add(payload.sublist(offset, limit));
        await request.response.flush();
        if (delay != Duration.zero) await Future<void>.delayed(delay);
      }
      await request.response.close();
    } on HttpException {
      // A seek cancels the old download connection.
    } on SocketException {
      // Backend teardown can disconnect an in-flight response.
    }
  });
  return _LocalRangeServer(server);
}

class _LocalRangeServer {
  _LocalRangeServer(this._server);
  final HttpServer _server;
  int get port => _server.port;
  Future<void> close() => _server.close(force: true);
}

Future<String> _sha256(List<int> bytes) async {
  final temp = await File(
    '${Directory.systemTemp.path}/sparse-suite-${identityHashCode(bytes)}-${DateTime.now().microsecondsSinceEpoch}.tmp',
  ).create();
  await temp.writeAsBytes(bytes);
  try {
    final result = await Process.run('shasum', ['-a', '256', temp.path]);
    if (result.exitCode != 0) {
      throw StateError('shasum failed: ${result.stderr}');
    }
    return (result.stdout as String).split(' ').first;
  } finally {
    await temp.delete();
  }
}
