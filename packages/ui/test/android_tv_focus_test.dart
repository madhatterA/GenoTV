import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

Widget _app({required GlobalKey<AppShellState> shellKey}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: AdaptiveBehavior(
    capabilities: const PlatformCapabilities.directionalPad(),
    child: AppShell(
      key: shellKey,
      activeId: 'home',
      destinations: <AppDestination>[
        for (final id in <String>['home', 'movies', 'settings', 'empty'])
          if (id == 'empty')
            AppDestination(
              id: id,
              label: id,
              icon: Icons.home,
              builder: (_) => const Center(child: Text('nothing')),
            )
          else
            AppDestination(
              id: id,
              label: id,
              icon: Icons.home,
              builder: (context) => Center(
                child: TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const Text('detail'),
                    ),
                  ),
                  child: Text('open-$id'),
                ),
              ),
            ),
      ],
    ),
  ),
);

void main() {
  testWidgets('TV capability selects TV player and sidebar at compact size', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(960, 540));
    final shell = GlobalKey<AppShellState>();
    await tester.pumpWidget(_app(shellKey: shell));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AppShell));
    expect(AdaptiveBehavior.of(context).formFactor, FormFactor.tv);
    expect(find.byKey(const ValueKey<String>('menu-pill')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'D-pad traverses and selects sidebar, Right returns to page, Back pops',
    (tester) async {
      await setLogicalSize(tester, const Size(1920, 1080));
      final shell = GlobalKey<AppShellState>();
      await tester.pumpWidget(_app(shellKey: shell));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(shell.currentState!.activeId, 'movies');
      expect(shell.currentState!.menuOpen, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.text('open-movies'), findsOneWidget);
    },
  );

  testWidgets('extra Left in the open sidebar keeps focus in it', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    final shell = GlobalKey<AppShellState>();
    await tester.pumpWidget(_app(shellKey: shell));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(shell.currentState!.activeId, 'movies');
  });

  testWidgets('page without focusable content keeps D-pad in the sidebar', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    final shell = GlobalKey<AppShellState>();
    await tester.pumpWidget(_app(shellKey: shell));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    // Rows: home, movies, empty, then Settings pinned below the divider.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(shell.currentState!.activeId, 'empty');
    expect(shell.currentState!.menuOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(shell.currentState!.activeId, 'settings');
  });
}
