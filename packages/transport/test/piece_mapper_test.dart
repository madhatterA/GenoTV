import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/piece_mapper.dart';

void main() {
  test('maps and clips a file that starts mid-piece', () {
    final mapper = PieceMapper(
      pieceLength: 16,
      fileOffsetInTorrent: 5,
      fileLength: 35,
    );
    expect(mapper.firstPiece, 0);
    expect(mapper.lastPiece, 2);
    expect(mapper.pieceForFileOffset(0), 0);
    expect(mapper.fileRangeForPiece(0), const ByteRange(0, 10));
    expect(mapper.fileRangeForPiece(2), const ByteRange(27, 34));
    expect(mapper.piecesForFileRange(const ByteRange(12, 15)), <int>[1]);
  });

  test('round-trips 1000 offsets across aligned and unaligned files', () {
    final random = Random(7);
    for (final start in <int>[0, 3, 31]) {
      final mapper = PieceMapper(
        pieceLength: 16,
        fileOffsetInTorrent: start,
        fileLength: 4096,
      );
      for (var index = 0; index < 1000; index++) {
        final offset = random.nextInt(mapper.fileLength);
        expect(
          mapper
              .fileRangeForPiece(mapper.pieceForFileOffset(offset))
              .contains(offset),
          isTrue,
        );
      }
    }
  });

  test('boundary availability requires the first piece', () {
    final mapper = PieceMapper(
      pieceLength: 16,
      fileOffsetInTorrent: 5,
      fileLength: 35,
    );
    expect(mapper.rangesForPieces(<int>[1, 2]).contiguousFrom0, 0);
    expect(mapper.rangesForPieces(<int>[0, 1, 2]).ranges, <ByteRange>[
      const ByteRange(0, 34),
    ]);
  });
}
