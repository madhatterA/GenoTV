import 'dart:convert';
import 'dart:io';

import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import '../support/fixture_artwork.dart';
import '../support/state_screen_registry.dart';
import '../support/surface_size.dart';

// DESIGN_SPEC §6.3 / §6.4 on a desktop profile (macOS, 1280x800). Every walk
// presses real keys and asserts the primary focus's contract key after each
// one. The hero Details, detail Trailer/Like/Cast and season chips are
// walked here; the filter chips by their phase.

final _log = <Map<String, Object?>>[];

/// The contract key of the primary focus: the first matching `ValueKey` on
/// the focus node's widget or one of its ancestors.
final _contract = RegExp(
  r'^(hero-focus-play|hero-focus-details|row-\d+-(item-\d+|see-all|arrow-left|arrow-right)|'
  r'menu-pill|menu-item-.+|top-search|top-back|grid-item-\d+|'
  r'detail-play-action|detail-trailer|detail-like|detail-watched-action|'
  r'detail-watchlist-action|detail-info-action|people-item-\d+|'
  r'detail-related-item-\d+|detail-trailers-item-\d+|season-chip-\d+|'
  r'episode-\d+|library-query|library-refresh|'
  r'section-.+|setting-.+|skip-forward-setting|verbose-logging-switch|'
  r'advanced-toggle|expert-toggle|search-field|'
  r'filter-chip-\d+|title-kind-.+)$',
);

String? _focusedKey() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  void check(Element element) {
    final key = element.widget.key;
    if (found == null &&
        key is ValueKey<String> &&
        _contract.hasMatch(key.value)) {
      found = key.value;
    }
  }

  check(context as Element);
  context.visitAncestorElements((ancestor) {
    check(ancestor);
    return found == null;
  });
  return found;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int times = 1,
}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

void _expectKey(String walk, String step, String expected) {
  final actual = _focusedKey();
  _log.add(<String, Object?>{
    'walk': walk,
    'step': step,
    'expected': expected,
    'actual': actual,
    'pass': actual == expected,
  });
  expect(actual, expected, reason: '$walk / $step');
}

AppDestination _destination(String id, String label, WidgetBuilder builder) =>
    AppDestination(
      id: id,
      label: label,
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
      builder: builder,
    );

/// A shell whose first destination ("start") is a lone button, so the test
/// can switch the app to keyboard mode and then enter the destination under
/// test through the menu (the only way a page is "entered" from the keyboard).
class _Harness {
  _Harness(this.tester, this.pages);

  final WidgetTester tester;
  final Map<String, WidgetBuilder> pages;

  Future<void> pump() async {
    await setLogicalSize(tester, const Size(1280, 800));
    final resolver = await loadFixtureArtworkResolver(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(tv: false),
        home: AdaptiveBehavior(
          capabilities: const PlatformCapabilities(),
          child: ArtworkResolverScope(
            resolver: resolver,
            child: AppShell(
              activeId: 'start',
              destinations: <AppDestination>[
                _destination(
                  'start',
                  'Start',
                  (_) => const Center(
                    child: TextButton(
                      autofocus: true,
                      onPressed: null,
                      child: Text('start'),
                    ),
                  ),
                ),
                for (final entry in pages.entries)
                  _destination(entry.key, entry.key, entry.value),
                if (!pages.containsKey('search'))
                  _destination('search', 'search', (_) => const SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Keyboard mode, then Start -> menu -> [id] with the keys a user presses.
  Future<void> enter(String id) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.keyM);
    for (var i = 0; i < 12 && _focusedKey() != 'menu-item-$id'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focusedKey(), 'menu-item-$id');
    await _press(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey<String>(key)).first);

void main() {
  tearDownAll(() {
    final dir = Directory.systemTemp.createTempSync('desktop-keywalk-');
    try {
      File('${dir.path}/keywalk_steps.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_log));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('Home walk', (tester) async {
    final model = HomeViewModel(
      rows: keywalkHomeRows(),
      firstDeferredSectionReady: true,
      secondDeferredSectionReady: true,
    );
    addTearDown(model.dispose);
    final harness = _Harness(tester, <String, WidgetBuilder>{
      'home': (_) =>
          HomeScreen(viewModel: model, onItemTap: (_) {}, onSeeAll: (_) {}),
    });
    await harness.pump();
    await harness.enter('home');
    const w = 'home';

    _expectKey(w, '0 entry', 'hero-focus-play');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '1 Right to Details', 'hero-focus-details');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(
      w,
      '2 Right stays (desktop: no slide change)',
      'hero-focus-details',
    );
    expect(model.hero, model.heroItems.first, reason: 'no slide change');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '3 Down', 'row-0-item-0');
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    _expectKey(w, '4 Right x2', 'row-0-item-2');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '5 Right to the end card', 'row-0-see-all');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '5 Right stays on the end card', 'row-0-see-all');

    // 6: nearest item of row 1 by centre x.
    final fromX = _rect(tester, 'row-0-see-all').center.dx;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final landed = _focusedKey()!;
    expect(landed, startsWith('row-1-item-'));
    var nearest = '';
    var best = double.infinity;
    for (var i = 0; i < 8; i++) {
      final finder = find.byKey(ValueKey<String>('row-1-item-$i'));
      if (finder.evaluate().isEmpty) continue;
      final d = (tester.getRect(finder.first).center.dx - fromX).abs();
      if (d < best) {
        best = d;
        nearest = 'row-1-item-$i';
      }
    }
    _expectKey(w, '6 Down lands on the nearest item', nearest);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '7 Up returns to the row memory', 'row-0-see-all');
    await _press(tester, LogicalKeyboardKey.arrowLeft, times: 2);
    _expectKey(w, '8 Left x2', 'row-0-item-1');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '9 Up to the hero', 'hero-focus-play');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '10 Up to the pill', 'menu-pill');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '11 Right', 'top-search');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.enter);
    _expectKey(w, '12 Left, Enter opens the panel', 'menu-item-home');
    expect(find.byKey(const ValueKey<String>('menu-panel')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.escape);
    _expectKey(w, '13 Escape closes the panel', 'menu-pill');
    expect(find.byKey(const ValueKey<String>('menu-panel')), findsNothing);
    await _press(tester, LogicalKeyboardKey.keyM);
    _expectKey(w, '14 M opens the panel', 'menu-item-home');
    await _press(tester, LogicalKeyboardKey.escape);
    _expectKey(w, '14 Escape', 'menu-pill');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '15 Down', 'hero-focus-play');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.tab);
    _expectKey(w, '16 Tab', 'top-search');
    await _press(tester, LogicalKeyboardKey.tab);
    _expectKey(w, '16 Tab', 'hero-focus-play');
    await _press(tester, LogicalKeyboardKey.tab);
    _expectKey(w, '16 Tab', 'hero-focus-details');
    await _press(tester, LogicalKeyboardKey.arrowLeft);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    _expectKey(w, '17 reach row 1 (memory)', nearest);
    final index = int.parse(nearest.split('-').last);
    await _press(tester, LogicalKeyboardKey.arrowLeft, times: index);
    _expectKey(w, '17 Left to the first item', 'row-1-item-0');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectKey(w, '17 Left stays', 'row-1-item-0');
  });

  testWidgets('Movies grid walk', (tester) async {
    final items = fixtureLibraryItems(count: 24);
    final harness = _Harness(tester, <String, WidgetBuilder>{
      'movies': (context) => LibraryScreen(
        items: items,
        scope: BrowseScope.movies,
        onItemTap: (_) => pushAndRestoreFocus<void>(
          Navigator.of(context),
          AppPageRoute<void>(
            builder: (_) => const Material(
              child: PopOnEscape(
                child: Center(
                  child: TextButton(
                    autofocus: true,
                    onPressed: _noop,
                    child: Text('opened'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    });
    await harness.pump();
    await harness.enter('movies');
    const w = 'movies';
    const columns = 7; // §4.5: floor((1280 - 64 + 16) / (160 + 16))

    _expectKey(w, '0 entry', 'grid-item-0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '1 Right', 'grid-item-1');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '2 Down keeps the column', 'grid-item-${1 + columns}');
    await _press(tester, LogicalKeyboardKey.arrowRight, times: columns);
    _expectKey(
      w,
      '3 Right stops at the line end',
      'grid-item-${2 * columns - 1}',
    );
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '3 Right stays', 'grid-item-${2 * columns - 1}');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '3 Down keeps the column', 'grid-item-${3 * columns - 1}');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '3 Up keeps the column', 'grid-item-${columns - 1}');

    // 4: Up from a column to the right of the chips lands on the title
    // search, which spans the page width above the chip bar.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '4 Up lands on the title search', 'library-query');
    for (var i = 0; i < 4 && _focusedKey() != 'menu-pill'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    _expectKey(w, '5 Up reaches the pill', 'menu-pill');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '5 Down returns to the first poster', 'grid-item-0');

    // 6: the chip bar (§8.2): Up from the first poster lands on the first chip,
    // Left/Right walk the chips (no wrap), Down returns to the first poster.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '6 Up lands on the first chip', 'filter-chip-0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '6 Right to the next chip', 'filter-chip-1');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '6 Right stays on the last chip', 'filter-chip-1');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectKey(w, '6 Left to the first chip', 'filter-chip-0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '6 Down returns to the first poster', 'grid-item-0');

    await _press(tester, LogicalKeyboardKey.enter);
    expect(find.text('opened'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('opened'), findsNothing);
    _expectKey(w, '7 Escape restores the opener', 'grid-item-0');
    _expectClickCursors(tester);
  });

  testWidgets('Movie detail walk', (tester) async {
    final model = HomeViewModel(
      rows: keywalkHomeRows(),
      firstDeferredSectionReady: true,
      secondDeferredSectionReady: true,
    );
    addTearDown(model.dispose);
    final harness = _Harness(tester, <String, WidgetBuilder>{
      'home': (context) => HomeScreen(
        viewModel: model,
        onSeeAll: (_) {},
        onItemTap: (item) => pushAndRestoreFocus<void>(
          Navigator.of(context),
          AppPageRoute<void>(
            builder: (_) => Material(
              child: FavouritesScope(
                repository: FakeFavouritesRepository(),
                child: MovieDetailScreen(
                  presentation: keywalkMoviePresentation(item),
                  onPlay: () {},
                  onToggleWatched: () {},
                  onInfo: () {},
                  onRelatedTap: (_) {},
                  onTrailerTap: (_) {},
                  onCastTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    });
    await harness.pump();
    await harness.enter('home');
    const w = 'movie detail';
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    _expectKey(w, 'open from', 'row-1-item-3');
    await _press(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    _expectKey(w, '0 entry', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '1 Right to Trailer', 'detail-trailer');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '2 Right to Like', 'detail-like');
    await _press(tester, LogicalKeyboardKey.arrowLeft, times: 2);
    _expectKey(w, '3 Left Left back to Play', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '4 Down to the first person', 'people-item-0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '5 Right along Cast', 'people-item-1');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '6 Down to More like this', 'detail-related-item-0');
    await _press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    _expectKey(w, '7 Up twice reaches the action row', 'detail-trailer');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectKey(w, '7b Left to Play', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '8 Up to Back', 'top-back');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '9 Right to the pill', 'menu-pill');
    _expectClickCursors(tester);
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    _expectKey(w, '10 Escape pops and restores the opener', 'row-1-item-3');
  });

  testWidgets('Series detail walk', (tester) async {
    final series = SeriesViewModel(seasons: fixtureSeriesSeasons());
    addTearDown(series.dispose);
    final harness = _Harness(tester, <String, WidgetBuilder>{
      'series': (_) => SeriesDetailScreen(
        presentation: fixtureSeriesPresentation(),
        viewModel: series,
        onPlay: (_) {},
      ),
    });
    await harness.pump();
    await harness.enter('series');
    const w = 'series detail';
    _expectKey(w, '0 entry', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '1 Down enters on the selected chip', 'season-chip-0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '2 Right to the next chip', 'season-chip-1');
    await _press(tester, LogicalKeyboardKey.enter);
    expect(series.selectedSeason, 2);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '3 Down to the first episode', 'episode-0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '4 Down along the episodes', 'episode-1');
    await _press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    _expectKey(w, '5 Up back to the chips', 'season-chip-3');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '6 Up to Play', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '7 Up to Back', 'top-back');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '8 Right to the pill', 'menu-pill');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '9 Down back to Play', 'detail-play-action');
  });

  testWidgets('Settings walk', (tester) async {
    final settings = AppSettings(MemorySettingsStore());
    final harness = _Harness(tester, <String, WidgetBuilder>{
      'settings': (_) => SettingsScreen(
        settings: settings,
        capabilities: keywalkCapabilityReport(),
        available: const <SettingCapability>{},
      ),
    });
    await harness.pump();
    await harness.enter('settings');
    const w = 'settings';
    final sectionKeys = <String>[
      for (final e
          in find
              .byWidgetPredicate(
                (x) =>
                    x.key is ValueKey<String> &&
                    (x.key! as ValueKey<String>).value.startsWith('section-'),
              )
              .evaluate())
        (e.widget.key! as ValueKey<String>).value,
    ]..sort((a, b) => _rect(tester, a).top.compareTo(_rect(tester, b).top));
    expect(sectionKeys.length, greaterThan(1));
    final first = sectionKeys.first;
    final sections = sectionKeys.length;
    _expectKey(w, '0 entry', first);
    await _press(tester, LogicalKeyboardKey.arrowDown, times: sections);
    _expectKey(w, '1 Down past the sections', 'setting-app.language');
    await _press(tester, LogicalKeyboardKey.arrowUp, times: sections);
    _expectKey(w, '2 Up back to the first section', first);
    await _press(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final focused = _focusedKey();
    _log.add(<String, Object?>{
      'walk': w,
      'step': '3 Enter opens the section page, focus on its first row',
      'expected': 'a row of the section page',
      'actual': focused,
      'pass': focused != null && !focused.startsWith('section-'),
    });
    expect(focused, isNotNull);
    expect(focused, isNot(startsWith('section-')));
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    _expectKey(w, '4 Escape returns to the section list', first);
    _expectClickCursors(tester);
  });

  testWidgets('Search walk', (tester) async {
    final controller = LibrarySearchController(
      search: (_) async => fixtureLibraryItems(count: 24),
    );
    addTearDown(controller.dispose);
    final harness = _Harness(tester, <String, WidgetBuilder>{
      'search': (_) => SearchScreen(
        search: controller.search,
        controller: controller,
        onItemTap: (_) {},
      ),
    });
    await harness.pump();
    await harness.enter('search');
    const w = 'search';
    _expectKey(w, '0 entry', 'search-field');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '1 Up from the field to the pill', 'menu-pill');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    // The rest of the word reaches the now focused field as text input.
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-field')),
      'abc',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    _expectKey(w, '2 typing moves focus into the field', 'search-field');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'abc',
    );
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '3 Down to the first result', 'grid-item-0');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '4 Up back to the field', 'search-field');
    _expectClickCursors(tester);
  });

  group('mouse', () {
    Future<void> pumpHome(WidgetTester tester) async {
      final model = HomeViewModel(
        rows: keywalkHomeRows(),
        firstDeferredSectionReady: true,
        secondDeferredSectionReady: true,
      );
      addTearDown(model.dispose);
      final harness = _Harness(tester, <String, WidgetBuilder>{
        'home': (_) =>
            HomeScreen(viewModel: model, onItemTap: (_) {}, onSeeAll: (_) {}),
      });
      await harness.pump();
      tester.view.physicalSize = const Size(1280, 1500);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      expect(shell.activeId, 'start');
      // Select Home with the mouse, which keeps the pointer profile.
      await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('menu-item-home')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }

    testWidgets('hover, row arrows, right-click, cursors, no ring', (
      tester,
    ) async {
      await pumpHome(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      addTearDown(mouse.removePointer);

      final poster = find.byKey(const ValueKey<String>('row-1-item-0'));
      double scaleOf(Finder f) => tester
          .widget<ScaleTransition>(
            find
                .descendant(of: f, matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
          .value;
      expect(scaleOf(poster), 1.0);
      await mouse.moveTo(tester.getCenter(poster));
      // The first frame switches the app to pointer mode, the next one starts
      // the 120 ms scale.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(scaleOf(poster), closeTo(1.03, 0.001));
      _log.add(<String, Object?>{
        'walk': 'mouse',
        'step': 'poster hover scale',
        'expected': 1.03,
        'actual': scaleOf(poster),
        'pass': true,
      });

      // A button's background turns tintFillHover on hover.
      final search = find.byKey(const ValueKey<String>('top-search'));
      Color? fillOf() => tester
          .widget<AnimatedContainer>(
            find
                .descendant(
                  of: search,
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .foregroundDecoration
          ?.let((d) => (d as BoxDecoration).color);
      expect(fillOf(), Colors.transparent);
      await mouse.moveTo(tester.getCenter(search));
      await tester.pump(const Duration(milliseconds: 200));
      final hoverFill = RivuletTokens.of(tester.element(search))
          .colors
          .tintFillHover;
      expect(fillOf(), hoverFill);

      // Clicking a card focuses it but paints no ring in pointer mode.
      await tester.tapAt(
        tester.getCenter(poster),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.foregroundPainter is FocusRingPainter,
        ),
        findsNothing,
      );

      // Right-click opens the media context menu at the pointer.
      final at = tester.getCenter(poster);
      await tester.tapAt(
        at,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      // The hero has a Details button too; the menu's is inside its glass.
      final menuDetails = find.descendant(
        of: find.byType(GlassSurface),
        matching: find.text('Details'),
      );
      expect(menuDetails, findsOneWidget);
      final menu = tester.getTopLeft(
        find
            .ancestor(of: menuDetails, matching: find.byType(GlassSurface))
            .first,
      );
      expect((menu - at).distance, lessThan(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menuDetails, findsNothing);

      // Hovering row 1 shows the right arrow; clicking pages the row.
      final row = find.byWidgetPredicate(
        (w) => w is MediaRow && w.rowIndex == 1,
      );
      await mouse.moveTo(tester.getCenter(poster));
      await tester.pump();
      final right = find.byKey(const ValueKey<String>('row-1-arrow-right'));
      expect(right, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('row-1-arrow-left')),
        findsNothing,
      );
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: row, matching: find.byType(Scrollable)).first,
          )
          .position;
      final viewport = tester.getSize(row).width;
      final posterWidth = tester.getSize(poster).width;
      await tester.tapAt(
        tester.getCenter(right),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final expected = (viewport - posterWidth).clamp(
        0.0,
        position.maxScrollExtent,
      );
      expect(position.pixels, closeTo(expected, 1));
      await mouse.moveTo(tester.getCenter(row));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('row-1-arrow-left')),
        findsOneWidget,
      );

      _expectClickCursors(tester);
    });
  });
}

void _noop() {}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Every `FocusableAction` / `FocusableCard` on screen has a click cursor.
void _expectClickCursors(WidgetTester tester) {
  final interactive = <Finder>[
    find.byType(FocusableAction),
    find.byType(FocusableCard),
  ];
  var checked = 0;
  for (final finder in interactive) {
    for (final element in finder.evaluate()) {
      final regions = find
          .descendant(
            of: find.byElementPredicate((e) => e == element),
            matching: find.byType(MouseRegion),
          )
          .evaluate()
          .map((e) => (e.widget as MouseRegion).cursor);
      expect(
        regions.contains(SystemMouseCursors.click),
        isTrue,
        reason: '${element.widget} has no click cursor',
      );
      checked++;
    }
  }
  expect(checked, greaterThan(0));
}
