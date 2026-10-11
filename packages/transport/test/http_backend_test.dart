import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

import 'support/sparse_source_suite.dart';

void main() {
  group('createHttpBackend platform selection', () {
    for (final platform in TransportPlatform.values) {
      test('returns Aria2FfiBackend on ${platform.name}', () {
        expect(createHttpBackend(platform: platform), isA<Aria2FfiBackend>());
      });
    }
  });

  group('shared sparse-source contract', () {
    // The in-process shim is a real requirement: a missing dylib must fail this
    // suite, never skip it (CLAUDE.md "Skip ban"). Build it with
    // tool/build_libaria2_macos.sh.
    runSparseBackendDownloadSuite('Aria2FfiBackend', () => Aria2FfiBackend());
  });
}
