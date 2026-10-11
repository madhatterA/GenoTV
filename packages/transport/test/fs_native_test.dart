import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  test(
    'punchHole frees blocks without changing size; free/allocated report',
    () async {
      final dir = await Directory.systemTemp.createTemp('fs-native-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.bin');
      await file.writeAsBytes(
        Uint8List(8 * 1024 * 1024)..fillRange(0, 8 << 20, 7),
      );
      final fs = FsNative();
      expect(fs.allocatedBytes(file.path), 8 * 1024 * 1024);
      // Unaligned request: rounded inward, so only whole blocks are freed.
      fs.punchHole(file.path, 1024 * 1024 + 100, 4 * 1024 * 1024);
      expect(await file.length(), 8 * 1024 * 1024);
      expect(
        fs.allocatedBytes(
          file.path,
          offset: 1024 * 1024 + 4096,
          length: 4 * 1024 * 1024 - 8192,
        ),
        0,
      );
      expect(
        fs.allocatedBytes(file.path),
        lessThanOrEqualTo(4 * 1024 * 1024 + 8192),
      );
      expect(
        fs.allocatedBytes(file.path, offset: 6 * 1024 * 1024),
        2 * 1024 * 1024,
      );
      expect(fs.freeBytes(dir.path), greaterThan(0));
      expect(
        () => fs.punchHole('${dir.path}/missing', 0, 4096),
        throwsA(isA<FsNativeException>()),
      );
      // The surviving bytes are intact, the punched range reads as zeros.
      final bytes = await file.readAsBytes();
      expect(bytes[0], 7);
      expect(bytes[2 * 1024 * 1024], 0);
    },
  );
}
