import 'package:contracts/fakes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/state_screen_registry.dart';

class _Cast implements CastUiController {
  @override
  final ValueNotifier<CastUiState> state = ValueNotifier<CastUiState>(
    const CastUiState(),
  );
  final calls = <String>[];
  @override
  Future<void> startDiscovery() async => calls.add('start');
  @override
  Future<void> stopDiscovery() async => calls.add('stopDiscovery');
  @override
  Future<void> cast(String id) async => calls.add('cast:$id');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> seek(Duration position) async => calls.add('seek');
  @override
  Future<void> stop() async => calls.add('stop');
}

Future<void> _phone(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.reset();
  });
  final artwork = await loadFixtureArtworkResolver(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      theme: AppTheme.dark(tv: false),
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(padding: const EdgeInsets.only(top: 24)),
        child: AdaptiveBehavior(
          capabilities: const PlatformCapabilities.touch(),
          child: ArtworkResolverScope(resolver: artwork, child: navigator!),
        ),
      ),
      home: child,
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

List<AppDestination> _destinations(Widget home) => <AppDestination>[
  AppDestination(
    id: 'home',
    label: 'Home',
    icon: Icons.home,
    builder: (_) => home,
  ),
  AppDestination(
    id: 'search',
    label: 'Search',
    icon: Icons.search,
    builder: (_) => const SizedBox(),
  ),
  AppDestination(
    id: 'settings',
    label: 'Settings',
    icon: Icons.settings,
    builder: (_) => const SizedBox(),
  ),
];

void _targets(WidgetTester tester) {
  for (final type in <Type>[FocusableAction, FocusableCard, AppIconButton]) {
    for (final element in find.byType(type).evaluate()) {
      final gestures = find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(GestureDetector),
          )
          .evaluate()
          .where((e) {
            final gesture = e.widget as GestureDetector;
            return gesture.onTap != null || gesture.onTapDown != null;
          });
      expect(gestures, isNotEmpty, reason: '$type has a gesture target');
      final box = gestures.first.renderObject! as RenderBox;
      expect(box.size.width, greaterThanOrEqualTo(48), reason: '$type width');
      expect(
        box.size.height,
        greaterThanOrEqualTo(48),
        reason:
            '$type height ${element.widget} parent=${element.findAncestorWidgetOfExactType<AppIconButton>()} chip=${element.findAncestorWidgetOfExactType<AppChip>()} sized=${element.findAncestorWidgetOfExactType<SizedBox>()}',
      );
    }
  }
}

void _test(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  for (final size in <Size>[const Size(400, 800), const Size(360, 740)]) {
    for (final id in <String>[
      'home',
      'movies',
      'movie_detail',
      'settings_root',
      'settings_audio',
      'search',
      'play_link',
    ]) {
      _test('$id targets ${size.width}', (tester) async {
        final built = await p06MatrixFixtures[id]!();
        await _phone(tester, built.widget, size: size);
        expect(tester.takeException(), isNull);
        _targets(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await built.dispose();
      });
    }
  }

  _test('Home top controls respect the small phone safe area', (tester) async {
    final built = await p06MatrixFixtures['home']!();
    await _phone(
      tester,
      AppShell(activeId: 'home', destinations: _destinations(built.widget)),
      size: const Size(360, 740),
    );
    _targets(tester);
    final pill = tester.getRect(find.byKey(const ValueKey('menu-pill')));
    final search = tester.getRect(find.byKey(const ValueKey('top-search')));
    expect(pill.overlaps(search), isFalse);
    expect(pill.top, greaterThanOrEqualTo(24));
    expect(search.top, greaterThanOrEqualTo(24));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await built.dispose();
  });

  _test('600ms media long press opens the context menu at the press point', (
    tester,
  ) async {
    final built = await p06MatrixFixtures['home']!();
    await _phone(tester, built.widget);
    final card = find.byKey(const ValueKey('row-1-item-0'));
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 600));
    final point = tester.getCenter(card);
    final gesture = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Details'), findsOneWidget);
    final menu = tester.getRect(
      find.ancestor(
        of: find.text('Details'),
        matching: find.byType(GlassSurface),
      ),
    );
    expect(menu.left, closeTo(point.dx.clamp(0, 400 - menu.width), 0.01));
    expect(menu.top, closeTo(point.dy.clamp(0, 800 - menu.height), 0.01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await built.dispose();
  });

  _test('phone player cast button opens a bottom sheet', (tester) async {
    final playback = FakePlaybackController();
    final cast = _Cast();
    await _phone(
      tester,
      PlayerScreen(
        title: 'Fixture player',
        controller: playback,
        videoSurface: const FakeVideoSurface(),
        cast: cast,
        setSystemUiMode: (_) async {},
        onExit: () {},
      ),
    );
    final castHit = find.byKey(const ValueKey('phone-hit-Cast'));
    expect(tester.getSize(castHit), const Size(48, 48));
    final castCircle = tester.getRect(
      find.byKey(const ValueKey('cast-button')),
    );
    await tester.tapAt(Offset(castCircle.left - 1, castCircle.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('app-sheet')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('app-sheet'))).height, 680);
    expect(castHit.hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await playback.dispose();
    cast.state.dispose();
  });

  for (final size in <Size>[const Size(400, 800), const Size(360, 740)]) {
    _test('detail source entry opens and dismisses sheet ${size.width}', (
      tester,
    ) async {
      final detail = await p06MatrixFixtures['movie_detail']!();
      final sources = await p06MatrixFixtures['play_source']!();
      await _phone(tester, detail.widget, size: size);
      final presentation = tester
          .widget<MovieDetailScreen>(find.byType(MovieDetailScreen))
          .presentation;
      await _phone(
        tester,
        Builder(
          builder: (context) => MovieDetailScreen(
            presentation: presentation,
            onPlay: () => showAppSheet<void>(context, (_) => sources.widget),
          ),
        ),
        size: size,
      );
      await tester.tap(find.text('Play').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final sheet = find.byKey(const ValueKey('app-sheet'));
      expect(sheet, findsOneWidget);
      expect(tester.getSize(sheet).height, closeTo(size.height * 0.85, 0.01));
      final surface = tester.widget<GlassSurface>(
        find.descendant(of: sheet, matching: find.byType(GlassSurface)).first,
      );
      expect(
        surface.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(22)),
      );
      await tester.timedDrag(
        find.byKey(const ValueKey('app-sheet-handle')),
        Offset(0, size.height * 0.85 * 0.31),
        const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(sheet, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await sources.dispose();
      await detail.dispose();
    });
  }

  _test('sheet follows drag and restores below dismissal thresholds', (
    tester,
  ) async {
    await _phone(
      tester,
      Builder(
        builder: (context) => AppButton.primary(
          label: 'Play',
          onActivate: () =>
              showAppSheet<void>(context, (_) => const SizedBox()),
        ),
      ),
    );
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final sheet = find.byKey(const ValueKey('app-sheet'));
    final initial = tester.getRect(sheet);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('app-sheet-handle'))),
    );
    await gesture.moveBy(
      const Offset(0, 80),
      timeStamp: const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(tester.getRect(sheet).top, greaterThan(initial.top));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(sheet), initial);
    await tester.fling(
      find.byKey(const ValueKey('app-sheet-handle')),
      const Offset(0, 80),
      1000,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sheet, findsNothing);
  });

  _test('modal source sheet keeps only its glass surface visible', (
    tester,
  ) async {
    await _phone(
      tester,
      AppShell(
        activeId: 'home',
        destinations: _destinations(
          Builder(
            builder: (context) => Center(
              child: AppButton.primary(
                label: 'Play',
                onActivate: () =>
                    showAppSheet<void>(context, (_) => const SizedBox()),
              ),
            ),
          ),
        ),
      ),
    );
    final pill = find.byKey(const ValueKey('menu-pill'));
    final search = find.byKey(const ValueKey('top-search'));
    expect(find.byType(GlassSurface), findsNWidgets(2));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(pill.hitTestable(), findsNothing);
    expect(search.hitTestable(), findsNothing);
    await tester.timedDrag(
      find.byKey(const ValueKey('app-sheet-handle')),
      const Offset(0, 680 * 0.31),
      const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('app-sheet')), findsNothing);
    expect(find.byType(GlassSurface), findsNWidgets(2));
    expect(pill.hitTestable(), findsOneWidget);
    expect(search.hitTestable(), findsOneWidget);
  });

  _test('swipe-left fling closes the phone menu panel', (tester) async {
    await _phone(
      tester,
      AppShell(activeId: 'home', destinations: _destinations(const SizedBox())),
    );
    await tester.tap(find.byKey(const ValueKey('menu-pill')));
    await tester.pump(const Duration(milliseconds: 300));
    final panel = find.byKey(const ValueKey('app-sidebar-widget'));
    expect(panel, findsOneWidget);
    await tester.fling(panel, const Offset(-100, 0), 400);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('menu-pill')).hitTestable(),
      findsOneWidget,
    );
  });

  _test('touch tap leaves the shared button in its idle color', (tester) async {
    await _phone(
      tester,
      Center(
        child: AppButton.primary(label: 'Play', onActivate: () {}),
      ),
    );
    final button = find.byType(AppButton);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 200));
    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: button,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .foregroundDecoration!
            as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });
}
