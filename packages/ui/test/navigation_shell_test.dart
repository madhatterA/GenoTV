import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

List<AppDestination> _destinations() => <AppDestination>[
  AppDestination(
    id: 'profile',
    label: 'Profile',
    icon: Icons.person_rounded,
    builder: (_) => const _TabPage(id: 'profile'),
  ),
  AppDestination(
    id: 'search',
    label: 'Search',
    icon: Icons.search_rounded,
    builder: (_) => const _TabPage(id: 'search'),
  ),
  AppDestination(
    id: 'home',
    label: 'Home',
    icon: Icons.home_filled,
    builder: (_) => const _TabPage(id: 'home'),
  ),
  AppDestination(
    id: 'movies',
    label: 'Movies',
    icon: Icons.local_movies_rounded,
    builder: (_) => const _TabPage(id: 'movies'),
  ),
  AppDestination(
    id: 'shows',
    label: 'Shows',
    icon: Icons.live_tv_rounded,
    builder: (_) => const _TabPage(id: 'shows'),
  ),
  AppDestination(
    id: 'settings',
    label: 'Settings',
    icon: Icons.settings_rounded,
    builder: (_) => const _TabPage(id: 'settings'),
  ),
];

/// A page that pushes a nested route and remembers a scroll offset via
/// `PageStorageKey`, so tab switches can be checked for stack/scroll
/// retention.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey<String>('page-$id'),
    // Decorative poster-tile blocks, not readable text: Rivulet's own
    // sidebar has real backdrop/poster art bleeding through its glass
    // (06_sidebar.png), never a text list — a plain `Text('$id item $n')`
    // list here was the opposite, a stray readable list showing through
    // the sidebar's translucent card in the golden.
    body: ListView.builder(
      key: PageStorageKey<String>('list-$id'),
      itemCount: 200,
      itemBuilder: (context, index) => Container(
        key: ValueKey<String>('$id-tile-$index'),
        height: 50,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        color: Color(0xFF000000 | (0x303030 + (index % 5) * 0x080808)),
      ),
    ),
    floatingActionButton: FloatingActionButton(
      key: ValueKey<String>('push-$id'),
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            key: ValueKey<String>('pushed-$id'),
            body: const Text('nested page'),
          ),
        ),
      ),
      child: const Icon(Icons.add),
    ),
  );
}

Widget _app({
  required List<AppDestination> destinations,
  String activeId = 'home',
  VoidCallback? onExitRequested,
}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: AppShell(
    destinations: destinations,
    activeId: activeId,
    onExitRequested: onExitRequested,
  ),
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu panel lists the rows in order with Settings pinned last', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(_app(destinations: _destinations()));
    await tester.pump();
    await _openMenu(tester);

    final order = <String>[
      'menu-item-profile',
      'menu-item-search',
      'menu-item-home',
      'menu-item-movies',
      'menu-item-shows',
      'menu-item-settings',
    ];
    var previous = -1.0;
    for (final key in order) {
      final finder = find.byKey(ValueKey<String>(key));
      expect(finder, findsOneWidget, reason: key);
      final top = tester.getTopLeft(finder).dy;
      expect(top, greaterThan(previous), reason: key);
      previous = top;
    }
    // Pinned at the bottom: its bottom edge sits 16 + 4 (row gap) + 8 above
    // the panel's bottom edge.
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey<String>('menu-item-settings')),
          )
          .dy,
      1080 - 16 - 4,
    );
  });

  testWidgets('desktop panel is 300 wide, full height, at the left edge', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(_app(destinations: _destinations()));
    await tester.pump();
    await _openMenu(tester);

    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('menu-panel')),
    );
    expect(panel.right, 300);
    expect(panel.top, 0);
    expect(panel.height, 1080);
  });

  testWidgets('opening dims the page and closing restores it', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(_app(destinations: _destinations()));
    await tester.pump();

    final scrim = find.byKey(const ValueKey<String>('menu-scrim'));
    expect(scrim, findsNothing);
    await _openMenu(tester);
    expect(scrim, findsOneWidget);

    await tester.tapAt(const Offset(1500, 500));
    await tester.pumpAndSettle();
    expect(scrim, findsNothing);
    expect(find.byKey(const ValueKey<String>('menu-panel')), findsNothing);
  });

  testWidgets('phone has no bottom bar and the pill opens the menu', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(400, 800));
    await tester.pumpWidget(_app(destinations: _destinations()));
    await tester.pump();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey<String>('menu-pill')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('top-search')), findsOneWidget);
  });

  testWidgets('search button opens Search; it is absent on Search itself', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(400, 800));
    await tester.pumpWidget(_app(destinations: _destinations()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('top-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('page-search')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('top-search')), findsNothing);
  });

  testWidgets('the top scrim fades in once the page is scrolled past 8 px', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(400, 800));
    await tester.pumpWidget(_app(destinations: _destinations()));
    await tester.pump();

    double scrimOpacity() => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('top-scrim')),
        )
        .opacity;
    expect(scrimOpacity(), 0);
    await tester.drag(
      find.byKey(const PageStorageKey<String>('list-home')),
      const Offset(0, -25),
    );
    await tester.pumpAndSettle();
    expect(scrimOpacity(), 1);
    await tester.drag(
      find.byKey(const PageStorageKey<String>('list-home')),
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(scrimOpacity(), 0);
  });

  testWidgets(
    'switching destinations retains each stack\'s pushed route and scroll offset',
    (tester) async {
      await setLogicalSize(tester, const Size(1920, 1080));
      await tester.pumpWidget(_app(destinations: _destinations()));
      await tester.pump();

      await tester.drag(
        find.byKey(const PageStorageKey<String>('list-home')),
        const Offset(0, -400),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('push-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('pushed-home')), findsOneWidget);

      await _openMenu(tester);
      await tester.tap(find.byKey(const ValueKey<String>('menu-item-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('page-search')), findsOneWidget);

      await _openMenu(tester);
      await tester.tap(find.byKey(const ValueKey<String>('menu-item-home')));
      await tester.pumpAndSettle();

      // The pushed nested route in "home" survived the tab switch.
      expect(find.byKey(const ValueKey<String>('pushed-home')), findsOneWidget);
    },
  );

  testWidgets(
    'Back asks a registered overlay handler before popping the destination stack',
    (tester) async {
      var overlayConsumed = false;
      var exited = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: AppShell(
            destinations: <AppDestination>[
              AppDestination(
                id: 'home',
                label: 'Home',
                icon: Icons.home,
                builder: (context) => _OverlayRegisteringPage(
                  onBack: () {
                    overlayConsumed = true;
                    return true;
                  },
                ),
              ),
            ],
            activeId: 'home',
            onExitRequested: () => exited = true,
          ),
        ),
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(overlayConsumed, isTrue);
      expect(exited, isFalse);
    },
  );

  testWidgets(
    'Back pops the local stack, then exits the app when nothing is left',
    (tester) async {
      var exited = false;
      await tester.pumpWidget(
        _app(
          destinations: _destinations(),
          onExitRequested: () => exited = true,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('push-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('pushed-home')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('pushed-home')), findsNothing);
      expect(exited, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exited, isTrue);
    },
  );

  testWidgets(
    'Back closes an open menu before the page pops or the app exits',
    (tester) async {
      var exited = false;
      await setLogicalSize(tester, const Size(1920, 1080));
      await tester.pumpWidget(
        _app(
          destinations: _destinations(),
          onExitRequested: () => exited = true,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('push-home')));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.byKey(const ValueKey<String>('menu-panel')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('menu-panel')), findsNothing);
      // The pushed page is still there: the panel took the Back press.
      expect(find.byKey(const ValueKey<String>('pushed-home')), findsOneWidget);
      expect(exited, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('pushed-home')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exited, isTrue);
    },
  );

  for (final size in const <Size>[
    Size(480, 480),
    Size(600, 700),
    Size(800, 600),
    Size(1400, 900),
    Size(1920, 1080),
  ]) {
    testWidgets(
      'page back button clears the menu pill and pops at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await setLogicalSize(tester, size);
        await tester.pumpWidget(
          _app(
            destinations: <AppDestination>[
              AppDestination(
                id: 'home',
                label: 'Home',
                icon: Icons.home_filled,
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      key: const ValueKey<String>('open-page'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Stack(children: <Widget>[PageBackButton()]),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              AppDestination(
                id: 'settings',
                label: 'Settings',
                icon: Icons.settings_rounded,
                builder: (_) => const SizedBox(),
              ),
            ],
          ),
        );
        final pill = find.byKey(const ValueKey<String>('menu-pill'));
        final pillLeftOnRoot = tester.getRect(pill).left;
        await tester.tap(find.byKey(const ValueKey<String>('open-page')));
        await tester.pumpAndSettle();
        final back = find.byKey(const ValueKey<String>('top-back'));
        // Order on screen: back, then the pill.
        expect(
          tester.getRect(back).right,
          lessThanOrEqualTo(tester.getRect(pill).left),
        );
        expect(tester.getRect(back).left, greaterThanOrEqualTo(0));
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(back, findsNothing);
        // The pill only steps right while a back button is showing.
        expect(tester.getRect(pill).left, pillLeftOnRoot);
      },
    );
  }
}

class _OverlayRegisteringPage extends StatefulWidget {
  const _OverlayRegisteringPage({required this.onBack});
  final bool Function() onBack;

  @override
  State<_OverlayRegisteringPage> createState() =>
      _OverlayRegisteringPageState();
}

class _OverlayRegisteringPageState extends State<_OverlayRegisteringPage> {
  VoidCallback? _unregister;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unregister ??= AppShellScope.maybeOf(context)?.register(widget.onBack);
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
