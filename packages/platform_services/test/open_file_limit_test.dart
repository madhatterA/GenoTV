import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

void main() {
  test('raises the soft open-file limit to min(hard, 4096), never lowers it', () {
    final logger = MemoryLogger();
    final first = raiseOpenFileLimit(logger)!;
    final hard = int.parse(
      (Process.runSync('sh', ['-c', 'ulimit -Hn']).stdout as String).trim() == 'unlimited'
          ? '9223372036854775807'
          : (Process.runSync('sh', ['-c', 'ulimit -Hn']).stdout as String).trim(),
    );
    expect(first, greaterThanOrEqualTo(hard < 4096 ? hard : 4096));
    expect(raiseOpenFileLimit(logger), first); // second call: no change, no lowering
    expect(logger.records.any((r) => r.level == LogLevel.info), isTrue);
  });
}
