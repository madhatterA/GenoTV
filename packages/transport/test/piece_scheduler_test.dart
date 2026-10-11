import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/piece_mapper.dart';
import 'package:transport/src/torrent/piece_scheduler.dart';

void main() {
  test('critical deadlines increase and look-ahead stays high priority', () {
    final scheduler = PieceScheduler();
    final mapper = PieceMapper(
      pieceLength: 1024 * 1024,
      fileOffsetInTorrent: 0,
      fileLength: 64 * 1024 * 1024,
    );
    final schedule = scheduler.plan(
      playHead: 0,
      mapper: mapper,
      available: RangeSet.empty(),
    );
    expect(
      schedule.operations.take(5).map((op) => op.priority),
      everyElement(7),
    );
    expect(
      schedule.operations.skip(5).map((op) => op.priority),
      everyElement(6),
    );
    final deadlines = schedule.operations
        .take(5)
        .map((op) => op.deadlineMs!)
        .toList();
    expect(deadlines, orderedEquals(<int>[1000, 2000, 3000, 4000, 5000]));
  });

  test('advancing reuses overlap; seeking clears, demotes, then raises', () {
    final scheduler = PieceScheduler();
    final mapper = PieceMapper(
      pieceLength: 1024 * 1024,
      fileOffsetInTorrent: 0,
      fileLength: 100 * 1024 * 1024,
    );
    scheduler.plan(playHead: 0, mapper: mapper, available: RangeSet.empty());
    final next = scheduler.plan(
      playHead: 1024 * 1024,
      mapper: mapper,
      available: RangeSet.empty(),
    );
    expect(next.clearDeadlines, isFalse);
    expect(next.demotePieces, <int>[0]);
    expect(next.operations, hasLength(1));

    final seek = scheduler.plan(
      playHead: 80 * 1024 * 1024,
      mapper: mapper,
      available: RangeSet.empty(),
    );
    final calls = <String>[];
    seek.apply(
      clear: () => calls.add('clear'),
      prioritize: (piece, priority) => calls.add('priority:$piece:$priority'),
      deadline: (piece, milliseconds) =>
          calls.add('deadline:$piece:$milliseconds'),
    );
    expect(seek.clearDeadlines, isTrue);
    expect(calls.first, 'clear');
    final firstRaised = calls.indexWhere((call) => call.endsWith(':7'));
    expect(calls.sublist(1, firstRaised), everyElement(endsWith(':4')));
  });

  test('large pieces produce a smaller critical window', () {
    int critical(int pieceLength) => PieceScheduler()
        .plan(
          playHead: 0,
          mapper: PieceMapper(
            pieceLength: pieceLength,
            fileOffsetInTorrent: 0,
            fileLength: 64 * 1024 * 1024,
          ),
          available: RangeSet.empty(),
        )
        .operations
        .where((operation) => operation.deadlineMs != null)
        .length;
    expect(critical(16 * 1024 * 1024), 1);
    expect(critical(1024 * 1024), 5);
  });

  test('a very low observed download rate cannot produce an out-of-Int32 deadline', () {
    // 8 KiB pieces + the 5 MiB critical window is the burst fixture's shape: 640
    // critical pieces, so the unclamped deadline for the furthest critical piece
    // is 640 * 8192 * 1000 / rate. At rate = 1 that is 5.24e9 ms, which truncates
    // to a negative Int32 in the FFI call and is rejected by the native guard.
    final scheduler = PieceScheduler();
    final schedule = scheduler.plan(
      playHead: 0,
      mapper: PieceMapper(
        pieceLength: 8 * 1024,
        fileOffsetInTorrent: 0,
        fileLength: 64 * 1024 * 1024,
      ),
      available: RangeSet.empty(),
      bitrateBytesPerSecond: 1,
    );
    final deadlines = schedule.operations
        .map((o) => o.deadlineMs)
        .whereType<int>()
        .toList(growable: false);
    expect(deadlines, isNotEmpty, reason: 'the critical window must produce deadline operations');
    for (final ms in deadlines) {
      expect(ms, greaterThanOrEqualTo(0));
      expect(ms, lessThanOrEqualTo(maxPieceDeadlineMs));
      expect(ms, lessThan(2147483647), reason: 'must fit the Int32 FFI parameter');
    }
  });
}
