import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

typedef StreamRangeReader = Future<List<int>> Function(Uri uri, ByteRange range);

/// Reusable behavioural spec for any [StreamSource] implementation, fake or
/// real. Every assertion cites the `planning/CONTRACTS.md` §2 invariant (or
/// its `StreamHandle` doc comment) it enforces.
///
/// [spec] lets a real implementation (Part 03) point this suite at a valid
/// fixture; the default URI is only suitable for deterministic fakes.
void runStreamSourceContractTests(
  StreamSource Function() create, {
  SourceSpec Function()? spec,
  StreamRangeReader? readRange,
  SourceSpec Function()? unreachableSpec,
}) {
  final buildSpec = spec ??
      (() => SourceSpec(kind: SourceKind.httpUrl, uri: Uri.parse('http://127.0.0.1:0/fixture')));

  group('StreamSource contract', () {
    test('open() twice for the same spec yields handles that do not fight (§2.1 demand dedup)',
        () async {
      final source = create();
      final s = buildSpec();
      final a = await source.open(s);
      final b = await source.open(s);
      expect(a.playbackUri, b.playbackUri);
      await a.dispose();
    });

    test('clearCache() frees closed data and leaves an open stream alone',
        () async {
      final source = create();
      final handle = await source.open(buildSpec());
      final uri = handle.playbackUri;
      expect(await source.clearCache(), greaterThanOrEqualTo(0));
      expect(handle.playbackUri, uri);
      await handle.dispose();
    });

    test('status replays the latest value to a late subscriber (§2 doc comment)', () async {
      final source = create();
      final handle = await source.open(buildSpec());
      final first = await handle.status.first;

      SourceStatus? late;
      final sub = handle.status.listen((s) => late = s);
      await Future<void>.delayed(Duration.zero);

      expect(late, isNotNull);
      expect(late, first);
      await sub.cancel();
      await handle.dispose();
    });

    test('state == failed always carries a failure (SourceStatus constructor invariant)',
        () async {
      final source = create();
      final handle = await source.open(buildSpec());
      final statuses = <SourceStatus>[];
      final sub = handle.status.listen(statuses.add);
      await Future<void>.delayed(Duration.zero);

      for (final status in statuses) {
        expect(status.state != SourceState.failed || status.failure != null, isTrue);
      }
      await sub.cancel();
      await handle.dispose();
    });

    test('dispose() is idempotent and stops all status emissions (§2 invariant 4)', () async {
      final source = create();
      final handle = await source.open(buildSpec());
      await handle.dispose();
      await handle.dispose(); // idempotent — must not throw

      final events = <SourceStatus>[];
      final sub = handle.status.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('after dispose(), playbackUri use is an error, not a silent no-op (§2 invariant 4)',
        () async {
      final source = create();
      final handle = await source.open(buildSpec());
      await handle.dispose();
      expect(() => handle.playbackUri, throwsA(anything));
    });

    test('seekHint never throws for an offset beyond totalBytes (§2 doc comment)', () async {
      final source = create();
      final handle = await source.open(buildSpec());
      await handle.seekHint(1 << 40); // absurdly large — beyond any real totalBytes
      await handle.dispose();
    });

    if (readRange != null) {
      test('a live range request delivers exact bytes (§2 invariant 5)', () async {
        final source = create();
        final handle = await source.open(buildSpec());
        final bytes = await readRange(handle.playbackUri, const ByteRange(0, 3));
        expect(bytes, hasLength(4));
        await handle.dispose();
      });
    }

    if (unreachableSpec != null) {
      test('an unreachable source reaches failed with a typed failure (§2 invariant 5)', () async {
        final source = create();
        final handle = await source.open(unreachableSpec());
        final status = await handle.status
            .firstWhere((value) => value.state == SourceState.failed)
            .timeout(const Duration(seconds: 10));
        expect(status.failure, isA<TransportFailure>());
        await handle.dispose();
      });
    }
  });
}
