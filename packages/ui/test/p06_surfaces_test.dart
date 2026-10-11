import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

Widget _host(Widget child, {bool tv = false, bool highContrast = false}) =>
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: tv),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1280, 800),
          highContrast: highContrast,
        ),
        child: AdaptiveBehavior(
          capabilities: tv
              ? const PlatformCapabilities.directionalPad()
              : const PlatformCapabilities(),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

const _box = SizedBox(width: 40, height: 40);

void main() {
  testWidgets('GlassSurface blurs on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_host(const GlassSurface(child: _box)));
    expect(find.byType(BackdropFilter), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('GlassSurface has no BackdropFilter on TV', (tester) async {
    await tester.pumpWidget(_host(const GlassSurface(child: _box), tv: true));
    expect(find.byType(BackdropFilter), findsNothing);
    final fill =
        (tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
                as BoxDecoration)
            .color;
    expect(fill, RivuletColors.dark().glassFillSolid);
  });

  testWidgets('GlassSurface has no BackdropFilter when opaque', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(
      _host(
        const UiAccessibility(
          reduceTransparency: true,
          child: GlassSurface(child: _box),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('TintedSurface never contains a BackdropFilter', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TintedSurface(child: _box),
            TintedSurface.overMedia(child: _box),
          ],
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final colors = RivuletColors.dark();
    final fills = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .toList();
    expect(
      fills,
      containsAll(<Color?>[colors.tintFill, colors.tintFillOverMedia]),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AmbientBackground paints inside a RepaintBoundary', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AmbientBackground(child: _box)));
    expect(
      find.descendant(
        of: find.byType(AmbientBackground),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(RepaintBoundary),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });
}
