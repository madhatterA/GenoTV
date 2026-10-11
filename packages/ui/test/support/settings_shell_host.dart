import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

CapabilityReport settingsTestReport() => CapabilityReport(
  hardwareDecode: true,
  decoders: const <String>['h264'],
  hdrOutput: false,
  hdrFormats: const <String>[],
  displayModeSwitching: false,
  audioPassthrough: false,
  passthroughFormats: const <String>[],
  diagnostics: const <String, String>{'fallbackReason': 'fixture'},
);

Widget settingsProvidersFixture(BuildContext context) => ProvidersScreen(
  load: () async => const [UiProviderAccount(id: 'ccloud', name: 'CCloud')],
  onCredentials: (_, _, _) async => 'Sign-in is not available in the app yet',
  onStartQr: (_) async =>
      UiQrLogin(code: 'fixture', url: Uri.parse('https://example.com')),
  onPollQr: (_, _) async => false,
  onLogout: (_) async {},
  onBuy: (_) async {},
);

/// Pumps a [SettingsScreen] over [settings], as the app mounts it.
Future<void> pumpSettings(
  WidgetTester tester,
  AppSettings settings, {
  Set<SettingCapability> available = const <SettingCapability>{},
  PlatformCapabilities platform = const PlatformCapabilities(),
  List<AudioDevice> audioDevices = const <AudioDevice>[],
  Future<int> Function()? onClearCache,
  Map<String, String> settingNotes = const <String, String>{},
  ValueListenable<Map<String, String>>? liveDiagnostics,
  WidgetBuilder? providersPage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      theme: AppTheme.dark(tv: false),
      home: AdaptiveBehavior(
        capabilities: platform,
        child: RepaintBoundary(
          key: const ValueKey<String>('settings-focus-capture'),
          child: SettingsScreen(
            settings: settings,
            capabilities: settingsTestReport(),
            available: available,
            audioDevices: audioDevices,
            onClearCache: onClearCache,
            settingNotes: settingNotes,
            liveDiagnostics: liveDiagnostics,
            providersPage: providersPage,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
