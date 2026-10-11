import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/state_screen_registry.dart';
import 'support/surface_size.dart';

const _pill = ValueKey<String>('menu-pill');
const _panel = ValueKey<String>('menu-panel');
const _scrim = ValueKey<String>('menu-scrim');

/// The destinations of DESIGN_SPEC §7.1, in order.
List<AppDestination> _destinations({WidgetBuilder? home}) {
  AppDestination d(
    String id,
    String label,
    IconData icon,
    IconData active, [
    WidgetBuilder? builder,
  ]) => AppDestination(
    id: id,
    label: label,
    icon: icon,
    activeIcon: active,
    builder:
        builder ??
        (_) => Center(
          child: TextButton(
            autofocus: true,
            onPressed: () {},
            child: Text('page-$id'),
          ),
        ),
  );
  return <AppDestination>[
    d(
      'home',
      'Home',
      PhosphorIconsRegular.house,
      PhosphorIconsFill.house,
      home,
    ),
    d(
      'movies',
      'Movies',
      PhosphorIconsRegular.filmSlate,
      PhosphorIconsFill.filmSlate,
    ),
    d(
      'tv',
      'TV shows',
      PhosphorIconsRegular.television,
      PhosphorIconsFill.television,
    ),
    d(
      'genres',
      'Genres',
      PhosphorIconsRegular.squaresFour,
      PhosphorIconsFill.squaresFour,
    ),
    d('liked', 'Liked', PhosphorIconsRegular.heart, PhosphorIconsFill.heart),
    d(
      'search',
      'Search',
      PhosphorIconsRegular.magnifyingGlass,
      PhosphorIconsFill.magnifyingGlass,
    ),
    d(
      'play-link',
      'Play link',
      PhosphorIconsRegular.link,
      PhosphorIconsFill.link,
    ),
    d(
      'settings',
      'Settings',
      PhosphorIconsRegular.gear,
      PhosphorIconsFill.gear,
    ),
  ];
}

Widget _app(
  GlobalKey<AppShellState> key, {
  bool tv = false,
  WidgetBuilder? home,
  ArtworkResolver? artwork,
}) {
  Widget shell = AppShell(
    key: key,
    activeId: 'home',
    destinations: _destinations(home: home),
  );
  if (artwork != null) {
    shell = ArtworkResolverScope(resolver: artwork, child: shell);
  }
  return MaterialApp(
    localizationsDelegates: const [AppStrings.delegate],
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(tv: tv),
    home: AdaptiveBehavior(
      capabilities: tv
          ? const PlatformCapabilities.directionalPad()
          : const PlatformCapabilities(),
      child: shell,
    ),
  );
}

FocusNode _focusOf(WidgetTester tester, Finder item) => tester
    .widget<Focus>(
      find.descendant(of: item, matching: find.byType(Focus)).first,
    )
    .focusNode!;

Future<void> _openByTap(WidgetTester tester) async {
  await tester.tap(find.byKey(_pill));
  await tester.pumpAndSettle();
}

void main() {
  group('phone 400x800', () {
    Future<GlobalKey<AppShellState>> pump(WidgetTester tester) async {
      await setLogicalSize(tester, const Size(400, 800));
      final key = GlobalKey<AppShellState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();
      return key;
    }

    testWidgets(
      'no bottom bar; pill opens the panel; Movies switches and closes',
      (tester) async {
        final shell = await pump(tester);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byKey(_pill), findsOneWidget);
        expect(find.byKey(_panel), findsNothing);

        await _openByTap(tester);
        expect(find.byKey(_panel), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('menu-item-movies')),
        );
        await tester.pumpAndSettle();
        expect(shell.currentState!.activeId, 'movies');
        expect(find.byKey(_panel), findsNothing);
        expect(find.byKey(_pill), findsOneWidget);
      },
    );

    testWidgets('swipe-left fling at 600 px/s closes the panel', (
      tester,
    ) async {
      await pump(tester);
      await _openByTap(tester);
      await tester.fling(find.byKey(_panel), const Offset(-120, 0), 600);
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
    });

    testWidgets('a short slow drag springs the panel back open', (
      tester,
    ) async {
      await pump(tester);
      await _openByTap(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_panel)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsOneWidget);
    });

    testWidgets('scrim tap closes the panel', (tester) async {
      await pump(tester);
      await _openByTap(tester);
      expect(find.byKey(_scrim), findsOneWidget);
      await tester.tapAt(const Offset(390, 400));
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
    });

    testWidgets('Android back closes the panel before anything else', (
      tester,
    ) async {
      final shell = await pump(tester);
      await _openByTap(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
      expect(shell.currentState!.activeId, 'home');
    });

    testWidgets(
      'with the panel open at most 2 BackdropFilters are built (P3)',
      (tester) async {
        await pump(tester);
        await _openByTap(tester);
        expect(
          find.byType(BackdropFilter).evaluate().length,
          lessThanOrEqualTo(2),
        );
      },
    );

    testWidgets(
      'open and close animate with fade and slide only (no AnimatedPositioned)',
      (tester) async {
        await pump(tester);
        await tester.tap(find.byKey(_pill));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(AnimatedPositioned), findsNothing);
        expect(find.byType(SlideTransition), findsWidgets);
        expect(find.byType(FadeTransition), findsWidgets);
        await tester.pumpAndSettle();
      },
    );
  });

  group('desktop 1280x800', () {
    Future<GlobalKey<AppShellState>> pump(WidgetTester tester) async {
      await setLogicalSize(tester, const Size(1280, 800));
      final key = GlobalKey<AppShellState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();
      return key;
    }

    testWidgets('M opens, focus starts on the current row, Esc closes and '
        'focus returns to the pill', (tester) async {
      final shell = await pump(tester);
      _focusOf(tester, find.byKey(_pill)).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isTrue);
      expect(
        _focusOf(
          tester,
          find.byKey(const ValueKey<String>('menu-item-home')),
        ).hasPrimaryFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isFalse);
      expect(_focusOf(tester, find.byKey(_pill)).hasPrimaryFocus, isTrue);
    });

    testWidgets('Down, Down, Enter navigates to the third item', (
      tester,
    ) async {
      final shell = await pump(tester);
      _focusOf(tester, find.byKey(_pill)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentState!.activeId, 'tv');
      expect(shell.currentState!.menuOpen, isFalse);
    });

    testWidgets('Right arrow closes the open panel', (tester) async {
      final shell = await pump(tester);
      _focusOf(tester, find.byKey(_pill)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isFalse);
    });
  });

  group('tv 960x540', () {
    Future<GlobalKey<AppShellState>> pump(WidgetTester tester) async {
      await setLogicalSize(tester, const Size(960, 540));
      final key = GlobalKey<AppShellState>();
      await tester.pumpWidget(
        _app(
          key,
          tv: true,
          home: (_) => Row(
            children: <Widget>[
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 120 : 8, top: 120),
                  child: TextButton(
                    key: ValueKey<String>('poster-$i'),
                    autofocus: i == 0,
                    onPressed: () {},
                    child: Text('poster-$i'),
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return key;
    }

    testWidgets('Left on the first poster opens; Right closes and returns '
        'focus to that same poster', (tester) async {
      final shell = await pump(tester);
      final poster = FocusManager.instance.primaryFocus!;
      expect(poster.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isFalse);
      expect(poster.hasPrimaryFocus, isTrue);
    });

    testWidgets('the Menu key opens the panel; no BackdropFilter on TV', (
      tester,
    ) async {
      final shell = await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(shell.currentState!.menuOpen, isTrue);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const ValueKey<String>('top-search')), findsNothing);
    });
  });

  group('goldens', () {
    const factors = <String, ({Size size, double dpr, bool tv})>{
      'phone': (size: Size(400, 800), dpr: 1, tv: false),
      'desktop': (size: Size(1280, 800), dpr: 1, tv: false),
      'tv': (size: Size(960, 540), dpr: 2, tv: true),
    };
    for (final entry in factors.entries) {
      for (final open in <bool>[false, true]) {
        final name = 'shell_${open ? 'open' : 'closed'}_${entry.key}';
        testWidgets(name, (tester) async {
          final factor = entry.value;
          debugDefaultTargetPlatformOverride = switch (entry.key) {
            'desktop' => TargetPlatform.macOS,
            _ => TargetPlatform.android,
          };
          tester.view.physicalSize = factor.size * factor.dpr;
          tester.view.devicePixelRatio = factor.dpr;
          addTearDown(tester.view.reset);
          final artwork = await loadFixtureArtworkResolver(tester);
          final built = await p06MatrixFixtures['home']!();
          final key = GlobalKey<AppShellState>();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey<String>('shell-golden'),
              child: _app(
                key,
                tv: factor.tv,
                artwork: artwork,
                home: (_) => built.widget,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          if (open) {
            if (factor.tv) {
              await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
            } else {
              await tester.tap(find.byKey(_pill));
            }
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey<String>('shell-golden')),
            matchesGoldenFile('goldens/p06/$name.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          await built.dispose();
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  });
}
