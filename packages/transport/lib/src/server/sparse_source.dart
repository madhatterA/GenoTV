import 'package:contracts/contracts.dart';

/// Thrown by [SparseSource.waitFor] when the source is disposed while waiting.
class SparseSourceDisposed implements Exception {
  const SparseSourceDisposed();
  @override
  String toString() => 'SparseSourceDisposed: source disposed while waiting';
}

/// A read that belongs to a position the player has already left (a far seek
/// moved on). Ends that connection at once so the player can run its seek.
class SparseSourceSuperseded extends SparseSourceDisposed {
  const SparseSourceSuperseded();
  @override
  String toString() => 'SparseSourceSuperseded: read left behind by a seek';
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
