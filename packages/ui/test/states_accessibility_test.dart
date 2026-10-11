import 'dart:io';
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/state_screen_registry.dart';
import 'support/surface_size.dart';

Widget _app(
  Widget child, {
  bool highContrast = false,
  bool accessible = false,
}) => MaterialApp(
  localizationsDelegates: AppStrings.localizationsDelegates,
  supportedLocales: AppStrings.supportedLocales,
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark(tv: false),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        highContrast: highContrast || accessible,
        disableAnimations: true,
        textScaler: TextScaler.linear(accessible ? 2 : 1),
      ),
      child: UiAccessibility(
        reduceTransparency: accessible,
        child: Directionality(
          textDirection: accessible ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(body: child),
        ),
      ),
    ),
  ),
);

const _viewports = <Size>[
  Size(400, 800),
  Size(844, 390),
  Size(1280, 800),
  Size(1920, 1080),
];

Future<void> _nonFlat(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final count = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 0.2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final colors = <int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      colors.add(bytes.getUint32(i));
    }
    image.dispose();
    return colors.length;
  });
  expect(count, greaterThan(10), reason: 'real state pixels must not be flat');
}

const _desktopPointerTarget = MinimumTapTargetGuideline(
  size: Size(40, 40),
  link: 'DESIGN_SPEC §4.5',
);

void _matrixTests() {
  test('registry includes every exported public screen', () {
    final exports = File('lib/ui.dart').readAsStringSync();
    final names = <String>{};
    for (final match in RegExp(r"export '([^']+)';").allMatches(exports)) {
      final source = File('lib/${match[1]}').readAsStringSync();
      names.addAll(
        RegExp(r'class (\w*Screen)\b')
            .allMatches(source)
            .map((m) => m[1]!)
            .where((n) => !n.startsWith('_')),
      );
    }
    expect(publicScreenFixtures.map((f) => f.name).toSet(), names);
    expect(publicScreenExportPaths.keys.toSet(), names);
  });

  testWidgets('desktop after a touch press keeps 48 tap targets', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    final artwork = await loadFixtureArtworkResolver(tester);
    final handle = tester.ensureSemantics();
    try {
      final built = await publicScreenFixtures
          .firstWhere((f) => f.name == 'HomeScreen')
          .build(ScreenFixtureState.content);
      await tester.pumpWidget(
        _app(
          AdaptiveBehavior(
            child: ArtworkResolverScope(resolver: artwork, child: built.widget),
          ),
          accessible: false,
        ),
      );
      final touch = await tester.createGesture(kind: PointerDeviceKind.touch);
      await touch.down(const Offset(2, 2));
      await touch.up();
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.pumpWidget(const SizedBox.shrink());
      await built.dispose();
    } finally {
      handle.dispose();
    }
  });

  for (final size in _viewports) {
    for (final fixture in publicScreenFixtures) {
      testWidgets(
        '${fixture.name} states and accessibility ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await setLogicalSize(tester, size);
          final artwork = await loadFixtureArtworkResolver(tester);
          final handle = tester.ensureSemantics();
          try {
            for (final accessible in [false, true]) {
              for (final state in ScreenFixtureState.values) {
                final built = await fixture.build(state);
                await tester.pumpWidget(
                  _app(
                    ArtworkResolverScope(
                      resolver: artwork,
                      child: RepaintBoundary(child: built.widget),
                    ),
                    accessible: accessible,
                  ),
                );
                await tester.pump(const Duration(milliseconds: 600));
                expect(
                  tester.takeException(),
                  isNull,
                  reason:
                      '${fixture.name} ${state.name} accessible=$accessible',
                );
                await expectLater(
                  tester,
                  meetsGuideline(labeledTapTargetGuideline),
                );
                if (size.shortestSide < 600) {
                  await expectLater(
                    tester,
                    meetsGuideline(iOSTapTargetGuideline),
                  );
                  await expectLater(
                    tester,
                    meetsGuideline(androidTapTargetGuideline),
                  );
                } else {
                  // DESIGN_SPEC §4.5: desktop pointer hit target is 40.
                  await expectLater(
                    tester,
                    meetsGuideline(_desktopPointerTarget),
                  );
                }
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pump();
                expect(tester.takeException(), isNull);
                if (state == ScreenFixtureState.content && !accessible) {
                  await _nonFlat(tester);
                  await expectLater(
                    find.byType(Scaffold).first,
                    matchesGoldenFile(
                      'goldens/a11y_${fixture.name}_${size.width.toInt()}x${size.height.toInt()}.png',
                    ),
                  );
                }
                await tester.pumpWidget(const SizedBox.shrink());
                await built.dispose();
              }
            }
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'caller strings, terminal Back, secondary actions and partial focus',
    (tester) async {
      var backs = 0;
      var primary = 0;
      var secondary = 0;
      final focus = FocusNode();
      const labels = UiStateLabels(
        loading: 'بارگذاری',
        errorTitle: 'خطا',
        retry: 'تلاش دوباره',
        back: 'بازگشت',
        showCode: 'جزئیات',
        hideCode: 'بستن',
      );
      await tester.pumpWidget(
        _app(
          UiAccessibility(
            labels: labels,
            child: ErrorView(
              failure: const CancelledFailure(),
              message: 'پیام خطا',
              onBack: () => backs++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('بازگشت'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(backs, 1);
      await tester.pumpWidget(
        _app(
          EmptyView(
            headline: 'Empty',
            body: 'Explanation',
            onPrimary: () => primary++,
            primaryLabel: 'Primary',
            onSecondary: () => secondary++,
            secondaryLabel: 'Secondary',
          ),
        ),
      );
      await tester.tap(find.text('Primary'));
      await tester.tap(find.text('Secondary'));
      expect([primary, secondary], [1, 1]);
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              TextButton(
                focusNode: focus,
                onPressed: () {},
                child: const Text('Retained'),
              ),
              const PartialStateBanner(message: 'Some results are unavailable'),
            ],
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    },
  );
}

void main() {
  _matrixTests();
  testWidgets('loading is a single noninteractive skeleton region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const LoadingView()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('recoverable error focuses Retry and keyboard retries once', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        ErrorView(failure: const CancelledFailure(), onRetry: () => calls++),
      ),
    );
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('outage banner retains usable content focus', (tester) async {
    final focus = FocusNode();
    final outage = ConnectionOutageController();
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            TextButton(
              focusNode: focus,
              onPressed: () {},
              child: const Text('Content'),
            ),
            ConnectionOutageBanner(
              controller: outage,
              onRetry: () async {},
              hasUsableContent: true,
            ),
          ],
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    outage.updateConnection(healthy: false);
    await tester.pump();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    outage.dispose();
    focus.dispose();
  });
}
