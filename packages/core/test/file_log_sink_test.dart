import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('logsink-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('records land in app.log; debug only when verbose; early ones kept', () async {
    var verbose = false;
    final sink = RotatingFileLogSink();
    final logger = ConsoleLogger(sink: sink.write);
    logger.info('before attach');
    sink.attach(dir, verbose: () => verbose);
    logger.debug('quiet');
    logger.warn('careful', error: 'boom');
    verbose = true;
    logger.debug('loud');
    await sink.flush();
    final text = File('${dir.path}/app.log').readAsStringSync();
    expect(text, contains('before attach'));
    expect(text, contains('WARN app: careful error=boom'));
    expect(text, contains('DEBUG app: loud'));
    expect(text, isNot(contains('quiet')));
  });

  test('rotates to app.1.log past the size cap', () async {
    final sink = RotatingFileLogSink(maxBytes: 200)..attach(dir, verbose: () => false);
    final logger = ConsoleLogger(sink: sink.write);
    for (var i = 0; i < 20; i++) {
      logger.info('line number $i');
    }
    await sink.flush();
    expect(File('${dir.path}/app.1.log').existsSync(), isTrue);
    expect(File('${dir.path}/app.log').lengthSync(), lessThanOrEqualTo(200));
  });

  test('a failing file write never throws into the caller', () async {
    final gone = Directory('${dir.path}/gone')..createSync();
    final sink = RotatingFileLogSink()..attach(gone, verbose: () => false);
    gone.deleteSync(recursive: true);
    final logger = ConsoleLogger(sink: sink.write);
    expect(() => logger.error('a', error: 'x'), returnsNormally);
    expect(() => logger.error('b', error: 'x'), returnsNormally);
    await sink.flush();
  });

  test('write returns before the disk is touched', () async {
    final sink = RotatingFileLogSink()..attach(dir, verbose: () => false);
    final logger = ConsoleLogger(sink: sink.write);
    for (var i = 0; i < 20; i++) {
      logger.info('burst $i');
    }
    expect(File('${dir.path}/app.log').existsSync(), isFalse);
    await sink.flush();
    expect(File('${dir.path}/app.log').readAsLinesSync(), hasLength(20));
  });
}
