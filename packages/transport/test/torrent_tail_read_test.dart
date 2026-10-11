import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

/// Regression (owner, Runner YTS MP4): head read, then the tail (moov at the
/// end), then the middle, with the status polled all along. A healthy stream
/// must never report stalled/failed, and building a status must not trip the
/// "failure iff failed/stalled" assertion.
void main() {
  test('mpv-like head/tail/middle reads never report a stall', () async {
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: Directory.current.path);
    String? magnet;
    final ready = Completer<void>();
    final out = fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('magnet=')) {
            magnet = line.substring('magnet='.length);
            if (!ready.isCompleted) ready.complete();
          }
        });
    final err = fixture.stderr.drain<void>();
    final cache = await Directory.systemTemp.createTemp('transport-tail-');
    final source = StreamSourceImpl(logger: _QuietLogger(), cacheDir: cache);
    final errors = <Object>[];
    try {
      await runZonedGuarded(() async {
        await ready.future.timeout(const Duration(seconds: 30));
        final handle = await source
            .open(SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(magnet!)))
            .timeout(const Duration(seconds: 35));
        final bad = <SourceStatus>[];
        final sub = handle.status.listen((s) {
          if (s.state == SourceState.stalled || s.state == SourceState.failed) bad.add(s);
        });
        const size = 32 * 1024 * 1024;
        // Open-ended head read left idle past the stall threshold.
        final client = HttpClient();
        final headReq = await client.getUrl(handle.playbackUri);
        headReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
        final headRes = await headReq.close();
        final headSub = headRes.listen((_) {})..pause();
        final tail = await _range(handle.playbackUri, size - 4096, size - 1);
        expect(tail, hasLength(4096));
        await handle.seekHint(size ~/ 2);
        final mid = await _range(handle.playbackUri, size ~/ 2, size ~/ 2 + 4095);
        expect(mid, hasLength(4096));
        await Future<void>.delayed(torrentStallThreshold + const Duration(seconds: 2));
        expect(bad, isEmpty, reason: bad.map((s) => '${s.state} ${s.failure}').join(', '));
        await headSub.cancel();
        client.close(force: true);
        await sub.cancel();
        await handle.dispose();
      }, (e, s) => errors.add(e));
      expect(errors, isEmpty);
    } finally {
      await source.dispose();
      await cache.delete(recursive: true);
      await out.cancel();
      fixture.kill(ProcessSignal.sigterm);
      await err;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
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
