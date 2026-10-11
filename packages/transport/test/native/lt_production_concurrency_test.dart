import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/stream_source_impl.dart';

void main() {
  test(
    'packaged torrent source serves two concurrent consumers',
    () async {
      final fixture = await Process.start('python3', <String>[
        'tool/libtorrent_magnet_fixture.py',
      ], workingDirectory: Directory.current.path);
      final magnet = Completer<String>();
      final stdoutSub = fixture.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('magnet=') && !magnet.isCompleted) {
              magnet.complete(line.substring(7));
            }
          });
      final stderrSub = fixture.stderr.drain<void>();
      final cache = await Directory.systemTemp.createTemp('transport-concurrent-');
      final source = StreamSourceImpl(logger: _SilentLogger(), cacheDir: cache);
      try {
        final handle = await source
            .open(
              SourceSpec(
                kind: SourceKind.torrentMagnet,
                uri: Uri.parse(await magnet.future.timeout(const Duration(seconds: 30))),
              ),
            )
            .timeout(const Duration(seconds: 35));
        try {
          final responses = await Future.wait(<Future<List<int>>>[
            _range(handle.playbackUri, 0, 4095),
            _range(handle.playbackUri, 24 * 1024 * 1024, 24 * 1024 * 1024 + 4095),
          ]).timeout(const Duration(seconds: 35));
          expect(responses, hasLength(2));
          expect(responses[0], orderedEquals(List<int>.generate(4096, (i) => i % 251)));
          expect(
            responses[1],
            orderedEquals(List<int>.generate(4096, (i) => (i + 24 * 1024 * 1024) % 251)),
          );
        } finally {
          await handle.dispose();
        }
      } finally {
        await source.dispose();
        // Terminate before waiting for pipe EOF; the fixture may still be running.
        fixture.kill(ProcessSignal.sigterm);
        await stdoutSub.cancel();
        await fixture.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
          fixture.kill(ProcessSignal.sigkill);
          return -9;
        });
        await stderrSub;
        await cache.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<List<int>> _range(Uri uri, int start, int end) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.partialContent);
    return await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
  } finally {
    client.close(force: true);
  }
}

final class _SilentLogger implements AppLogger {
  @override
  void debug(String message, {Object? data}) {}
  @override
  void info(String message, {Object? data}) {}
  @override
  void warn(String message, {Object? error, StackTrace? stack}) {}
  @override
  void error(String message, {required Object error, StackTrace? stack}) {}
  @override
  AppLogger scoped(String name) => this;
}
