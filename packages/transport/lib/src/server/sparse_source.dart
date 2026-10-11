import 'package:contracts/contracts.dart';

/// Thrown by [SparseSource.waitFor] when the source is disposed while waiting.
class SparseSourceDisposed implements Exception {
  const SparseSourceDisposed();
  @override
  String toString() => 'SparseSourceDisposed: source disposed while waiting';
}

/// Internal byte source consumed by [RangeServer].
abstract interface class SparseSource {
  int? get totalBytes;
  RangeSet get available;

  /// Completes when [range] is available; throws [SparseSourceDisposed] if the
  /// source is disposed first.
  Future<void> waitFor(ByteRange range);
  Stream<List<int>> read(ByteRange range);
  void releaseDemand(Object token);
}
