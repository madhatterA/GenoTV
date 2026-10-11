import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

// macos_reference.md 1.5 / 1.5.8: the digital-device fixture lists AC3, DTS and
// a 192 kHz E-AC3 carrier; only the AC3 and DTS tick boxes are visible.
CapabilityReport _report(List<String> formats, String os) => CapabilityReport(
  hardwareDecode: false,
  decoders: const [],
  hdrOutput: false,
  hdrFormats: const [],
  displayModeSwitching: false,
  audioPassthrough: formats.isNotEmpty,
  passthroughFormats: formats,
  diagnostics: {'os': os},
);

Future<void> _pump(
  WidgetTester tester,
  List<String> formats, {
  String os = 'macos',
}) async {
  final settings = AppSettings(MemorySettingsStore());
  await settings.setShowAdvanced(true);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      theme: AppTheme.dark(tv: false),
      home: SettingsScreen(
        settings: settings,
        section: SettingSection.audio,
        available: {if (formats.isNotEmpty) SettingCapability.audioPassthrough},
        capabilities: _report(formats, os),
        audioDevices: const [],
      ),
    ),
  );
}

void main() {
  testWidgets(
    'digital device shows passthrough, AC3, DTS and AC3 transcode only',
    (tester) async {
      await _pump(tester, ['ac3', 'dts', 'eac3']);
      for (final id in [
        'audio.passthrough',
        'audio.receiver.dolbyDigital',
        'audio.receiver.dts',
        'audio.ac3Transcode',
      ]) {
        expect(find.byKey(ValueKey('setting-$id')), findsOneWidget, reason: id);
      }
      for (final id in ['ddPlus', 'trueHd', 'dtsHd', 'atmos', 'dtsX']) {
        expect(
          find.byKey(ValueKey('setting-audio.receiver.$id')),
          findsNothing,
          reason: id,
        );
      }
    },
  );

  testWidgets('built-in PCM-only output hides every passthrough row', (
    tester,
  ) async {
    await _pump(tester, const []);
    for (final id in [
      'audio.passthrough',
      'audio.receiver.dolbyDigital',
      'audio.receiver.dts',
      'audio.ac3Transcode',
    ]) {
      expect(find.byKey(ValueKey('setting-$id')), findsNothing, reason: id);
    }
  });

  // Kodi 1.6 (macOS and Windows references): no multichannel LPCM setting.
  for (final os in ['macos', 'windows']) {
    testWidgets('$os never shows audio.multichannelLpcm', (tester) async {
      await _pump(tester, ['ac3', 'dts'], os: os);
      expect(
        find.byKey(const ValueKey('setting-audio.multichannelLpcm')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('setting-audio.passthrough')),
        findsOneWidget,
      );
    });
  }
}
