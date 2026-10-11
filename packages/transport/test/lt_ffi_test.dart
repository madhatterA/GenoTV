import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  final path = Platform.environment['TRANSPORT_LT_SHIM_DYLIB'] ??
      '${Directory.current.path}/macos/libs/libtransport_lt_shim.dylib';
  test('real libtorrent C ABI session creates and destroys', () {
    if (!File(path).existsSync()) {
      fail('required native artifact is missing: $path — build it per '
          'packages/transport/tool/LT_BUILD.md');
    }
    final session = LtFfiSession(library: DynamicLibrary.open(path));
    expect(session.error, isEmpty);
    session.dispose();
    session.dispose();
  });

  test('native session rejects malformed magnets and tears down repeatedly', () {
    if (!File(path).existsSync()) {
      fail('required native artifact is missing: $path — build it per '
          'packages/transport/tool/LT_BUILD.md');
    }
    final session = LtFfiSession(library: DynamicLibrary.open(path));
    expect(() => session.addMagnet('not-a-magnet', savePath: Directory.systemTemp.path), throwsA(isA<Exception>()));
    session.dispose();
    for (var i = 0; i < 20; i++) {
      final cycle = LtFfiSession(library: DynamicLibrary.open(path));
      cycle.dispose();
    }
  });
}
