import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Compiles the plugin's real bitstream-format predicate against CoreAudio
  // SDK structures (no device or OS setting is touched).
  test(
    'Kodi macOS 1.5.1-1.5.8 carrier-format detection (native predicate)',
    () {
      final result = Process.runSync('python3', [
        'test/macos_audio_formats_test.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('failures: 0, skipped: 0'));
    },
  );
}
