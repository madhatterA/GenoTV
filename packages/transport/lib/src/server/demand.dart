import 'package:contracts/contracts.dart';

/// Ref-counted demand ranges. Overlapping requests share one source demand.
class DemandRegistry {
  final Map<Object, ByteRange> _tokens = <Object, ByteRange>{};
  final Map<Object, ByteRange> _bucketByToken = <Object, ByteRange>{};
  final Map<ByteRange, int> _counts = <ByteRange, int>{};

  Object register(ByteRange range) {
    final token = Object();
    _tokens[token] = range;
    final existing = _counts.keys.cast<ByteRange?>().firstWhere(
      (r) => r != null && r.overlaps(range),
      orElse: () => null,
    );
    if (existing != null) {
      _counts[existing] = (_counts[existing] ?? 0) + 1;
      _bucketByToken[token] = existing;
    } else {
      _counts[range] = 1;
      _bucketByToken[token] = range;
    }
    return token;
  }

  void release(Object token) {
    final range = _tokens.remove(token);
    if (range == null) return;
    // The registry stores the canonical range selected at registration time.
    // A later overlapping registration must not make release decrement the
    // wrong bucket when several overlaps are active.
    final key = _bucketByToken.remove(token) ?? range;
    final count = (_counts[key] ?? 1) - 1;
    if (count <= 0) {
      _counts.remove(key);
    } else {
      _counts[key] = count;
    }
  }

  int get activeCount => _tokens.length;
  Iterable<ByteRange> get activeRanges => List.unmodifiable(_counts.keys);
}
