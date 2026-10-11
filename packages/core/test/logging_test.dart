import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scoped', () {
    test('nested scopes join with a dot', () {
      final records = <LogRecord>[];
      final logger = ConsoleLogger(sink: records.add);

      logger.scoped('a').scoped('b').info('hi');

      expect(records, hasLength(1));
      expect(records.single.scope, 'app.a.b');
    });
  });

  group('level filtering', () {
    test('a record below the minimum level is not delivered to the sink', () {
      final records = <LogRecord>[];
      final logger = ConsoleLogger(sink: records.add, minimumLevel: LogLevel.warn);

      logger.debug('ignored');
      logger.info('ignored');
      logger.warn('kept');
      logger.error('kept', error: Exception('boom'));

      expect(records.map((r) => r.message), <String>['kept', 'kept']);
    });
  });

  group('error()', () {
    test('delivers the error object and a non-null stack trace', () {
      final records = <LogRecord>[];
      final logger = ConsoleLogger(sink: records.add);
      final failure = Exception('boom');

      logger.error('failed', error: failure);

      expect(records.single.error, same(failure));
      expect(records.single.stack, isNotNull);
    });

    test('preserves a caller-supplied stack trace', () {
      final records = <LogRecord>[];
      final logger = ConsoleLogger(sink: records.add);
      final failure = Exception('boom');
      final stack = StackTrace.current;

      logger.error('failed', error: failure, stack: stack);

      expect(records.single.stack, same(stack));
    });
  });

  group('MemoryLogger', () {
    test('retains at most N records and drops the oldest', () {
      final logger = MemoryLogger(capacity: 2);

      logger.info('one');
      logger.info('two');
      logger.info('three');

      expect(logger.records.map((r) => r.message), <String>['two', 'three']);
    });

    test('a scoped child writes into the same backing records', () {
      final logger = MemoryLogger();
      final child = logger.scoped('worker');

      child.error('failed', error: Exception('boom'));

      expect(logger.records, hasLength(1));
      expect(logger.records.single.scope, 'app.worker');
    });
  });
}
