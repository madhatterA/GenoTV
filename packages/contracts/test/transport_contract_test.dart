import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SourceStatus', () {
    test('accepts a null totalBytes', () {
      final status = SourceStatus(
        state: SourceState.resolving,
        available: RangeSet.empty(),
        totalBytes: null,
        bytesPerSecond: 0,
        peersOrConnections: 0,
      );
      expect(status.totalBytes, isNull);
    });

    test('state == failed requires a non-null failure', () {
      expect(
        () => SourceStatus(
          state: SourceState.failed,
          available: RangeSet.empty(),
          totalBytes: null,
          bytesPerSecond: 0,
          peersOrConnections: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a non-failed state cannot carry a failure', () {
      expect(
        () => SourceStatus(
          state: SourceState.ready,
          available: RangeSet.empty(),
          totalBytes: 100,
          bytesPerSecond: 0,
          peersOrConnections: 0,
          failure: const TransportFailure.httpUnreachable(cause: 'unreachable'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('stalled carries its typed failure', () {
      final failure = const TransportFailure.torrentStalled();
      final status = SourceStatus(
        state: SourceState.stalled,
        available: RangeSet.empty(),
        totalBytes: 100,
        bytesPerSecond: 0,
        peersOrConnections: 1,
        failure: failure,
      );
      expect(status.failure, same(failure));
    });
  });

  group('TransportFailure', () {
    test('every leaf has a unique code', () {
      final codes = <String>{
        const TransportFailure.httpNoRangeSupport(cause: 'x').code,
        const TransportFailure.httpValidatorChanged().code,
        const TransportFailure.httpUnreachable(cause: 'x').code,
        const TransportFailure.rangeUnsatisfiable().code,
        const TransportFailure.torrentNoMetadata().code,
        const TransportFailure.torrentNoPeers().code,
        const TransportFailure.torrentStalled().code,
        const TransportFailure.torrentFileError(cause: 'x').code,
        const TransportFailure.torrentFileNotFound().code,
        const TransportFailure.engineUnavailable(cause: 'x').code,
      };
      expect(codes, hasLength(10));
    });
  });

  test('TransportOptions equality covers every field and defaults are Auto', () {
    const a = TransportOptions();
    expect(a, const TransportOptions());
    expect(a.verifyTls && a.dht && a.pex, isTrue);
    expect(a.seeding, SeedingMode.off);
    expect(
      const TransportOptions(headers: {'A': 'b'}),
      const TransportOptions(headers: {'A': 'b'}),
    );
    expect(const TransportOptions(headers: {'A': 'b'}), isNot(a));
    expect(const TransportOptions(trackers: ['t']), isNot(a));
    expect(const TransportOptions(proxy: 'http://p'), isNot(a));
  });
}
