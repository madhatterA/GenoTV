import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:contracts/contracts.dart';
import 'package:transport/src/stream_source_impl.dart';

Future<void> main() async {
  final fixture = await Process.start('python3', <String>[
    'tool/libtorrent_magnet_fixture.py',
  ], workingDirectory: Directory.current.path);
  final output = <String>[];
  final ready = Completer<String>();
  final sub = fixture.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    output.add(line);
    stderr.writeln('fixture: $line');
    if (line.startsWith('magnet=') && !ready.isCompleted) ready.complete(line.substring(7));
  });
  final err = fixture.stderr.transform(utf8.decoder).listen((line) {
    output.add(line);
    stderr.writeln('fixture stderr: $line');
  });
  final cache = await Directory.systemTemp.createTemp('transport-debug-');
  final source = StreamSourceImpl(logger: _Logger(), cacheDir: cache);
  try {
    final magnet = await ready.future.timeout(const Duration(seconds: 30));
    final handle = await source.open(SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(magnet))).timeout(const Duration(seconds: 35));
    try {
      final request = await HttpClient().getUrl(handle.playbackUri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-4095');
      final response = await request.close();
      stderr.writeln('response=${response.statusCode} length=${response.contentLength}');
      final body = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      stderr.writeln('body=${body.length}');
    } finally {
      await handle.dispose();
    }
  } finally {
    await source.dispose();
    await sub.cancel();
    await err.cancel();
    fixture.kill(ProcessSignal.sigterm);
    await fixture.exitCode.timeout(const Duration(seconds: 5), onTimeout: () { fixture.kill(ProcessSignal.sigkill); return -9; });
    await cache.delete(recursive: true);
  }
}

final class _Logger implements AppLogger {
  @override
  void debug(String message, {Object? data}) => stderr.writeln('debug: $message $data');
  @override
  void info(String message, {Object? data}) => stderr.writeln('info: $message $data');
  @override
  void warn(String message, {Object? error, StackTrace? stack}) => stderr.writeln('warn: $message $error');
  @override
  void error(String message, {required Object error, StackTrace? stack}) => stderr.writeln('error: $message $error\n$stack');
  @override
  AppLogger scoped(String name) => this;
}
