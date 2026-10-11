import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../core/cast_media.dart';
import '../core/media_proxy.dart';
import '../remux/remuxer.dart';
import '../utils/logger.dart';
import 'media_transformer.dart';

/// Serves bounded reads of growing output, and complete, atomically published HLS assets.
final class ProgressiveOutput {
  ProgressiveOutput({
    required this.task,
    required this.file,
    required this.directory,
    required this.type,
    required this.proxy,
    required this.inputRoutes,
  }) {
    _completion = task.done.then<void>(
      (outcome) {
        _finished = true;
        if (outcome == RemuxOutcome.cancelled && !_disposed) {
          _error = const CastTransformFailure('Remux cancelled');
        }
      },
      onError: (Object error, StackTrace stack) {
        _finished = true;
        _error = CastTransformFailure(error);
        CastLogger.error('Generated cast media failed: $error\n$stack');
      },
    );
  }
  final RemuxTask task;
  final File file;
  final Directory directory;
  final CastMediaType type;
  final MediaProxy proxy;
  final List<String> inputRoutes;
  String? prefix;
  bool _finished = false;
  bool _disposed = false;
  Object? _error;
  late final Future<void> _completion;
  Future<void>? _disposing;

  Future<void> get ready => _waitFor(file);

  void _check() {
    if (_error != null) throw _error!;
    if (_disposed) throw const CastTransformFailure('Transform disposed');
  }

  Future<void> _waitFor(File target) async {
    for (;;) {
      _check();
      if (await target.exists() && await target.length() > 0) return;
      if (_finished) throw const CastTransformFailure('Output missing');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> serve(HttpRequest request, String leaf) async {
    final valid = type == CastMediaType.hls
        ? leaf == file.uri.pathSegments.last ||
              RegExp(r'^stream\d+\.ts$').hasMatch(leaf)
        : leaf == file.uri.pathSegments.last;
    if (!valid || request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = valid
          ? HttpStatus.methodNotAllowed
          : HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final target = File('${file.parent.path}/$leaf');
    try {
      await _waitFor(target);
      if (leaf.endsWith('.m3u8')) {
        // Native temp_file publication makes each playlist snapshot consistent.
        final bytes = await target.readAsBytes();
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.contentLength = bytes.length;
        if (request.method == 'GET') request.response.add(bytes);
        await request.response.close();
      } else {
        await _serveBytes(
          request,
          target,
          complete: _finished || type == CastMediaType.hls,
        );
      }
    } catch (error, stack) {
      CastLogger.error('Generated output serve failed: $error\n$stack');
      // Once streaming has begun a broken output must terminate the connection;
      // a normal EOF would present truncated media as a completed response.
      request.response.addError(error, stack);
      await request.response.close();
    }
  }

  Future<void> _serveBytes(
    HttpRequest request,
    File target, {
    required bool complete,
  }) async {
    final response = request.response;
    response.headers.contentType = target.path.endsWith('.ts')
        ? ContentType('video', 'mp2t')
        : type == CastMediaType.mkv
        ? ContentType('video', 'x-matroska')
        : ContentType('video', 'mp4');
    response.headers.set(
      HttpHeaders.acceptRangesHeader,
      complete ? 'bytes' : 'none',
    );
    final length = await target.length();
    var start = 0;
    int? end = complete ? length : null;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    // A server may ignore Range while total length is unknown. Stream the full
    // representation with chunked framing; never invent a final Content-Length.
    if (range != null && complete) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      var valid =
          match != null && (match[1]!.isNotEmpty || match[2]!.isNotEmpty);
      if (valid) {
        if (match[1]!.isEmpty) {
          final suffix = int.tryParse(match[2]!);
          valid = suffix != null && suffix > 0;
          if (valid) start = math.max(0, length - suffix);
        } else {
          start = int.tryParse(match[1]!) ?? length;
          final last = match[2]!.isEmpty ? length - 1 : int.tryParse(match[2]!);
          valid = last != null && last >= start;
          if (valid) end = math.min(length, last + 1);
        }
      }
      if (!valid || start >= length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        response.contentLength = 0;
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${end! - 1}/$length',
      );
    }
    if (end != null) response.contentLength = end - start;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    var position = start;
    for (;;) {
      _check();
      final available = end ?? await target.length();
      if (position < available) {
        final next = math.min(available, position + 65536);
        await response.addStream(target.openRead(position, next));
        await response.flush();
        position = next;
      } else if (end != null) {
        break;
      } else if (_finished) {
        if (position < await target.length()) continue;
        break;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    await response.close();
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    task.cancel();
    await _completion;
    if (prefix != null) proxy.unregisterGeneratedMedia(prefix!);
    for (final route in inputRoutes) {
      proxy.unregisterMedia(route);
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
