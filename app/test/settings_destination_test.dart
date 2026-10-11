import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:video_player/ui_bindings.dart';

final _report = CapabilityReport(
  hardwareDecode: true,
  decoders: const <String>['h264'],
  hdrOutput: false,
  hdrFormats: const <String>[],
  displayModeSwitching: false,
  audioPassthrough: false,
  passthroughFormats: const <String>[],
  diagnostics: const <String, String>{},
);

void main() {
  test('macOS passthrough follows the native probe, not the device list', () {
    expect(
      availableSettingCapabilities(_report, os: 'macos'),
      isNot(contains(SettingCapability.audioPassthrough)),
    );
    final digital = CapabilityReport(
      hardwareDecode: true,
      decoders: const <String>[],
      hdrOutput: false,
      hdrFormats: const <String>[],
      displayModeSwitching: true,
      audioPassthrough: true,
      passthroughFormats: const <String>['ac3', 'dts'],
      diagnostics: const <String, String>{},
    );
    expect(
      availableSettingCapabilities(digital, os: 'macos'),
      contains(SettingCapability.audioPassthrough),
    );
  });
  testWidgets('Settings destination opens Settings and a change persists', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(MemorySettingsStore());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: AppShell(
          activeId: 'home',
          destinations: <AppDestination>[
            AppDestination(
              id: 'home',
              label: 'Home',
              icon: Icons.home,
              builder: (_) => const Text('home body'),
            ),
            AppDestination(
              id: 'settings',
              label: 'Settings',
              icon: Icons.settings,
              builder: (_) => SettingsDestination(
                settings: settings,
                probe: () async => _report,
                audioDevices: () async => [
                  AudioDevice(id: 'coreaudio/speakers', name: 'Mac speakers'),
                ],
                logger: MemoryLogger(),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-item-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      tester
          .widget<SettingsScreen>(find.byType(SettingsScreen))
          .audioDevices
          .single
          .id,
      'coreaudio/speakers',
    );

    await tester.tap(find.byKey(const ValueKey<String>('section-playback')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('setting-playback.resume')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('choice-option-Always')),
    );
    await tester.pumpAndSettle();
    expect(
      settings.values.read<String>(settingById('playback.resume')),
      'Always',
    );
  });

  test('removed engine-unsupported settings have no schema entry', () {
    final ids = settingDefs.map((d) => d.id).toSet();
    expect(ids.intersection(retiredSettingKeys.toSet()), isEmpty);
  });

  test('capability set comes from the probe report and the OS', () {
    final none = availableSettingCapabilities(_report, os: 'ios');
    // Kodi iOS always offers the Default/Touchscreen monitor choice (§4.1).
    expect(none, {SettingCapability.multipleDisplays});
    final report = CapabilityReport(
      hardwareDecode: true,
      decoders: const <String>[],
      hdrOutput: true,
      hdrFormats: const <String>['hdr10'],
      displayModeSwitching: true,
      audioPassthrough: true,
      passthroughFormats: const <String>[],
      diagnostics: const <String, String>{},
    );
    expect(
      availableSettingCapabilities(report, os: 'macos'),
      <SettingCapability>{
        SettingCapability.displayModeSwitching,
        SettingCapability.refreshRateControl,
        SettingCapability.hdrOutput,
        SettingCapability.multipleDisplays,
        SettingCapability.audioPassthrough,
        SettingCapability.audioDeviceSelection,
        SettingCapability.exclusiveAudio,
        SettingCapability.desktopWindow,
        SettingCapability.gpuBackend,
      },
    );
  });

  testWidgets(
    'changing Windows passthrough endpoint refreshes the screen capability report',
    (tester) async {
      final settings = AppSettings(MemorySettingsStore());
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.dark(tv: false),
          home: SettingsDestination(
            settings: settings,
            logger: MemoryLogger(),
            probe: () async {
              calls++;
              final id = settings.values.read<String>(
                settingById('audio.passthroughDevice'),
              );
              return CapabilityReport(
                hardwareDecode: false,
                decoders: [],
                hdrOutput: false,
                hdrFormats: [],
                displayModeSwitching: false,
                audioPassthrough: true,
                passthroughFormats: id == 'wasapi/spdif'
                    ? ['ac3']
                    : ['ac3', 'eac3'],
                diagnostics: {'os': 'windows'},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .capabilities
            .passthroughFormats,
        ['ac3', 'eac3'],
      );
      await settings.values.write(
        settingById('audio.passthroughDevice'),
        'wasapi/spdif',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .capabilities
            .passthroughFormats,
        ['ac3'],
      );
      expect(calls, 2);
    },
  );
}
