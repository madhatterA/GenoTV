import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/settings_shell_host.dart';
import 'support/surface_size.dart';

const _rows = <String, String>{
  'Video codec': 'h264 (High)',
  'Decoder': 'videotoolbox',
  'Video width': '3840',
  'Video height': '2160',
  'Pixel format': 'yuv420p10',
  'Transfer function': 'pq',
  'HDR signal peak': '4.926108',
  'Dropped frames (output)': '2',
  'Video bitrate': '18420 kbit/s',
  'Buffered (seconds)': '41.2',
  'Audio codec': 'eac3 (Dolby Digital Plus)',
  'Audio output': 'coreaudio',
  'Audio output format': 'spdif-eac3 (passthrough)',
};

Future<AppSettings> _advanced() async {
  final settings = AppSettings(MemorySettingsStore());
  await settings.setShowAdvanced(true);
  return settings;
}

void main() {
  final all = SettingCapability.values.toSet();

  testWidgets('Advanced page: multi-line custom options with rejection note', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    await pumpSettings(
      tester,
      await _advanced(),
      available: all,
      settingNotes: const {
        'advanced.customMpvOptions': 'Rejected: no-such-option (mpv rejected no-such-option=1: property not found (-8))',
      },
    );
    await tester.tap(find.byKey(const ValueKey<String>('section-advanced')));
    await tester.pumpAndSettle();
    expect(find.textContaining('property not found (-8)'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.maxLines, greaterThan(1));
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_advanced_custom_options.png'),
    );
  });

  testWidgets('Diagnostics page follows the live rows', (tester) async {
    await setLogicalSize(tester, const Size(1280, 1250));
    final live = ValueNotifier<Map<String, String>>(const {
      'Playback': 'Not playing',
    });
    addTearDown(live.dispose);
    await pumpSettings(
      tester,
      await _advanced(),
      available: all,
      liveDiagnostics: live,
    );
    await tester.tap(find.byKey(const ValueKey<String>('section-advanced')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playback diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Not playing'), findsOneWidget);

    live.value = _rows;
    await tester.pumpAndSettle();
    expect(find.text('Not playing'), findsNothing);
    expect(find.text('spdif-eac3 (passthrough)'), findsOneWidget);
    await expectLater(
      find.byType(DiagnosticsScreen),
      matchesGoldenFile('goldens/settings_diagnostics_populated.png'),
    );
  });
}
