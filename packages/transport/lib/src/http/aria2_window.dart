import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';

import '../cache/fs_native.dart';
import '../cache/range_ops.dart';
import 'http_options.dart';

/// Loopback slice server used to seek: aria2 has no HTTP offset-priority call
/// (aria2.h exposes only queue-position changePosition), so the wanted slice is
/// presented to aria2 as its own file, served from the origin via a Range request.
class Aria2Window {
  Aria2Window(
    this.spec,
    this.range,
    this.total,
    this.directory,
    this.server,
    this.options,
  ) : _client = configureOriginClient(
        HttpClient()..autoUncompress = false,
        options,
      );
  final SourceSpec spec;
  final ByteRange range;
  final int total;
  final Directory directory;
  final HttpServer server;
  final TransportOptions options;
  final HttpClient _client;
  int? gid;
  Object? failure;
  bool _closed = false;
  RangeSet copied = RangeSet.empty();
  File get file => File('${directory.path}/window.bin');
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/window');

  static Future<Aria2Window> open(
    SourceSpec spec,
    ByteRange range,
    int total,
    Directory cache, [
    TransportOptions options = const TransportOptions(),
  ]) async {
    final directory = await cache.createTemp('aria2-window-');
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final window = Aria2Window(
        spec,
        range,
        total,
        directory,
        server,
        options,
      );
      server.listen(window._serve);
      return window;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _serve(HttpRequest request) async {
    var disconnected = false;
    HttpClientRequest? origin;
    unawaited(
      request.response.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          disconnected = true;
          origin?.abort(error, stack);
        },
      ),
    );
    try {
      if (request.uri.path != '/window' ||
          (request.method != 'GET' && request.method != 'HEAD')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final header = request.headers.value(HttpHeaders.rangeHeader);
      final match = header == null
          ? null
          : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(header);
      final start = match == null ? 0 : int.parse(match[1]!);
      final end = match == null || match[2]!.isEmpty
          ? range.length - 1
          : int.parse(match[2]!);
      if ((header != null && match == null) ||
          start > end ||
          start >= range.length ||
          end >= range.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          'Content-Range',
          'bytes */${range.length}',
        );
        await request.response.close();
        return;
      }
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.contentLength = end - start + 1;
      if (header != null) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-$end/${range.length}',
        );
      }
      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }
      origin = await _client.getUrl(spec.uri);
      for (final entry in originHeaders(spec, options).entries) {
        origin.headers.set(entry.key, entry.value);
      }
      origin.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      origin.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=${range.start + start}-${range.start + end}',
      );
      final response = await origin.close();
      final expected =
          'bytes ${range.start + start}-${range.start + end}/$total';
      if (response.statusCode != HttpStatus.partialContent ||
          response.headers.value('content-range') != expected ||
          (response.contentLength != -1 &&
              response.contentLength != end - start + 1)) {
        _client.close(force: true);
        throw TransportFailure.httpNoRangeSupport(
          cause: 'invalid seek response: expected $expected',
        );
      }
      await request.response.addStream(response);
      await request.response.close();
    } catch (error) {
      // Let response.done distinguish local cancellation from origin failure.
      await Future<void>.value();
      if (!_closed && !disconnected) failure = error;
      await request.response.close().catchError((Object closeError) {
        if (!_closed && !disconnected) failure ??= closeError;
        return request.response;
      });
    }
  }

  Future<void> copyAvailable(
    RangeSet available,
    File destination, {
    bool releaseCopied = false,
    void Function(ByteRange)? onCopied,
  }) async {
    final fs = releaseCopied ? FsNative() : null;
    if (available.ranges.isEmpty) return;
    final input = await file.open();
    final output = await destination.open(mode: FileMode.writeOnlyAppend);
    try {
      var pending = available;
      for (final done in copied.ranges) {
        pending = subtractRange(pending, done);
      }
      for (final fresh in pending.ranges) {
        await input.setPosition(fresh.start);
        await output.setPosition(range.start + fresh.start);
        var remaining = fresh.length;
        while (remaining > 0) {
          final count = remaining.clamp(0, 256 * 1024);
          final bytes = await input.read(count);
          if (bytes.length != count) {
            throw StateError('short aria2 seek-window read');
          }
          await output.writeFrom(bytes);
          // The completed segment now lives in the main sparse file. Release
          // its staging blocks immediately so both files share one budget.
          fs?.punchHole(file.path, fresh.endInclusive - remaining + 1, count);
          final done = ByteRange(
            fresh.endInclusive - remaining + 1,
            fresh.endInclusive - remaining + count,
          );
          copied = copied.add(done);
          onCopied?.call(done);
          remaining -= count;
        }
        await output.flush();
        copied = copied.add(fresh);
      }
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  }
}
