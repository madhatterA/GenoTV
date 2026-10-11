import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

Widget _app({required bool tv, bool reduced = false}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: ThemeData.dark().copyWith(
    extensions: <ThemeExtension<dynamic>>[RivuletTokens.dark(tv: tv)],
  ),
  builder: (context, child) => AdaptiveBehavior(
    capabilities: PlatformCapabilities(isTv: tv),
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
  ),
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () => showMediaContextMenu(
        context: context,
        actions: <MediaContextAction>[
          MediaContextAction(label: 'Play', onSelected: () {}),
        ],
      ),
      child: const Text('open'),
    ),
  ),
);

double _scale(WidgetTester tester) {
  final scales = find.ancestor(
    of: find.byType(GlassSurface),
    matching: find.byType(ScaleTransition),
  );
  return scales.evaluate().isEmpty
      ? 1
      : tester.widget<ScaleTransition>(scales.first).scale.value;
}

void main() {
  testWidgets('desktop: scales 0.96 to 1 over base, then settled', (
    tester,
  ) async {
    await tester.pumpWidget(_app(tv: false));
    await tester.tap(find.text('open'));
    await tester.pump(); // route built
    await tester.pump(); // ticker's first frame = t 0
    await tester.pump(const Duration(milliseconds: 20));
    expect(_scale(tester), lessThan(1));
    expect(_scale(tester), greaterThanOrEqualTo(0.96));
    await tester.pump(RivuletMotion.base);
    expect(_scale(tester), 1);
  });

  testWidgets('TV: fade only, no scale', (tester) async {
    await tester.pumpWidget(_app(tv: true));
    await tester.tap(find.text('open'));
    await tester.pump(); // route built
    await tester.pump(); // ticker's first frame = t 0
    await tester.pump(const Duration(milliseconds: 20));
    expect(_scale(tester), 1);
  });
}
