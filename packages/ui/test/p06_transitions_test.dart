import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

const _page = ValueKey<String>('pushed-page');

Widget _app(Widget Function(BuildContext) home, {bool tv = false}) =>
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      builder: (_, child) => AdaptiveBehavior(
        capabilities: tv
            ? const PlatformCapabilities.directionalPad()
            : const PlatformCapabilities(),
        child: child!,
      ),
      home: Builder(builder: home),
    );

Widget _pusher(BuildContext context) => Center(
  child: TextButton(
    onPressed: () => Navigator.of(context).push<void>(
      AppPageRoute<void>(builder: (_) => const SizedBox(key: _page)),
    ),
    child: const Text('push'),
  ),
);

FadeTransition _fade(WidgetTester tester) => tester.widget<FadeTransition>(
  find
      .ancestor(of: find.byKey(_page), matching: find.byType(FadeTransition))
      .first,
);

Finder get _slide => find.ancestor(
  of: find.byKey(_page),
  matching: find.byType(SlideTransition),
);

AnimationStatus _status(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byKey(_page)))!.animation!.status;

Future<void> _push(WidgetTester tester) async {
  await tester.tap(find.text('push'));
  await tester.pump(); // route built
  await tester.pump(); // ticker's first frame = t 0
}

void main() {
  testWidgets('desktop push: front-loaded fade and slide, done at 240 ms', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(800, 600));
    await tester.pumpWidget(_app(_pusher));
    await _push(tester);
    await tester.pump(const Duration(milliseconds: 120));
    final opacity = _fade(tester).opacity.value;
    expect(opacity, inInclusiveRange(0.6, 1.0));
    final dx = tester.widget<SlideTransition>(_slide.first).position.value.dx;
    expect(dx * 800, inInclusiveRange(0.0, 24.0));
    await tester.pump(const Duration(milliseconds: 121));
    expect(_fade(tester).opacity.value, 1.0);
    expect(tester.widget<SlideTransition>(_slide.first).position.value.dx, 0);
    expect(_status(tester), AnimationStatus.completed);
  });

  testWidgets('pop takes 200 ms', (tester) async {
    await setLogicalSize(tester, const Size(800, 600));
    await tester.pumpWidget(_app(_pusher));
    await _push(tester);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 101));
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('TV: page appears immediately without fade or slide', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(_app(_pusher, tv: true));
    await _push(tester);
    expect(find.byKey(_page), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(_page),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(_slide, findsNothing);
    expect(_status(tester), AnimationStatus.completed);
  });

  testWidgets('reduced motion: no slide, done within 120 ms', (tester) async {
    await setLogicalSize(tester, const Size(800, 600));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          disableAnimations: true,
        ),
        child: _app(_pusher),
      ),
    );
    await _push(tester);
    await tester.pump(const Duration(milliseconds: 121));
    expect(_slide, findsNothing);
    expect(_fade(tester).opacity.value, 1.0);
    expect(_status(tester), AnimationStatus.completed);
  });

  group('menu destination switch', () {
    Future<void> switchTo(
      WidgetTester tester, {
      required bool tv,
      required Size size,
    }) async {
      await setLogicalSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: tv),
          home: AdaptiveBehavior(
            capabilities: tv
                ? const PlatformCapabilities.directionalPad()
                : const PlatformCapabilities(),
            child: AppShell(
              activeId: 'home',
              destinations: <AppDestination>[
                for (final id in <String>['home', 'movies'])
                  AppDestination(
                    id: id,
                    label: id,
                    icon: Icons.circle,
                    activeIcon: Icons.circle,
                    builder: (_) => Text('page-$id'),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('menu-item-movies')));
      await tester.pump();
    }

    testWidgets('outgoing page remains painted at the start of a switch', (
      tester,
    ) async {
      await switchTo(tester, tv: false, size: const Size(800, 600));
      expect(find.text('page-home'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('page-home'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('page-home'), findsNothing);
      expect(find.text('page-movies'), findsOneWidget);
    });

    testWidgets('desktop: FadeThroughTransition over 200 ms', (tester) async {
      await switchTo(tester, tv: false, size: const Size(800, 600));
      final anim = tester
          .widget<FadeThroughTransition>(
            find
                .ancestor(
                  of: find.text('page-movies'),
                  matching: find.byType(FadeThroughTransition),
                )
                .first,
          )
          .animation;
      await tester.pump(const Duration(milliseconds: 100));
      expect(anim.value, inExclusiveRange(0.0, 1.0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(anim.value, 1.0);
    });

    testWidgets('TV: plain fade over 150 ms', (tester) async {
      await switchTo(tester, tv: true, size: const Size(1920, 1080));
      expect(find.byType(FadeThroughTransition), findsNothing);
      final opacity = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('page-movies'),
              matching: find.byType(FadeTransition),
            ),
          )
          .firstWhere((w) => w.opacity is AnimationController)
          .opacity;
      await tester.pump(const Duration(milliseconds: 75));
      expect(opacity.value, inExclusiveRange(0.0, 1.0));
      await tester.pump(const Duration(milliseconds: 75));
      expect(opacity.value, 1.0);
    });
  });
}
