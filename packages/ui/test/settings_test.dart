import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

CapabilityReport _report() => CapabilityReport(
  hardwareDecode: true,
  decoders: const <String>['h264'],
  hdrOutput: false,
  hdrFormats: const <String>[],
  displayModeSwitching: false,
  audioPassthrough: false,
  passthroughFormats: const <String>[],
  diagnostics: const <String, String>{
    'fallbackReason': 'software decode selected',
  },
);

void main() {
  testWidgets('settings write exact skip duration immediately', (tester) async {
    final appSettings = AppSettings(MemorySettingsStore());
    await setLogicalSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: SettingsScreen(
          settings: appSettings,
          capabilities: _report(),
          available: const <SettingCapability>{},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('section-playback')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('skip-forward-setting')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 seconds').last);
    await tester.pumpAndSettle();
    expect(appSettings.skipForward, const Duration(seconds: 60));
  });

  testWidgets('diagnostics renders fallback and copies every key/value', (
    tester,
  ) async {
    String? copied;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: DiagnosticsScreen(
          report: _report(),
          copyText: (text) async => copied = text,
        ),
      ),
    );
    expect(find.text('software decode selected'), findsOneWidget);
    final copy = tester.widget<AppButton>(
      find.byKey(const ValueKey<String>('copy-diagnostics')),
    );
    copy.onActivate!();
    await tester.pump();
    expect(copied, contains('fallbackReason: software decode selected'));
    expect(copied, contains('hardwareDecode: true'));
  });
}
