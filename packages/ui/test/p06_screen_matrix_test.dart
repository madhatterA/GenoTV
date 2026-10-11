import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/state_screen_registry.dart';

/// DESIGN_SPEC §12 golden matrix: 11 screens x phone/desktop/TV.
const _factors = <String, ({Size size, double dpr, bool tv})>{
  'phone': (size: Size(400, 800), dpr: 1, tv: false),
  'desktop': (size: Size(1280, 800), dpr: 1, tv: false),
  'tv': (size: Size(960, 540), dpr: 2, tv: true),
};

void main() {
  for (final id in p06MatrixFixtures.keys) {
    for (final entry in _factors.entries) {
      final factor = entry.value;
      testWidgets('$id ${entry.key}', (tester) async {
        debugDefaultTargetPlatformOverride = switch (entry.key) {
          'desktop' => TargetPlatform.macOS,
          _ => TargetPlatform.android,
        };
        tester.view.physicalSize = factor.size * factor.dpr;
        tester.view.devicePixelRatio = factor.dpr;
        addTearDown(tester.view.reset);
        final artwork = await loadFixtureArtworkResolver(tester);
        final built = await p06MatrixFixtures[id]!();
        await tester.pumpWidget(
          MaterialApp(
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(tv: factor.tv),
            home: AdaptiveBehavior(
              capabilities: factor.tv
                  ? const PlatformCapabilities.directionalPad()
                  : entry.key == 'phone'
                  ? const PlatformCapabilities.touch()
                  : const PlatformCapabilities(),
              child: ArtworkResolverScope(
                resolver: artwork,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: RepaintBoundary(
                    key: const ValueKey<String>('p06-matrix'),
                    child: built.widget,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey<String>('p06-matrix')),
          matchesGoldenFile('goldens/p06/${id}_${entry.key}.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await built.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
