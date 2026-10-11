import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, flags) in [
    ('without VM service', <String>[]),
    ('authenticated VM service', ['--service']),
    (
      'unauthenticated VM service',
      ['--disable-service-auth-codes', '--service'],
    ),
  ]) {
    test('reused PID is safe $name and same-VM recovery works', () async {
      final process = await Process.start('dart', [
        '--disable-dart-dev',
        if (flags.contains('--disable-service-auth-codes'))
          '--disable-service-auth-codes',
        '--packages=.dart_tool/package_config.json',
        'test/support/native_reference_probe.dart',
        if (flags.contains('--service')) '--service',
      ]);
      final output = utf8.decoder.bind(process.stdout).join();
      final errors = utf8.decoder.bind(process.stderr).join();
      try {
        final code = await process.exitCode.timeout(
          const Duration(seconds: 30),
        );
        final stdout = await output;
        final stderr = await errors;
        expect(code, 0, reason: '$stdout\n$stderr');
        expect(
          stdout,
          contains('legacy stale pointer ignored; same-VM recovery checked'),
        );
      } finally {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 5));
      }
    });
  }
}
