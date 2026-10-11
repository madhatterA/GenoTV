import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ByteRange', () {
    test('length is inclusive of endInclusive', () {
      expect(const ByteRange(0, 499).length, 500);
    });

    test('a one-byte range has length 1', () {
      expect(const ByteRange(10, 10).length, 1);
    });

    test('asserts endInclusive >= start', () {
      expect(() => ByteRange(10, 9), throwsA(isA<AssertionError>()));
    });

    test('contains is inclusive at both ends', () {
      const range = ByteRange(10, 20);
      expect(range.contains(10), isTrue);
      expect(range.contains(20), isTrue);
      expect(range.contains(21), isFalse);
      expect(range.contains(9), isFalse);
    });
  });

  group('RangeSet.add', () {
    test('disjoint ranges do not merge', () {
      final set = RangeSet.empty().add(const ByteRange(0, 9)).add(const ByteRange(20, 29));
      expect(set.ranges, [const ByteRange(0, 9), const ByteRange(20, 29)]);
    });

    test('adjacent ranges merge', () {
      final set = RangeSet.empty().add(const ByteRange(0, 9)).add(const ByteRange(10, 19));
      expect(set.ranges, [const ByteRange(0, 19)]);
    });

    test('overlapping ranges merge', () {
      final set = RangeSet.empty().add(const ByteRange(0, 15)).add(const ByteRange(10, 19));
      expect(set.ranges, [const ByteRange(0, 19)]);
    });

    test('a range bridging two existing ranges merges all three', () {
      final set = RangeSet.empty()
          .add(const ByteRange(0, 9))
          .add(const ByteRange(20, 29))
          .add(const ByteRange(10, 19));
      expect(set.ranges, [const ByteRange(0, 29)]);
    });

    test('is immutable: adding to a set does not change the original', () {
      final original = RangeSet.empty().add(const ByteRange(0, 9));
      final extended = original.add(const ByteRange(10, 19));

      expect(original.ranges, [const ByteRange(0, 9)]);
      expect(extended.ranges, [const ByteRange(0, 19)]);
    });

    test('a range ending at the last byte of the file is kept exactly', () {
      const lastByte = 999;
      final set = RangeSet.empty().add(const ByteRange(900, lastByte));
      expect(set.ranges, [const ByteRange(900, lastByte)]);
    });
  });

  group('RangeSet.containsRange', () {
    test('true when fully covered', () {
      final set = RangeSet.empty().add(const ByteRange(0, 99));
      expect(set.containsRange(const ByteRange(10, 20)), isTrue);
    });

    test('false when a single byte in the middle is missing', () {
      final set = RangeSet.empty().add(const ByteRange(0, 49)).add(const ByteRange(51, 99));
      expect(set.containsRange(const ByteRange(0, 99)), isFalse);
    });
  });

  group('RangeSet.firstGapFrom', () {
    test('an empty set answers with an open-ended gap starting at offset', () {
      final gap = RangeSet.empty().firstGapFrom(0);
      expect(gap.start, 0);
      expect(gap.endInclusive, isNull);
    });

    test('finds a hole that starts exactly at offset', () {
      final set = RangeSet.empty().add(const ByteRange(0, 49)).add(const ByteRange(100, 149));
      final gap = set.firstGapFrom(50);
      expect(gap, const Gap(50, 99));
    });

    test('finds a hole that starts later than offset', () {
      final set = RangeSet.empty().add(const ByteRange(0, 49)).add(const ByteRange(100, 149));
      final gap = set.firstGapFrom(10);
      expect(gap, const Gap(50, 99));
    });

    test('past the last known range, the gap is open-ended', () {
      final set = RangeSet.empty().add(const ByteRange(0, 49));
      final gap = set.firstGapFrom(0);
      expect(gap.start, 50);
      expect(gap.endInclusive, isNull);
    });
  });

  group('RangeSet.contiguousFrom0', () {
    test('is the length of the leading range when it starts at 0', () {
      final set = RangeSet.empty().add(const ByteRange(0, 99));
      expect(set.contiguousFrom0, 100);
    });

    test('is 0 when byte 0 is missing even if huge later ranges are present', () {
      final set = RangeSet.empty().add(const ByteRange(1, 1000000000));
      expect(set.contiguousFrom0, 0);
    });
  });
}
