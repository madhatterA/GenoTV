import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/http/aria2_window.dart';

void main() {
  test('merged availability never recopies punched staging segments', () async {
    const block = 64 * 1024;
    final directory = await Directory.systemTemp.createTemp('aria2-copy-test-');
    final window = await Aria2Window.open(
      SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://127.0.0.1/media'),
      ),
      const ByteRange(0, 4 * block - 1),
      4 * block,
      directory,
    );
    final destination = File('${directory.path}/media.partial');
    final expected = Uint8List.fromList([
      for (var segment = 1; segment <= 4; segment++)
        ...List<int>.filled(block, segment),
    ]);
    try {
      await window.file.writeAsBytes(expected);
      await window.copyAvailable(
        RangeSet.empty()
            .add(const ByteRange(0, block - 1))
            .add(const ByteRange(2 * block, 3 * block - 1)),
        destination,
        releaseCopied: true,
      );
      await window.copyAvailable(
        RangeSet.empty().add(const ByteRange(0, 4 * block - 1)),
        destination,
        releaseCopied: true,
      );
      expect(await destination.readAsBytes(), expected);
    } finally {
      await window.close();
      await directory.delete(recursive: true);
    }
  });
}
