import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates a leaf declared in another Part's package. This test file is a
/// different Dart library from `app_failure.dart`, so a compiling `extends`
/// here genuinely proves the cross-package extension model works.
final class _FakeTransportFailure extends AppFailure {
  const _FakeTransportFailure({required super.cause})
      : super(
          code: '${FailureCodes.transportHttpPrefix}.timeout',
          message: 'Request timed out',
        );
}

void main() {
  group('AppFailure.toString', () {
    test('renders code: message', () {
      const failure = CancelledFailure();
      expect(failure.toString(), 'app.cancelled: Operation was cancelled');
    });

    test('includes the cause when present', () {
      final failure = UnexpectedFailure(cause: Exception('boom'));
      expect(failure.toString(), contains('app.unexpected: An unexpected error occurred'));
      expect(failure.toString(), contains('boom'));
    });
  });

  group('cross-package leaf', () {
    test('a subtype declared outside core.dart is assignable to AppFailure', () {
      final AppFailure failure = _FakeTransportFailure(cause: Exception('timed out'));
      expect(failure.code, 'transport.http.timeout');
      expect(failure, isA<AppFailure>());
    });
  });

  group('FailureLogging', () {
    test('logger.failure(f) produces exactly one error-level record carrying the code', () {
      final logger = MemoryLogger();
      final failure = _FakeTransportFailure(cause: Exception('timed out'));

      logger.failure(failure);

      expect(logger.records, hasLength(1));
      final record = logger.records.single;
      expect(record.level, LogLevel.error);
      expect(record.scope, contains(failure.code));
      expect(record.error, same(failure));
    });
  });
}
