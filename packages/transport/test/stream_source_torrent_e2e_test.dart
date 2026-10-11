import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  test('production StreamSource opens the legal local magnet and serves exact seeks', () async {
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: Directory.current.path);
    final lines = fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    String? magnet;
    final ready = Completer<void>();
    final output = <String>[];
    final subscription = lines.listen((line) {
      output.add(line);
      if (line.startsWith('magnet=')) {
        magnet = line.substring('magnet='.length);
        if (!ready.isCompleted) ready.complete();
      }
    });
    final errors = fixture.stderr.transform(utf8.decoder).listen(output.add);
    final cache = await Directory.systemTemp.createTemp(
      'transport-torrent-e2e-',
    );
    final source = StreamSourceImpl(logger: _QuietLogger(), cacheDir: cache);
    try {
      await ready.future.timeout(const Duration(seconds: 30));
      final handle = await source
          .open(
            SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(magnet!)),
          )
          .timeout(const Duration(seconds: 35));
      try {
        final first = await _range(handle.playbackUri, 0, 4095);
        expect(first, hasLength(4096));
        expect(first, orderedEquals(List<int>.generate(4096, (i) => i % 251)));
        await handle.seekHint(24 * 1024 * 1024);
        final second = await _range(
          handle.playbackUri,
          24 * 1024 * 1024,
          24 * 1024 * 1024 + 4095,
        );
        expect(
          second,
          orderedEquals(
            List<int>.generate(4096, (i) => (i + 24 * 1024 * 1024) % 251),
          ),
        );
        // Live counters straight from libtorrent (shim transport_lt_torrent_stats).
        final stats = await (handle as TransportStatsProvider).readStats();
        final torrent = stats.torrent!;
        expect(torrent.infoHash, hasLength(40));
        expect(torrent.piecesTotal, greaterThan(0));
        expect(torrent.piecesHave, inInclusiveRange(1, torrent.piecesTotal));
        expect(torrent.pieceSize, greaterThan(0));
        expect(torrent.seeds, greaterThanOrEqualTo(0));
        expect(torrent.uploadBytesPerSecond, greaterThanOrEqualTo(0));
        expect(stats.totalBytes, greaterThan(0));
        expect(stats.downloadedBytes, greaterThan(0));
      } finally {
        await handle.dispose();
      }
      await source.dispose();
    } finally {
      await source.dispose();
      await cache.delete(recursive: true);
      await subscription.cancel();
      await errors.cancel();
      fixture.kill(ProcessSignal.sigterm);
      await fixture.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          fixture.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
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

final class _QuietLogger implements AppLogger {
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
