import 'dart:async';

import 'package:contracts/contracts.dart';

import 'sparse_source.dart';

/// Deterministic sparse source used by transport tests and diagnostics.
class FakeSparseSource implements SparseSource {
  FakeSparseSource(this._bytes, {Iterable<ByteRange>? available})
    : _available = (available ?? <ByteRange>[ByteRange(0, _bytes.length - 1)])
          .fold(RangeSet.empty(), (set, range) => set.add(range));

  final List<int> _bytes;
  RangeSet _available;
  final List<ByteRange> released = <ByteRange>[];
  final List<Object> demandTokens = <Object>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  int get totalBytes => _bytes.length;
  @override
  RangeSet get available => _available;

  void fill(ByteRange range) {
    _available = _available.add(range);
    _changes.add(null);
  }

  @override
  Future<void> waitFor(ByteRange range) async {
    while (!_available.containsRange(range)) {
      if (_disposed) throw const SparseSourceDisposed();
      try {
        await _changes.stream.first;
      } on StateError {
        // dispose() closed the change stream while this waiter was parked.
        throw const SparseSourceDisposed();
      }
    }
  }

  @override
  Stream<List<int>> read(ByteRange range) async* {
    if (!_available.containsRange(range)) {
      throw StateError('range is not available: $range');
    }
    const chunk = 256 * 1024;
    for (var offset = range.start; offset <= range.endInclusive;) {
      final end = (offset + chunk - 1).clamp(offset, range.endInclusive);
      yield List<int>.unmodifiable(_bytes.sublist(offset, end + 1));
      offset = end + 1;
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void releaseDemand(Object token) {
    demandTokens.remove(token);
    released.add(ByteRange(0, 0));
  }

  bool _disposed = false;

  Future<void> dispose() {
    _disposed = true;
    return _changes.close();
  }
}
