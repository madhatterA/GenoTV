import 'package:contracts/contracts.dart';

/// Converts aria2's most portable availability representation (piece bitfield)
/// into exact byte ranges. Bit zero is the first piece.
RangeSet rangesFromBitfield(
  String bitfield, {
  required int pieceLength,
  required int totalBytes,
}) {
  var result = RangeSet.empty();
  for (var piece = 0; piece < bitfield.length * 4; piece++) {
    final byte = piece ~/ 4;
    final bit = 3 - (piece % 4);
    if ((int.parse(bitfield[byte], radix: 16) & (1 << bit)) == 0) continue;
    final start = piece * pieceLength;
    if (start >= totalBytes) break;
    final end = (start + pieceLength - 1).clamp(start, totalBytes - 1);
    result = result.add(ByteRange(start, end));
  }
  return result;
}

RangeSet rangesFromPieceFlags(
  Iterable<bool> pieces, {
  required int pieceLength,
  required int totalBytes,
}) {
  var result = RangeSet.empty();
  var piece = 0;
  for (final have in pieces) {
    if (have) {
      final start = piece * pieceLength;
      if (start < totalBytes) {
        result = result.add(
          ByteRange(
            start,
            (start + pieceLength - 1).clamp(start, totalBytes - 1),
          ),
        );
      }
    }
    piece++;
  }
  return result;
}
