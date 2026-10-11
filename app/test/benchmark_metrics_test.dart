import 'package:flutter_test/flutter_test.dart';

import '../tool/bench_metrics.dart';

void main() {
  test('benchmark clock is monotonic for ordered checkpoints', () {
    final clock = BenchmarkClock();
    final start = clock.milliseconds;
    final end = clock.milliseconds;
    expect(end, greaterThanOrEqualTo(start));
    BenchmarkBoundary.requireOrdered(
      name: 'sample',
      startMs: start,
      endMs: end,
    );
  });

  test('benchmark boundary rejects reversed checkpoints', () {
    expect(
      () => BenchmarkBoundary.requireOrdered(
        name: 'reversed',
        startMs: 20,
        endMs: 10,
      ),
      throwsStateError,
    );
  });
}
