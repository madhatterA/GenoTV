import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import '../support/fixture_artwork.dart';
import '../support/state_screen_registry.dart';

void main() {
  const key = LogicalKeyboardKey.goBack;
  for (final popFirst in [false, true]) {
    testWidgets('TV ${key.keyLabel}, pop first: $popFirst', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final model = HomeViewModel(
        rows: keywalkHomeRows(),
        firstDeferredSectionReady: true,
        secondDeferredSectionReady: true,
      );
      addTearDown(model.dispose);
      final resolver = await loadFixtureArtworkResolver(tester);
      late BuildContext homeContext;
      var exits = 0;
      var pops = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: true),
          builder: (_, child) => NavigatorBackShortcuts(child: child!),
          home: AdaptiveBehavior(
            capabilities: const PlatformCapabilities.directionalPad(),
            child: ArtworkResolverScope(
              resolver: resolver,
              child: AppShell(
                activeId: 'home',
                onExitRequested: () => exits++,
                destinations: [
                  AppDestination(
                    id: 'home',
                    label: 'Home',
                    icon: Icons.home,
                    builder: (context) {
                      homeContext = context;
                      return HomeScreen(viewModel: model);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // goBack has no physical key; supply a mapped scan code for the simulator.
      Future<void> backPress() async {
        if (popFirst) await tester.binding.handlePopRoute();
        await tester.sendKeyEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
          platform: 'android',
        );
        await tester.pumpAndSettle();
        if (!popFirst) await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      final route = AppPageRoute<void>(
        builder: (_) => Material(
          child: MovieDetailScreen(
            presentation: MovieDetailPresentation(
              item: model.rows.first.items.first,
              year: '2024',
              summary: 'Back regression fixture.',
              related: const [],
            ),
            onPlay: () {},
          ),
        ),
      );
      unawaited(
        Navigator.of(homeContext).push<void>(route).then((_) {
          pops++;
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('detail-page')), findsOneWidget);

      // With the panel open above detail, one press only closes the panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
      await backPress();
      expect(find.byKey(const ValueKey('menu-panel')), findsNothing);
      expect(find.byKey(const ValueKey('detail-page')), findsOneWidget);
      expect(route.isCurrent, isTrue);
      expect(pops, 0);
      expect(exits, 0);

      // With detail focused, one press pops detail and leaves Home alone.
      await backPress();
      expect(find.byKey(const ValueKey('detail-page')), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(Navigator.of(homeContext).canPop(), isFalse);
      expect(pops, 1);
      expect(exits, 0);

      // Home must not stage focus in response to the remote key either.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final rowFocus = FocusManager.instance.primaryFocus;
      expect(rowFocus?.context, isNotNull);
      await tester.sendKeyEvent(
        key,
        physicalKey: PhysicalKeyboardKey.escape,
        platform: 'android',
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(rowFocus));
      expect(exits, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
