import 'package:contracts/contracts.dart';

/// Maps file-relative offsets to torrent pieces, including partial boundaries.
class PieceMapper {
  PieceMapper({
    required this.pieceLength,
    required this.fileOffsetInTorrent,
    required this.fileLength,
  }) : assert(pieceLength > 0),
       assert(fileOffsetInTorrent >= 0),
       assert(fileLength > 0);

  final int pieceLength;
  final int fileOffsetInTorrent;
  final int fileLength;

  int get firstPiece => fileOffsetInTorrent ~/ pieceLength;
  int get lastPiece => (fileOffsetInTorrent + fileLength - 1) ~/ pieceLength;

  int pieceForFileOffset(int offset) {
    if (offset < 0 || offset >= fileLength) {
      throw RangeError('file offset: $offset');
    }
    return (fileOffsetInTorrent + offset) ~/ pieceLength;
  }

  ByteRange fileRangeForPiece(int piece) {
    if (piece < firstPiece || piece > lastPiece) {
      throw RangeError('piece: $piece');
    }
    final torrentStart = piece * pieceLength;
    final start = torrentStart < fileOffsetInTorrent
        ? 0
        : torrentStart - fileOffsetInTorrent;
    final end =
        ((torrentStart + pieceLength).clamp(
              fileOffsetInTorrent,
              fileOffsetInTorrent + fileLength,
            ) -
            fileOffsetInTorrent) -
        1;
    return ByteRange(start, end);
  }

  Iterable<int> piecesForFileRange(ByteRange range) sync* {
    if (range.start < 0 || range.endInclusive >= fileLength) {
      throw RangeError(range);
    }
    for (
      var piece = pieceForFileOffset(range.start);
      piece <= pieceForFileOffset(range.endInclusive);
      piece++
    ) {
      yield piece;
    }
  }

  RangeSet rangesForPieces(Iterable<int> pieces) {
    var result = RangeSet.empty();
    for (final piece in pieces) {
      if (piece >= firstPiece && piece <= lastPiece) {
        result = result.add(fileRangeForPiece(piece));
      }
    }
    return result;
  }
}
