import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  test('all nine TransportFailure codes are constructible and stable', () {
    final failures = <TransportFailure>[
      const TransportFailure.httpNoRangeSupport(cause: 'test'),
      const TransportFailure.httpValidatorChanged(cause: 'test'),
      const TransportFailure.httpUnreachable(cause: 'test'),
      const TransportFailure.rangeUnsatisfiable(cause: 'test'),
      const TransportFailure.torrentNoMetadata(cause: 'test'),
      const TransportFailure.torrentNoPeers(cause: 'test'),
      const TransportFailure.torrentStalled(cause: 'test'),
      const TransportFailure.torrentFileNotFound(cause: 'test'),
      const TransportFailure.engineUnavailable(cause: 'test'),
    ];
    expect(failures.map((failure) => failure.code).toSet(), hasLength(9));
  });

  test(
    'unreachable HTTP probes and missing engines surface typed failures',
    () async {
      await expectLater(
        RangeSupportProbe().probe(
          SourceSpec(
            kind: SourceKind.httpUrl,
            uri: Uri.parse('http://127.0.0.1:1/missing'),
          ),
        ),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.code,
            'code',
            'transport.http.unreachable',
          ),
        ),
      );
      // DynamicLibrary.process() has no aria2 shim symbols: the engine is missing.
      final backend = Aria2FfiBackend(library: DynamicLibrary.process());
      await expectLater(
        backend.start(),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.code,
            'code',
            'transport.engine.unavailable',
          ),
        ),
      );
    },
  );

  test('validator changes are rejected at the transport boundary', () {
    expect(
      () => validateHttpValidator('old', 'new'),
      throwsA(isA<TransportFailure>()),
    );
  });
}
