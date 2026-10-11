import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets(
    'Windows screen gates receiver boxes on probes and lists device rates',
    (tester) async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.setShowAdvanced(true);
      await settings.setShowExpert(true);
      await settings.values.write(
        settingById('audio.outputDevice'),
        'wasapi/y',
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.dark(tv: false),
          home: SettingsScreen(
            settings: settings,
            section: SettingSection.audio,
            available: {
              SettingCapability.audioPassthrough,
              SettingCapability.audioDeviceSelection,
            },
            capabilities: CapabilityReport(
              hardwareDecode: false,
              decoders: [],
              hdrOutput: false,
              hdrFormats: [],
              displayModeSwitching: false,
              audioPassthrough: true,
              passthroughFormats: ['ac3', 'dts'],
              diagnostics: {
                'os': 'windows',
                'audioPassthroughDevices': 'wasapi/y\n',
                'audioPcmIsIec958': 'true',
              },
            ),
            audioDevices: [
              AudioDevice(
                id: 'wasapi/y',
                name: 'Other endpoint',
                supportedSampleRates: [48000],
              ),
              AudioDevice(
                id: 'wasapi/x',
                name: 'Speakers',
                isCurrent: true,
                supportedSampleRates: [44100, 48000, 96000],
              ),
            ],
          ),
        ),
      );
      for (final id in ['dolbyDigital', 'dts']) {
        expect(
          find.byKey(ValueKey('setting-audio.receiver.$id')),
          findsOneWidget,
        );
      }
      for (final id in ['ddPlus', 'dtsHd', 'trueHd']) {
        expect(
          find.byKey(ValueKey('setting-audio.receiver.$id')),
          findsNothing,
        );
      }
      final pass = tester.widget<SettingRow>(
        find.byKey(const ValueKey('setting-audio.passthroughDevice')),
      );
      expect(pass.choices, {'Auto': 'Auto', 'wasapi/y': 'Other endpoint'});
      final rate = tester.widget<SettingRow>(
        find.byKey(const ValueKey('setting-audio.sampleRate')),
      );
      expect(rate.choices, {'Auto': 'Auto', '48000': '48000'});
    },
  );

  testWidgets(
    'Windows stereo PCM-only hides passthrough device and stereo upmix',
    (tester) async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.setShowAdvanced(true);
      await settings.values.write(settingById('audio.speakerLayout'), 'Stereo');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.dark(tv: false),
          home: SettingsScreen(
            settings: settings,
            section: SettingSection.audio,
            available: {SettingCapability.audioDeviceSelection},
            capabilities: CapabilityReport(
              hardwareDecode: false,
              decoders: [],
              hdrOutput: false,
              hdrFormats: [],
              displayModeSwitching: false,
              audioPassthrough: false,
              passthroughFormats: [],
              diagnostics: {'os': 'windows'},
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('setting-audio.passthroughDevice')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('setting-audio.stereoUpmix')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('setting-audio.speakerLayout')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choice-option-5.1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('setting-audio.stereoUpmix')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Windows Fixed hides passthrough and transcode; IEC hides channel setting',
    (tester) async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.setShowAdvanced(true);
      await settings.values.write(settingById('audio.outputMode'), 'Fixed');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.dark(tv: false),
          home: SettingsScreen(
            settings: settings,
            section: SettingSection.audio,
            available: {
              SettingCapability.audioDeviceSelection,
              SettingCapability.audioPassthrough,
            },
            capabilities: CapabilityReport(
              hardwareDecode: false,
              decoders: [],
              hdrOutput: false,
              hdrFormats: [],
              displayModeSwitching: false,
              audioPassthrough: true,
              passthroughFormats: ['ac3'],
              diagnostics: {'os': 'windows', 'audioPcmIsIec958': 'true'},
            ),
          ),
        ),
      );
      for (final id in [
        'passthrough',
        'passthroughDevice',
        'ac3Transcode',
        'speakerLayout',
      ]) {
        expect(find.byKey(ValueKey('setting-audio.$id')), findsNothing);
      }
    },
  );
}
