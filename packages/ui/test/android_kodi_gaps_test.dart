import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/settings/settings_catalog.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('Android keep-alive is Expert without exclusive mode', (
    tester,
  ) async {
    final settings = AppSettings(MemorySettingsStore());
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: SettingsScreen(
          settings: settings,
          section: SettingSection.audio,
          available: const {},
          capabilities: CapabilityReport(
            hardwareDecode: false,
            decoders: [],
            hdrOutput: false,
            hdrFormats: [],
            displayModeSwitching: true,
            audioPassthrough: false,
            passthroughFormats: [],
            diagnostics: {'os': 'android'},
          ),
        ),
      ),
    );
    await show();
    expect(
      find.byKey(const ValueKey('setting-audio.deviceKeepAlive')),
      findsNothing,
    );
    await settings.setShowAdvanced(true);
    await settings.setShowExpert(true);
    await tester.pumpWidget(const SizedBox());
    await show();
    expect(
      find.byKey(const ValueKey('setting-audio.deviceKeepAlive')),
      findsOneWidget,
    );
    for (final id in [
      'audio.exclusiveMode',
      'audio.outputDevice',
      'audio.passthroughDevice',
    ]) {
      expect(find.byKey(ValueKey('setting-$id')), findsNothing);
    }
  });

  testWidgets('Android rate list contains only enumerated display rates', (
    tester,
  ) async {
    final settings = AppSettings(MemorySettingsStore());
    await settings.setShowAdvanced(true);
    await settings.setShowExpert(true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: SettingsScreen(
          settings: settings,
          section: SettingSection.display,
          available: {
            SettingCapability.displayModeSwitching,
            SettingCapability.refreshRateControl,
          },
          capabilities: CapabilityReport(
            hardwareDecode: false,
            decoders: [],
            hdrOutput: false,
            hdrFormats: [],
            displayModeSwitching: true,
            audioPassthrough: false,
            passthroughFormats: [],
            diagnostics: {'os': 'android', 'display.refreshRates': '60.0,90.0'},
          ),
        ),
      ),
    );
    final row = tester.widget<SettingRow>(
      find.byKey(const ValueKey('setting-display.refreshRate')),
    );
    expect(row.choices, {'auto': 'Auto', '60.0': '60.0', '90.0': '90.0'});
    for (final id in [
      'video.matchFrameRate',
      'video.matchResolution',
      'video.displayModeWhitelist',
    ]) {
      expect(find.byKey(ValueKey('setting-$id')), findsOneWidget);
    }
    for (final id in ['video.hdr', 'display.hdrOutputMode']) {
      expect(find.byKey(ValueKey('setting-$id')), findsNothing);
    }
    final basic = visibleSettings(
      SettingSection.display,
      showAdvanced: false,
      showExpert: false,
      available: {
        SettingCapability.displayModeSwitching,
        SettingCapability.refreshRateControl,
      },
    );
    expect(
      basic.map((d) => d.id),
      containsAll(['video.matchFrameRate', 'video.matchResolution']),
    );
    expect(
      basic.map((d) => d.id),
      isNot(contains('video.displayModeWhitelist')),
    );
  });
}
