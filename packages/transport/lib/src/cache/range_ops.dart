import 'package:contracts/contracts.dart';

/// Bytes covered by [set].
int rangesLength(RangeSet set) =>
    set.ranges.fold(0, (sum, range) => sum + range.length);

/// [set] without the bytes of [cut].
RangeSet subtractRange(RangeSet set, ByteRange cut) {
  var result = RangeSet.empty();
  for (final range in set.ranges) {
    if (range.endInclusive < cut.start || range.start > cut.endInclusive) {
      result = result.add(range);
      continue;
    }
    if (range.start < cut.start) {
      result = result.add(ByteRange(range.start, cut.start - 1));
    }
    if (range.endInclusive > cut.endInclusive) {
      result = result.add(ByteRange(cut.endInclusive + 1, range.endInclusive));
    }
  }
  return result;
}

/// The parts of [set] that lie inside [window].
RangeSet intersectRange(RangeSet set, ByteRange window) {
  var result = RangeSet.empty();
  for (final range in set.ranges) {
    final start = range.start > window.start ? range.start : window.start;
    final end = range.endInclusive < window.endInclusive
        ? range.endInclusive
        : window.endInclusive;
    if (start <= end) result = result.add(ByteRange(start, end));
  }
  return result;
}
