import 'dart:math' as math;

import 'package:contracts/contracts.dart';

import 'piece_mapper.dart';

const int criticalWindowBytes = 5 * 1024 * 1024;
const int lookAheadWindowBytes = 30 * 1024 * 1024;

/// Upper bound for a piece deadline. Deadlines are a scheduling hint, and the
/// native FFI parameter is Int32 -- an unclamped value computed from a very low
/// observed download rate overflows it and is rejected by the shim's `ms < 0`
/// guard (see bug_history.md). Two minutes is far beyond any useful ordering
/// horizon for playback and is safely inside Int32.
const int maxPieceDeadlineMs = 120 * 1000;

class PieceOperation {
  const PieceOperation({
    required this.piece,
    required this.priority,
    this.deadlineMs,
  });
  final int piece;
  final int priority;
  final int? deadlineMs;
}

class PieceSchedule {
  const PieceSchedule({
    required this.clearDeadlines,
    required this.demotePieces,
    required this.operations,
  });

  final bool clearDeadlines;
  final List<int> demotePieces;
  final List<PieceOperation> operations;

  void apply({
    required void Function() clear,
    required void Function(int piece, int priority) prioritize,
    required void Function(int piece, int deadlineMs) deadline,
  }) {
    if (clearDeadlines) clear();
    for (final piece in demotePieces) {
      prioritize(piece, 4);
    }
    for (final operation in operations) {
      prioritize(operation.piece, operation.priority);
      final milliseconds = operation.deadlineMs;
      if (milliseconds != null) deadline(operation.piece, milliseconds);
    }
  }
}

/// Pure deadline policy. Deadlines schedule work; they are not completion guarantees.
class PieceScheduler {
  final Map<int, PieceOperation> _active = <int, PieceOperation>{};
  int? _currentPiece;

  PieceSchedule plan({
    required int playHead,
    required PieceMapper mapper,
    required RangeSet available,
    int? bitrateBytesPerSecond,
    int? maxLookAheadBytes,
  }) {
    final current = mapper.pieceForFileOffset(
      playHead.clamp(0, mapper.fileLength - 1),
    );
    final criticalPieces = (criticalWindowBytes / mapper.pieceLength).ceil();
    // The cache limit may leave less room ahead than the default window.
    final lookAheadBytes = maxLookAheadBytes == null
        ? lookAheadWindowBytes
        : math.min(lookAheadWindowBytes, maxLookAheadBytes);
    final lookAheadPieces = math.max(
      1,
      (lookAheadBytes / mapper.pieceLength).ceil(),
    );
    final rate = bitrateBytesPerSecond == null || bitrateBytesPerSecond <= 0
        ? 1 * 1024 * 1024
        : bitrateBytesPerSecond;
    final desired = <int, PieceOperation>{};
    final windowEnd = (current + lookAheadPieces - 1).clamp(
      current,
      mapper.lastPiece,
    );
    for (var piece = current; piece <= windowEnd; piece++) {
      final range = mapper.fileRangeForPiece(piece);
      if (available.containsRange(range)) continue;
      final ahead = piece - current;
      if (ahead < criticalPieces) {
        desired[piece] = PieceOperation(
          piece: piece,
          priority: 7,
          deadlineMs: ((ahead + 1) * mapper.pieceLength * 1000 / rate)
              .round()
              .clamp(0, maxPieceDeadlineMs),
        );
      } else {
        desired[piece] = PieceOperation(piece: piece, priority: 6);
      }
    }
    final clearDeadlines =
        _currentPiece != null && (current - _currentPiece!).abs() > 1;
    final demote = _active.keys
        .where((piece) => !desired.containsKey(piece))
        .toList(growable: false);
    final operations = desired.entries
        .where((entry) => !_active.containsKey(entry.key))
        .map((entry) => entry.value)
        .toList(growable: false);
    _active
      ..clear()
      ..addAll(desired);
    _currentPiece = current;
    return PieceSchedule(
      clearDeadlines: clearDeadlines,
      demotePieces: demote,
      operations: operations,
    );
  }
}
