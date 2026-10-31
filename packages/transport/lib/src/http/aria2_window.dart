import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';

import '../cache/fs_native.dart';
import '../cache/range_ops.dart';
import 'http_options.dart';

/// The origin asked the client to slow down (HTTP 429/503 with Retry-After).
/// [retryAfter] is the wait it asked for, capped at [maxRetryAfter], or null.
class OriginRateLimited extends HttpException {
  OriginRateLimited(super.message, {super.uri, this.retryAfter});
  static const Duration maxRetryAfter = Duration(seconds: 60);
  final Duration? retryAfter;

  /// Retry-After is delta-seconds or an HTTP date; anything else is ignored.
  static Duration? parse(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    Duration? wait;
    if (seconds != null) {
      wait = Duration(seconds: seconds);
    } else {
      try {
        wait = HttpDate.parse(value).difference(DateTime.now());
      } on HttpException {
        return null;
      } on FormatException {
        return null;
      }
    }
    if (wait.isNegative) return null;
    return wait > maxRetryAfter ? maxRetryAfter : wait;
  }
}

/// Loopback slice server used to seek: aria2 has no HTTP offset-priority call
/// (aria2.h exposes only queue-position changePosition), so the wanted slice is
/// presented to aria2 as its own file, served from the origin via a Range request.
class Aria2Window {
  static const Duration idleTimeout = Duration(seconds: 15);
  static const _transientStatuses = {408, 429, 500, 502, 503, 504};

  /// Origin requests in flight per host. aria2 stripes a window over 8 loopback
  /// connections; without this cap they all hit the origin at once and a rate
  /// limiter (Cloudflare) answers 429.
  static const maxOriginRequestsPerHost = 4;
  static final Map<String, int> _inFlight = {};
  static final Map<String, List<Completer<void>>> _waiting = {};

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
    var acquired = false;
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
      await _acquire(spec.uri.host);
      acquired = true;
      if (disconnected) return;
      // dart:io starts a spare connect when a queued request is served by an
      // idle socket; closing the client cancels it with no listener. Catch
      // that in the zone that created it instead of leaking it to the app.
      origin = await runZonedGuarded<Future<HttpClientRequest>>(
        () => _client.getUrl(spec.uri),
        (error, stack) {
          if (!_closed) failure ??= error;
        },
      )!;
      for (final entry in originHeaders(spec, options).entries) {
        origin.headers.set(entry.key, entry.value);
      }
      origin.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      origin.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=${range.start + start}-${range.start + end}',
      );
      final response = await origin.close().timeout(idleTimeout);
      final expected =
          'bytes ${range.start + start}-${range.start + end}/$total';
      // Rate limits and gateway errors are the network, not a missing feature: a plain
      // error is retried with backoff, only a real answer that ignores Range is final.
      if (_transientStatuses.contains(response.statusCode)) {
        await response.drain<void>();
        final retry = response.headers.value(HttpHeaders.retryAfterHeader);
        throw OriginRateLimited(
          'origin returned ${response.statusCode} (retry-after $retry)',
          uri: spec.uri,
          retryAfter: OriginRateLimited.parse(retry),
        );
      }
      if (response.statusCode != HttpStatus.partialContent ||
          response.headers.value('content-range') != expected ||
          (response.contentLength != -1 &&
              response.contentLength != end - start + 1)) {
        _client.close(force: true);
        throw TransportFailure.httpNoRangeSupport(
          cause:
              'invalid seek response: expected 206 $expected '
              'content-length ${end - start + 1}, got ${response.statusCode} '
              '${response.headers.value('content-range')} '
              'content-length ${response.contentLength} '
              'redirects ${response.redirects.length}',
        );
      }
      // A half-open connection never errors: no bytes for this long is an
      // outage, and the backend retries the window.
      await request.response.addStream(response.timeout(idleTimeout));
      await request.response.close();
    } catch (error) {
      // Let response.done distinguish local cancellation from origin failure.
      await Future<void>.value();
      if (!_closed && !disconnected) failure = error;
      await request.response.close().catchError((Object closeError) {
        if (!_closed && !disconnected) failure ??= closeError;
        return request.response;
      });
    } finally {
      if (acquired) _release(spec.uri.host);
    }
  }

  static Future<void> _acquire(String host) {
    final used = _inFlight[host] ?? 0;
    if (used < maxOriginRequestsPerHost) {
      _inFlight[host] = used + 1;
      return Future<void>.value();
    }
    final turn = Completer<void>();
    (_waiting[host] ??= []).add(turn);
    return turn.future;
  }

  // A waiter inherits the released slot, so the count stays unchanged.
  static void _release(String host) {
    final queue = _waiting[host];
    if (queue != null && queue.isNotEmpty) {
      queue.removeAt(0).complete();
      return;
    }
    final used = (_inFlight[host] ?? 1) - 1;
    if (used <= 0) {
      _inFlight.remove(host);
    } else {
      _inFlight[host] = used;
    }
  }

  final Set<Future<void>> _copies = {};

  /// Copies run until done or [close]; close waits for them before deleting.
  Future<void> copyAvailable(
    RangeSet available,
    File destination, {
    bool releaseCopied = false,
    void Function(ByteRange)? onCopied,
    bool Function()? shouldStop,
  }) {
    if (_closed) return Future<void>.value();
    final copy = _copyAvailable(
      available,
      destination,
      releaseCopied: releaseCopied,
      onCopied: onCopied,
      shouldStop: () => _closed || (shouldStop?.call() ?? false),
    );
    _copies.add(copy);
    return copy.whenComplete(() => _copies.remove(copy));
  }

  Future<void> _copyAvailable(
    RangeSet available,
    File destination, {
    required bool releaseCopied,
    void Function(ByteRange)? onCopied,
    required bool Function() shouldStop,
  }) async {
    final fs = releaseCopied ? FsNative() : null;
    if (available.ranges.isEmpty) return;
    final RandomAccessFile input;
    try {
      input = await file.open();
    } on PathNotFoundException {
      // close() deleted the window directory while this copy was starting
      // (a seek or dispose raced a status poll): nothing left to copy.
      if (_closed) return;
      rethrow;
    }
    final output = await destination.open(mode: FileMode.writeOnlyAppend);
    // Punching a hole costs a filesystem round trip (~100 ms on a phone's
    // flash); one per 256 KiB chunk made a large backlog take minutes, so the
    // copied bytes are released in batches.
    var punchFrom = -1;
    var punchLength = 0;
    void releaseBatch() {
      if (punchLength > 0) fs?.punchHole(file.path, punchFrom, punchLength);
      punchLength = 0;
    }

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
          if (shouldStop()) return;
          final count = remaining.clamp(0, 256 * 1024);
          final bytes = await input.read(count);
          if (bytes.length != count) {
            throw StateError('short aria2 seek-window read');
          }
          await output.writeFrom(bytes);
          final start = fresh.endInclusive - remaining + 1;
          final done = ByteRange(start, start + count - 1);
          copied = copied.add(done);
          onCopied?.call(done);
          // The completed segment now lives in the main sparse file; its
          // staging blocks are released so both files share one budget.
          if (fs != null) {
            if (punchLength == 0) punchFrom = start;
            punchLength += count;
            if (punchLength >= _punchBatch) releaseBatch();
          }
          remaining -= count;
        }
        releaseBatch();
        await output.flush();
        copied = copied.add(fresh);
      }
    } finally {
      releaseBatch();
      await input.close();
      await output.close();
    }
  }

  static const int _punchBatch = 1024 * 1024;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await server.close(force: true);
    // Each copy reports its own failure to its caller.
    await Future.wait([for (final c in _copies) c.catchError((Object _) {})]);
    await directory.delete(recursive: true);
  }
}
