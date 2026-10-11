import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:persistence/src/write_queue.dart';

void main() {
  group('WriteQueue', () {
    test('100 writes to one key within the window produce one row write, with the last value',
        () async {
      final flushed = <MapEntry<String, int>>[];
      final queue = WriteQueue<String, int>(
        flushOne: (key, value) async => flushed.add(MapEntry(key, value)),
        logger: MemoryLogger(),
        window: const Duration(milliseconds: 200),
      );

      for (var i = 0; i < 100; i++) {
        queue.write('a', i);
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(flushed, hasLength(1));
      expect(flushed.single.value, 99);
      await queue.dispose();
    });

    test('writes to different keys are not coalesced together', () async {
      final flushed = <String>[];
      final queue = WriteQueue<String, int>(
        flushOne: (key, value) async => flushed.add(key),
        logger: MemoryLogger(),
        window: const Duration(milliseconds: 200),
      );

      queue.write('a', 1);
      queue.write('b', 2);

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(flushed, containsAll(<String>['a', 'b']));
      expect(flushed, hasLength(2));
      await queue.dispose();
    });

    test('a read after a queued write returns the queued value (read-through)', () {
      final queue = WriteQueue<String, int>(
        flushOne: (key, value) async {},
        logger: MemoryLogger(),
        window: const Duration(seconds: 10),
      );

      queue.write('a', 42);

      expect(queue.pendingValueFor('a'), 42);
    });

    test('dispose() flushes pending writes', () async {
      final flushed = <int>[];
      final queue = WriteQueue<String, int>(
        flushOne: (key, value) async => flushed.add(value),
        logger: MemoryLogger(),
        window: const Duration(seconds: 10),
      );

      queue.write('a', 1);
      expect(flushed, isEmpty);

      await queue.dispose();

      expect(flushed, <int>[1]);
    });

    test('an urgent write bypasses the window', () async {
      final flushed = <int>[];
      final queue = WriteQueue<String, int>(
        flushOne: (key, value) async => flushed.add(value),
        logger: MemoryLogger(),
        window: const Duration(seconds: 30),
      );

      queue.write('a', 1, urgent: true);
      await Future<void>.delayed(Duration.zero);

      expect(flushed, <int>[1]);
      await queue.dispose();
    });

    test('a failing write logs a PersistenceFailure and does not throw to the caller', () async {
      final logger = MemoryLogger();
      final queue = WriteQueue<String, int>(
        flushOne: (key, value) async => throw Exception('disk full'),
        logger: logger,
        window: const Duration(seconds: 30),
      );

      queue.write('a', 1, urgent: true);
      await Future<void>.delayed(Duration.zero);

      expect(logger.records, hasLength(1));
      expect(logger.records.single.level, LogLevel.error);
      expect(logger.records.single.error, isA<PersistenceFailure>());
      await queue.dispose();
    });
  });
}
