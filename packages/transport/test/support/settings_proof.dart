import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';

/// Appends one readback row to the file named by READBACK_OUT (if set).
void readbackRow({
  required String setting,
  required String value,
  required String sent,
  required String readBack,
  required bool pass,
}) {
  final out = Platform.environment['READBACK_OUT'];
  if (out == null) return;
  File(out).writeAsStringSync(
    '| $setting | $value | $sent | $readBack | ${pass ? 'PASS' : 'FAIL'} |\n',
    mode: FileMode.append,
  );
}

final class QuietLogger implements AppLogger {
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

/// Range-capable loopback origin that records what it sees.
final class ProofOrigin {
  ProofOrigin._(this.server, this.size, this.chunkDelay);
  final HttpServer server;
  final int size;
  final Duration chunkDelay;
  final List<Map<String, String>> requests = [];
  final List<String> methods = [];
  int active = 0;
  int maxActive = 0;
  int bytesSent = 0;

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/media.bin');

  static Future<ProofOrigin> start({
    int size = 16 * 1024 * 1024,
    Duration chunkDelay = Duration.zero,
  }) async {
    final origin = ProofOrigin._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      size,
      chunkDelay,
    );
    origin.server.listen(origin._serve);
    return origin;
  }

  Future<void> _serve(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((k, v) => headers[k] = v.join(','));
    requests.add(headers);
    methods.add(request.method);
    final match = RegExp(
      r'^bytes=(\d+)-(\d*)$',
    ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    final start = match == null ? 0 : int.parse(match[1]!);
    final end = match == null || match[2]!.isEmpty
        ? size - 1
        : int.parse(match[2]!);
    final response = request.response
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..headers.set(HttpHeaders.etagHeader, '"proof"')
      ..contentLength = end - start + 1;
    if (match != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('Content-Range', 'bytes $start-$end/$size');
    }
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    active++;
    if (active > maxActive) maxActive = active;
    var counted = true;
    void finish() {
      if (counted) active--;
      counted = false;
    }

    unawaited(response.done.then<void>((_) => finish(), onError: (_) => finish()));
    try {
      const chunk = 64 * 1024;
      var at = start;
      while (at <= end) {
        final n = (end - at + 1) < chunk ? end - at + 1 : chunk;
        response.add(List<int>.filled(n, at % 251));
        bytesSent += n;
        at += n;
        await response.flush();
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      }
      await response.close();
    } on Object {
      // client went away
    } finally {
      finish();
    }
  }

  Future<void> close() => server.close(force: true);
}

/// Reads [length] bytes from [start] of [uri] with a Range request.
Future<int> fetchRange(Uri uri, int start, int length) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=$start-${start + length - 1}',
    );
    final response = await request.close();
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
    }
    return total;
  } finally {
    client.close(force: true);
  }
}
