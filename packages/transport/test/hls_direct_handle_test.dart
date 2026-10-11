import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  test('HLS opens the original URL without a download backend', () async {
    final dir = await Directory.systemTemp.createTemp('hls-test');
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: dir);
    final spec = SourceSpec(
      kind: SourceKind.hlsUrl,
      uri: Uri.parse('https://s.example/a/playlist.m3u8'),
      headers: {'User-Agent': 'Mozilla/5.0'},
    );
    try {
      final first = await source.open(spec);
      final second = await source.open(spec);
      expect(first.playbackUri, spec.uri);
      expect(second.playbackUri, spec.uri);
      expect(first.totalBytes, isNull);
      expect((await first.status.first).state, SourceState.ready);
      await first.dispose();
      expect(second.playbackUri, spec.uri);
      await second.dispose();
      await second.dispose();
    } finally {
      await source.dispose();
      await dir.delete(recursive: true);
    }
  });
}
