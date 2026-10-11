import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';

import '../server/sparse_source.dart';

/// Range-backed HTTP source. Writes are offset-based and serialized, so
/// concurrent requests cannot share a mutable RandomAccessFile cursor.
class RemoteHttpSparseSource implements SparseSource {
  RemoteHttpSparseSource({
    required this.uri,
    required this.file,
    required this.headers,
    required this.totalBytes,
    this.validator,
  });

  final Uri uri;
  final File file;
  final Map<String, String> headers;
  @override
  final int? totalBytes;
  final String? validator;
  final HttpClient _client = HttpClient();
  final Map<ByteRange, Future<void>> _pending = <ByteRange, Future<void>>{};
  RangeSet _available = RangeSet.empty();
  Future<void> _writeTail = Future<void>.value();
  Future<void> _sidecarTail = Future<void>.value();
  bool _disposed = false;

  @override
  RangeSet get available => _available;

  Future<void> restoreAvailability() async {
    final sidecar = File('${file.path}.ranges');
    if (!await sidecar.exists() || !await file.exists()) return;
    try {
      final decoded = jsonDecode(await sidecar.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) return;
      if (decoded['length'] != totalBytes ||
          decoded['uri'] != uri.toString() ||
          decoded['validator'] != validator) {
        return;
      }
      final rawRanges = decoded['ranges'];
      if (rawRanges is! List) return;
      final fileLength = await file.length();
      var restored = RangeSet.empty();
      for (final item in rawRanges) {
        if (item is! List ||
            item.length != 2 ||
            item[0] is! int ||
            item[1] is! int) {
          return;
        }
        final start = item[0] as int;
        final end = item[1] as int;
        if (start < 0 ||
            end < start ||
            (totalBytes != null && end >= totalBytes!) ||
            end >= fileLength) {
          return;
        }
        restored = restored.add(ByteRange(start, end));
      }
      _available = restored;
    } catch (_) {
      _available = RangeSet.empty();
    }
  }

  @override
  Future<void> waitFor(ByteRange range) async {
    _check();
    if (_available.containsRange(range)) return;
    final existing = _pending[range];
    final pending = existing ?? _fetch(range);
    _pending[range] = pending;
    try {
      await pending;
    } finally {
      if (identical(_pending[range], pending)) {
        unawaited(_pending.remove(range));
      }
    }
  }

  Future<void> _fetch(ByteRange range) async {
    _check();
    final request = await _client.getUrl(uri);
    for (final entry in headers.entries) {
      request.headers.add(entry.key, entry.value);
    }
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${range.start}-${range.endInclusive}',
    );
    final response = await request.close();
    final actualValidator =
        response.headers.value('etag') ??
        response.headers.value('last-modified');
    if (validator != null &&
        actualValidator != null &&
        validator != actualValidator) {
      await response.drain<void>();
      throw TransportFailure.httpValidatorChanged(
        cause: 'expected $validator, received $actualValidator',
      );
    }
    if (response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw TransportFailure.httpNoRangeSupport(
        cause: 'upstream returned ${response.statusCode}',
      );
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (bytes.length != range.length) {
      throw StateError('upstream returned ${bytes.length} bytes for $range');
    }
    await _writeAt(range.start, bytes);
    _available = _available.add(range);
    await _writeSidecar();
  }

  Future<void> _writeAt(int offset, List<int> bytes) {
    final operation = _writeTail.then((_) async {
      await file.parent.create(recursive: true);
      final output = await file.open(mode: FileMode.writeOnly);
      try {
        await output.setPosition(offset);
        await output.writeFrom(bytes);
      } finally {
        await output.close();
      }
    });
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<void> _writeSidecar() async {
    final operation = _sidecarTail.then((_) async {
      final sidecar = File('${file.path}.ranges');
      final temp = File(
        '${sidecar.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      final payload = jsonEncode(<String, Object?>{
        'version': 1,
        'length': totalBytes,
        'uri': uri.toString(),
        'validator': validator,
        'ranges': _available.ranges
            .map((r) => <int>[r.start, r.endInclusive])
            .toList(),
      });
      await temp.writeAsString(payload, flush: true);
      await temp.rename(sidecar.path);
    });
    _sidecarTail = operation.catchError((_) {});
    await operation;
  }

  @override
  Stream<List<int>> read(ByteRange range) async* {
    await waitFor(range);
    final input = await file.open();
    try {
      await input.setPosition(range.start);
      var remaining = range.length;
      while (remaining > 0) {
        final count = remaining < 256 * 1024 ? remaining : 256 * 1024;
        final start = range.endInclusive - remaining + 1;
        final chunk = ByteRange(start, start + count - 1);
        if (!_available.containsRange(chunk)) {
          throw StateError('range became unavailable while reading $chunk');
        }
        final bytes = await input.read(count);
        if (bytes.length != count) {
          throw StateError('short cached read for $range');
        }
        yield bytes;
        remaining -= count;
      }
    } finally {
      await input.close();
    }
  }

  @override
  void releaseDemand(Object token) {}

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: true);
    await _writeTail;
    await _sidecarTail;
  }

  void _check() {
    if (_disposed) throw const SparseSourceDisposed();
  }
}
