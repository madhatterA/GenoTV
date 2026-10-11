import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';
import 'dart:io';

void main() {
  test('range parser and piece mapper preserve inclusive boundaries', () {
    expect(parseRange('bytes=-3', 10).range, const ByteRange(7, 9));
    final mapper = PieceMapper(pieceLength: 4, fileOffsetInTorrent: 2, fileLength: 8);
    expect(mapper.pieceForFileOffset(0), 0);
    expect(mapper.fileRangeForPiece(2), const ByteRange(6, 7));
  });

  test('loopback range server serves byte-exact ranges', () async {
    final source = FakeSparseSource(List<int>.generate(10, (index) => index));
    final server = await RangeServer.start();
    try {
      final uri = server.register(source, filename: 'sample.mp4');
      final request = await HttpClient().getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk)), <int>[2, 3, 4, 5]);
    } finally {
      await server.close();
      await source.dispose();
    }
  });

  test('loopback server waits over a hole instead of serving zeros', () async {
    final source = FakeSparseSource(
      List<int>.generate(6, (index) => index + 10),
      available: const <ByteRange>[ByteRange(0, 1), ByteRange(4, 5)],
    );
    final server = await RangeServer.start();
    try {
      final responseFuture = () async {
        final response = await (await HttpClient().getUrl(server.register(source))).close();
        return response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      }();
      await Future<void>.delayed(Duration.zero);
      source.fill(const ByteRange(2, 3));
      expect(await responseFuture, <int>[10, 11, 12, 13, 14, 15]);
    } finally {
      await server.close();
      await source.dispose();
    }
  });

  test('open-ended range streams the available prefix before the rest arrives',
      () async {
    const window = 4 * 1024 * 1024;
    final source = FakeSparseSource(
      List<int>.generate(3 * window, (index) => index % 251),
      available: const <ByteRange>[ByteRange(0, window - 1)],
    );
    final server = await RangeServer.start();
    final client = HttpClient();
    try {
      final request = await client.getUrl(server.register(source));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final response = await request.close();
      var received = 0;
      final done = response.listen((chunk) => received += chunk.length).asFuture<void>();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(received, window, reason: 'first window sent while the rest is missing');
      source.fill(const ByteRange(window, 3 * window - 1));
      await done;
      expect(received, 3 * window);
    } finally {
      client.close(force: true);
      await server.close();
      await source.dispose();
    }
  });
}
