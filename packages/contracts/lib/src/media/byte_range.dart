/// A span of bytes, **inclusive of [endInclusive]** — matching HTTP `Range`
/// semantics (`bytes=0-499` means 500 bytes, byte 499 included). This
/// convention is the single highest-value decision in this file: an
/// off-by-one here becomes a corrupt video stream in Part 03. Do not change
/// it without re-reading every caller.
class ByteRange {
  const ByteRange(this.start, this.endInclusive)
      : assert(endInclusive >= start, 'endInclusive must be >= start');

  final int start;
  final int endInclusive;

  int get length => endInclusive - start + 1;

  bool contains(int offset) => offset >= start && offset <= endInclusive;

  bool overlaps(ByteRange other) =>
      start <= other.endInclusive && other.start <= endInclusive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ByteRange && other.start == start && other.endInclusive == endInclusive);

  @override
  int get hashCode => Object.hash(start, endInclusive);

  @override
  String toString() => 'ByteRange($start-$endInclusive)';
}

/// A gap in a [RangeSet]: bytes not yet known to be available, starting at
/// [start]. [endInclusive] is null when the gap's end isn't known — e.g. past
/// the last range a [RangeSet] has recorded, where nothing has told it where
/// the data stops. Deliberately not a [ByteRange]: a [ByteRange] is always a
/// fully known, finite span of bytes that ARE present; an open-ended gap is
/// neither finite nor present.
///
/// `planning/CONTRACTS.md` §1 originally typed `firstGapFrom` as returning
/// `ByteRange?`; corrected to `Gap?` in this Phase — see decisions.md
/// "firstGapFrom returns Gap, not ByteRange".
class Gap {
  const Gap(this.start, this.endInclusive)
      : assert(endInclusive == null || endInclusive >= start);

  final int start;

  /// Null when the gap's end is not yet known.
  final int? endInclusive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Gap && other.start == start && other.endInclusive == endInclusive);

  @override
  int get hashCode => Object.hash(start, endInclusive);

  @override
  String toString() => 'Gap($start-${endInclusive ?? '?'})';
}

/// Byte availability is ranges, never a percentage — a 40% file with a hole
/// at the current offset is not playable there
/// (`research/technical/HTTP_STREAMING.md`). Immutable: every mutator
/// returns a new [RangeSet]. Ranges are always sorted and coalesced, so
/// adjacent ranges (`[0-9]` + `[10-19]`) merge into one (`[0-19]`), not just
/// overlapping ones — otherwise `containsRange` would report false holes
/// forever.
// ponytail: linear scan, interval tree if range count ever grows past the
// tens of ranges a single media file actually produces.
class RangeSet {
  RangeSet._(this._ranges);

  factory RangeSet.empty() => RangeSet._(const <ByteRange>[]);

  final List<ByteRange> _ranges;

  Iterable<ByteRange> get ranges => List.unmodifiable(_ranges);

  /// Bytes available from byte 0 with no hole. 0 if byte 0 itself is
  /// missing, even if bytes 1..1e9 are present.
  int get contiguousFrom0 {
    if (_ranges.isEmpty) return 0;
    final first = _ranges.first;
    return first.start == 0 ? first.length : 0;
  }

  /// True only if [r] is fully covered by a single recorded range — ranges
  /// are coalesced, so a range spanning two recorded ranges would have to
  /// cross a real gap between them.
  bool containsRange(ByteRange r) {
    for (final existing in _ranges) {
      if (existing.start <= r.start && r.endInclusive <= existing.endInclusive) {
        return true;
      }
    }
    return false;
  }

  /// The first gap at or after [offset]. Always returns something — an empty
  /// [RangeSet] has no data anywhere, so `firstGapFrom(offset)` is the
  /// open-ended `Gap(offset, null)`. See [Gap] for why an open end is
  /// represented explicitly rather than a sentinel like `-1`.
  Gap firstGapFrom(int offset) {
    var cursor = offset;
    for (final range in _ranges) {
      if (range.endInclusive < cursor) continue;
      if (range.start <= cursor) {
        cursor = range.endInclusive + 1;
        continue;
      }
      return Gap(cursor, range.start - 1);
    }
    return Gap(cursor, null);
  }

  /// Returns a new [RangeSet] with [range] merged in; ranges overlapping or
  /// directly adjacent to it are coalesced into one.
  RangeSet add(ByteRange range) {
    final merged = <ByteRange>[];
    var start = range.start;
    var end = range.endInclusive;
    var i = 0;
    final n = _ranges.length;

    while (i < n && _ranges[i].endInclusive < start - 1) {
      merged.add(_ranges[i]);
      i++;
    }
    while (i < n && _ranges[i].start <= end + 1) {
      if (_ranges[i].start < start) start = _ranges[i].start;
      if (_ranges[i].endInclusive > end) end = _ranges[i].endInclusive;
      i++;
    }
    merged.add(ByteRange(start, end));
    while (i < n) {
      merged.add(_ranges[i]);
      i++;
    }
    return RangeSet._(merged);
  }
}
