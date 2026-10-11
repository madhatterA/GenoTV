import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'range_parser.dart';
import 'sparse_source.dart';
import 'demand.dart';

const int rangeChunkSize = 256 * 1024;
const int rangeServeWindow = 4 * 1024 * 1024;
const Duration rangeWaitTimeout = Duration(seconds: 30);

class RangeServer {
  RangeServer._(this._server, this._logger);

  final HttpServer _server;
  final AppLogger? _logger;
  final Map<String, _Registration> _streams = <String, _Registration>{};
  final Set<Future<void>> _inFlight = <Future<void>>{};
  final DemandRegistry _demands = DemandRegistry();
  bool _closed = false;

  static Future<RangeServer> start({AppLogger? logger}) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
    }
    final result = RangeServer._(server, logger);
    server.listen(result._handle);
    return result;
  }

  int get port => _server.port;
  InternetAddress get address => _server.address;

  Uri register(SparseSource source, {String? filename, String? contentType}) {
    if (_closed) throw StateError('RangeServer is closed');
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    final name = filename == null || filename.isEmpty ? 'stream' : filename;
    _streams[token] = _Registration(source, contentType ?? _guessType(name));
    return Uri(
      scheme: 'http',
      host: _server.address.address,
      port: port,
      path: '/s/$token/$name',
    );
  }

  void unregister(Uri uri) {
    final token = _token(uri.pathSegments);
    if (token != null) _streams.remove(token);
  }

  Future<void> _handle(HttpRequest request) {
    final work = _serve(request);
    _inFlight.add(work);
    work.whenComplete(() => _inFlight.remove(work));
    return work;
  }

  Future<void> _serve(HttpRequest request) async {
    final token = _token(request.uri.pathSegments);
    final registration = token == null ? null : _streams[token];
    if (registration == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      _logger?.warn('Unknown transport stream token', error: request.uri);
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    final source = registration.source;
    final size = source.totalBytes;
    if (size == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      await request.response.close();
      return;
    }
    final parsed = parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      size,
    );
    if (parsed.kind == RangeParseKind.unsatisfiable) {
      final failure = TransportFailure.rangeUnsatisfiable(
        cause: request.headers.value(HttpHeaders.rangeHeader),
      );
      _logger?.warn('Unsatisfiable transport range', error: failure);
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set('Content-Range', 'bytes */$size');
      await request.response.close();
      return;
    }
    final range = parsed.kind == RangeParseKind.valid
        ? parsed.range!
        : ByteRange(0, size - 1);
    final partial = parsed.kind == RangeParseKind.valid;
    final response = request.response;
    response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, registration.contentType)
      ..set(HttpHeaders.contentLengthHeader, range.length);
    if (partial) {
      response.headers.set(
        'Content-Range',
        'bytes ${range.start}-${range.endInclusive}/$size',
      );
    }
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    final tokenObject = _demands.register(range);
    var sourceFailed = false;
    try {
      // Start with one disk-read chunk; read() waits for subsequent chunks.
      // Keep the larger read stream so its cache reader tracks progress.
      for (var start = range.start; start <= range.endInclusive;) {
        final end = min(start + rangeServeWindow - 1, range.endInclusive);
        final window = ByteRange(start, end);
        await source
            .waitFor(ByteRange(start, min(start + rangeChunkSize - 1, end)))
            .timeout(rangeWaitTimeout);
        var pulled = 0;
        await response.addStream(
          source
              .read(window)
              .timeout(rangeWaitTimeout)
              .transform(
                StreamTransformer<List<int>, List<int>>.fromHandlers(
                  handleData: (chunk, sink) {
                    pulled += chunk.length;
                    sink.add(chunk);
                  },
                  handleError: (e, s, sink) {
                    sourceFailed = true;
                    sink.addError(e, s);
                  },
                ),
              ),
        );
        // A closed client socket cancels the source stream and addStream
        // returns normally, so a short read means the client is gone.
        if (pulled < window.length) throw const _ClientDisconnected();
        start = end + 1;
      }
      _demands.release(tokenObject);
      source.releaseDemand(tokenObject);
      await response.close();
    } catch (error, stack) {
      source.releaseDemand(tokenObject);
      _demands.release(tokenObject);
      // A client that drops the connection mid-body (normal on seek) makes
      // the socket write fail; a disposed source ends the wait. Neither is a
      // failure; origin/disk errors (sourceFailed) and timeouts still are.
      final disconnected =
          error is _ClientDisconnected ||
          (!sourceFailed &&
              (error is HttpException || error is SocketException));
      if (disconnected || error is SparseSourceDisposed) {
        _logger?.info(
          disconnected
              ? 'Transport client disconnected mid-response'
              : 'Transport source disposed mid-response',
          data: <String, Object?>{'range': range.toString(), 'token': token},
        );
        // The failed write also fails response.done; consume it here so it
        // cannot escape as an unhandled async error.
        unawaited(response.done.then((_) {}, onError: (Object _) {}));
        if (error is SparseSourceDisposed) await _abort(response);
        return;
      }
      final failure = error is TimeoutException
          ? TransportFailure.httpUnreachable(cause: error, stack: stack)
          : error is TransportFailure
          ? error
          : null;
      _logger?.error(
        'Transport range response failed',
        error: failure ?? error,
        stack: stack,
      );
      await _abort(response);
    }
  }

  // Drops the connection. Once the body has started, detachSocket throws and
  // close() fails on the short body (which also destroys the socket); that
  // failure is the abort itself, the cause is logged by the caller.
  Future<void> _abort(HttpResponse response) async {
    try {
      unawaited(
        response
            .detachSocket(writeHeaders: false)
            .then((socket) => socket.destroy()),
      );
    } catch (_) {
      await response.close().then((_) {}, onError: (Object _) {});
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
    await Future.wait(_inFlight, eagerError: false);
    _streams.clear();
  }

  String? _token(List<String> segments) =>
      segments.length >= 2 && segments.first == 's' ? segments[1] : null;

  static String _guessType(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    const types = <String, String>{
      'mp4': 'video/mp4',
      'm4v': 'video/mp4',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
    };
    return types[extension] ?? 'application/octet-stream';
  }
}

class _ClientDisconnected implements Exception {
  const _ClientDisconnected();
}

class _Registration {
  const _Registration(this.source, this.contentType);
  final SparseSource source;
  final String contentType;
}
