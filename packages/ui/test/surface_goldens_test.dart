import 'package:core/core.dart';
import 'package:contracts/contracts.dart';
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
  diagnostics: const <String, String>{'fallbackReason': 'fixture'},
);

void main() {
  testWidgets('settings stays composed at compact and desktop sizes', (
    tester,
  ) async {
    final settings = AppSettings(MemorySettingsStore());
    for (final size in const <Size>[Size(400, 800), Size(1400, 900)]) {
      await setLogicalSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.dark(tv: false),
          home: SettingsScreen(
            settings: settings,
            capabilities: _report(),
            available: const <SettingCapability>{},
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(SettingsScreen),
        matchesGoldenFile('goldens/settings_${size.width.toInt()}.png'),
      );
    }
  });

  testWidgets('player keeps an escape affordance at both sizes', (
    tester,
  ) async {
    for (final size in const <Size>[Size(402, 874), Size(1400, 900)]) {
      await setLogicalSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.dark(tv: false),
          // `Scaffold`, not a bare `home:`: `PreviewPlayerScreen` builds no
          // `Scaffold`/`Material` of its own (production reaches it via a
          // route pushed over `AppShell`'s own Scaffold). Without one here,
          // its title text loses the Material-provided default text style
          // and the `Roboto` fallback with it — invisible on a host with a
          // system fallback font, but tofu/placeholder glyphs under
          // `flutter test`'s font-less environment. See `decisions.md`.
          home: const Scaffold(
            body: PreviewPlayerScreen(mediaId: 'surface-player'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Close player'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey<String>('player-screen')),
        matchesGoldenFile('goldens/player_${size.width.toInt()}.png'),
      );
      // A golden must never pass with Flutter's red/yellow error box baked
      // in — `matchesGoldenFile` only diffs pixels, it does not know a
      // RenderFlex overflow from real content.
      expect(
        tester.takeException(),
        isNull,
        reason: 'no FlutterError/overflow at ${size.width.toInt()}',
      );
    }
  });
}
