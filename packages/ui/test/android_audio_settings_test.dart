import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/settings/settings_catalog.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('Android screen uses format probes and supported sink rates', (
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
          section: SettingSection.audio,
          available: {SettingCapability.audioPassthrough},
          capabilities: CapabilityReport(
            hardwareDecode: false,
            decoders: [],
            hdrOutput: false,
            hdrFormats: [],
            displayModeSwitching: false,
            audioPassthrough: true,
            passthroughFormats: ['ac3'],
            diagnostics: {'os': 'android'},
          ),
          audioDevices: [
            AudioDevice(
              id: 'auto',
              name: 'AudioTrack',
              kind: AudioDeviceKind.unknown,
              isCurrent: true,
              supportedSampleRates: [32000, 48000],
            ),
          ],
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('setting-audio.receiver.dolbyDigital')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('setting-audio.receiver.ddPlus')),
      findsNothing,
    );
    final rate = tester.widget<SettingRow>(
      find.byKey(const ValueKey('setting-audio.sampleRate')),
    );
    expect(rate.choices, {'Auto': 'Auto', '32000': '32000', '48000': '48000'});
  });
  Set<String> audioSettings(List<String>? formats) => visibleSettings(
    SettingSection.audio,
    showAdvanced: true,
    showExpert: true,
    available: {SettingCapability.audioPassthrough},
    passthroughFormats: formats,
  ).map((setting) => setting.id).toSet();

  test('Android hides rejected formats while keeping the master switch', () {
    final ids = audioSettings([]);
    expect(ids, contains('audio.passthrough'));
    expect(ids.where((id) => id.startsWith('audio.receiver.')), isEmpty);
    expect(ids, isNot(contains('audio.ac3Transcode')));
  });

  test(
    'Android exposes only probed receiver formats, without object toggles',
    () {
      final ids = audioSettings(['ac3', 'eac3', 'dtsHd']);
      expect(ids, contains('audio.ac3Transcode'));
      expect(
        ids,
        containsAll([
          'audio.receiver.dolbyDigital',
          'audio.receiver.ddPlus',
          'audio.receiver.dtsHd',
        ]),
      );
      for (final id in ['dts', 'trueHd', 'atmos', 'dtsX']) {
        expect(ids, isNot(contains('audio.receiver.$id')));
      }
    },
  );

  test('Other OS receiver visibility keeps the existing capability gate', () {
    expect(
      audioSettings(null).where((id) => id.startsWith('audio.receiver.')),
      hasLength(7),
    );
  });

  test('iOS audio page omits every setting Kodi iOS does not handle', () {
    final ids = visibleSettings(
      SettingSection.audio,
      showAdvanced: true,
      showExpert: true,
      available: const <SettingCapability>{},
    ).map((setting) => setting.id).toSet();
    expect(
      ids,
      containsAll([
        'audio.speakerLayout',
        'audio.outputMode',
        'audio.sampleRate',
        'audio.stereoUpmix',
        'audio.downmixDialogue',
        'audio.normalizeVolume',
        'audio.resamplingQuality',
      ]),
    );
    for (final id in [
      'audio.outputDevice',
      'audio.passthroughDevice',
      'audio.passthrough',
      'audio.multichannelLpcm',
      'audio.ac3Transcode',
      'audio.exclusiveMode',
    ]) {
      expect(ids, isNot(contains(id)));
    }
    expect(ids.where((id) => id.startsWith('audio.receiver.')), isEmpty);
  });

  testWidgets('iOS sample rate offers the rates Kodi iOS advertises', (
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
          section: SettingSection.audio,
          available: const <SettingCapability>{},
          capabilities: CapabilityReport(
            hardwareDecode: false,
            decoders: [],
            hdrOutput: false,
            hdrFormats: [],
            displayModeSwitching: false,
            audioPassthrough: false,
            passthroughFormats: [],
            diagnostics: {'os': 'ios'},
          ),
          audioDevices: [
            AudioDevice(
              id: 'speaker',
              name: 'Speaker',
              isCurrent: true,
              supportedSampleRates: [44100, 48000],
            ),
          ],
        ),
      ),
    );
    final rate = tester.widget<SettingRow>(
      find.byKey(const ValueKey('setting-audio.sampleRate')),
    );
    expect(rate.choices, {'Auto': 'Auto', '44100': '44100', '48000': '48000'});
  });
}
