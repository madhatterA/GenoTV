import 'dart:async';

import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/state_screen_registry.dart' show browseGridItems;

// Part 06 ch03 p02: Movies / TV shows / Liked, Genres, Search (DESIGN_SPEC
// §8.2-§8.4, §9.8). Column formula, lazy grid, chip bar, search field and the
// browse goldens.

/// [testWidgets] that restores the platform override before the framework's
/// invariant check, even when the body fails.
void _test(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

typedef _Factor = ({
  Size size,
  double dpr,
  bool tv,
  FormFactor formFactor,
  PlatformCapabilities caps,
});

const Map<String, _Factor> _factors = <String, _Factor>{
  'phone': (
    size: Size(400, 800),
    dpr: 1,
    tv: false,
    formFactor: FormFactor.phone,
    caps: PlatformCapabilities.touch(),
  ),
  'desktop': (
    size: Size(1280, 800),
    dpr: 1,
    tv: false,
    formFactor: FormFactor.desktop,
    caps: PlatformCapabilities(),
  ),
  'tv': (
    size: Size(960, 540),
    dpr: 2,
    tv: true,
    formFactor: FormFactor.tv,
    caps: PlatformCapabilities.directionalPad(),
  ),
};

const _root = ValueKey<String>('p06-browse');

/// Pumps [home] in the matrix harness of `p06_screen_matrix_test.dart`; the
/// golden boundary wraps the whole app so dialogs are in the picture.
Future<void> _pump(
  WidgetTester tester,
  String factor,
  Widget home, {
  Size? size,
}) async {
  final spec = _factors[factor]!;
  debugDefaultTargetPlatformOverride = factor == 'desktop'
      ? TargetPlatform.macOS
      : TargetPlatform.android;
  tester.view.physicalSize = (size ?? spec.size) * spec.dpr;
  tester.view.devicePixelRatio = spec.dpr;
  addTearDown(tester.view.reset);
  final artwork = await loadFixtureArtworkResolver(tester);
  await tester.pumpWidget(
    ArtworkResolverScope(
      resolver: artwork,
      child: RepaintBoundary(
        key: _root,
        child: MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(tv: spec.tv),
          home: AdaptiveBehavior(
            capabilities: spec.caps,
            child: Scaffold(backgroundColor: Colors.transparent, body: home),
          ),
        ),
      ),
    ),
  );
}

Future<void> _golden(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byKey(_root),
    matchesGoldenFile('goldens/p06/$name.png'),
  );
}

Widget _movies({List<MediaItem>? items, TitlePageSource? source}) =>
    LibraryScreen(
      items: items ?? browseGridItems(),
      scope: BrowseScope.movies,
      genres: const [TitleFilterOption(28, 'Action')],
      countries: const [TitleFilterOption('US', 'United States')],
      source: source,
      onItemTap: (_) {},
    );

Widget _liked({required bool empty}) => PagedTitleGrid(
  source: (_, _) async =>
      TitlePage(items: empty ? const [] : browseGridItems(count: 8)),
  initialQuery: TitleQuery(kind: TitleKind.movie),
  title: 'Liked',
  showFilters: false,
  autofocus: false,
  empty: EmptyView(
    icon: PhosphorIconsRegular.heart,
    headline: 'No liked titles yet',
    body: 'Titles you like appear here.',
    primaryLabel: 'Browse movies',
    onPrimary: () {},
  ),
);

Finder _chip(int i) => find.byKey(ValueKey<String>('filter-chip-$i'));

/// Distinct left edges of the cards on the first line of the grid.
int _firstLineColumns(WidgetTester tester) {
  final cards = find.byType(FocusableCard).evaluate().map((e) => e.widget);
  final tops = <double>{};
  final lefts = <double>{};
  final first = tester.getTopLeft(find.byKey(const ValueKey('grid-item-0')));
  for (final widget in cards) {
    final key = (widget as FocusableCard).focusKey;
    final rect = tester.getTopLeft(find.byKey(key!));
    tops.add(rect.dy);
    if ((rect.dy - first.dy).abs() < 1) lefts.add(rect.dx);
  }
  return lefts.length;
}

void main() {
  group('grid columns', () {
    // floor((width - 2*gutter + gap) / (posterWidth + gap)), min 2 (§4.5).
    const table = <(String, double, int)>[
      ('phone', 360, 2),
      ('phone', 400, 3),
      ('desktop', 800, 4),
      ('desktop', 1280, 7),
      ('desktop', 1920, 7),
      ('tv', 960, 5),
    ];
    for (final (factor, width, columns) in table) {
      test('$factor $width -> $columns', () {
        final sizes = RivuletSizes.of(
          _factors[factor]!.formFactor,
          Size(width, 800),
        );
        expect(sizes.gridColumns, columns);
      });
    }

    for (final (factor, width, columns) in table) {
      _test('the grid lays out $columns columns at $factor $width', (
        tester,
      ) async {
        await _pump(
          tester,
          factor,
          _movies(items: browseGridItems(count: 60)),
          size: Size(width, 800),
        );
        await tester.pump();
        expect(_firstLineColumns(tester), columns);
      });
    }
  });

  group('grid', () {
    _test('is lazy: a 2000 title library builds a few dozen cards', (
      tester,
    ) async {
      await _pump(tester, 'desktop', _movies(items: fixtureLibraryItems()));
      await tester.pump();
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.byType(FocusableCard).evaluate().length, lessThan(60));
    });

    _test('next page: OrbLoader.small sits under the last line', (
      tester,
    ) async {
      await _pump(
        tester,
        'phone',
        LibraryScreen(
          items: browseGridItems(count: 6),
          scope: BrowseScope.movies,
          isLoadingMore: true,
          onLoadMore: () {},
        ),
      );
      await tester.pump();
      final loader = find.byKey(const ValueKey('media-grid-loading-more'));
      expect(tester.widget<OrbLoader>(loader).size, 24);
      final lastCard = tester.getRect(
        find.byKey(const ValueKey('grid-item-5')),
      );
      expect(tester.getTopLeft(loader).dy, greaterThan(lastCard.bottom));
      expect(
        tester.getCenter(loader).dx,
        closeTo(tester.view.physicalSize.width / 2, 1),
      );
      await tester.pump(const Duration(milliseconds: 1));
    });

    _test('first page: a Skeletonizer grid of 12 placeholder cards', (
      tester,
    ) async {
      final pending = Completer<TitlePage>();
      await _pump(
        tester,
        'phone',
        PagedTitleGrid(
          source: (_, _) => pending.future,
          initialQuery: TitleQuery(kind: TitleKind.movie),
          title: 'Movies',
        ),
        // Tall enough that the lazy grid builds all 12 placeholders.
        size: const Size(390, 2400),
      );
      await tester.pump();
      expect(find.byType(MediaGridSkeleton), findsOneWidget);
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      expect(find.byType(PosterCard), findsNWidgets(12));
      pending.complete(TitlePage(items: browseGridItems(count: 4)));
      await tester.pumpAndSettle();
      expect(find.byType(MediaGridSkeleton), findsNothing);
      expect(find.byType(PosterCard), findsNWidgets(4));
    });
  });

  group('filter bar', () {
    _test('is a horizontally scrolling row of AppChips, sort last', (
      tester,
    ) async {
      await _pump(tester, 'phone', _movies());
      await tester.pump();
      final scroll = find.descendant(
        of: find.byType(FilterBar),
        matching: find.byType(SingleChildScrollView),
      );
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
      final chips = tester.widgetList<AppChip>(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.byType(AppChip),
        ),
      );
      // Year, country, one genre, sort.
      expect(chips.length, 4);
      expect(chips.last.icon, PhosphorIconsRegular.sortAscending);
      expect(chips.last.label, 'Sort: Popularity');
    });

    _test('a selected chip is an accent fill', (tester) async {
      await _pump(
        tester,
        'phone',
        LibraryScreen(
          items: browseGridItems(),
          scope: BrowseScope.movies,
          genres: const [TitleFilterOption(28, 'Action')],
          initialQuery: TitleQuery(kind: TitleKind.movie, genreIds: const [28]),
        ),
      );
      await tester.pump();
      final accent = AppTheme.dark(tv: false)
          .extension<RivuletTokens>()!
          .colors
          .accent;
      Color? fill(Finder chip) => tester
          .widgetList<DecoratedBox>(
            find.descendant(of: chip, matching: find.byType(DecoratedBox)),
          )
          .map((box) => (box.decoration as BoxDecoration).color)
          .firstWhere((color) => color == accent, orElse: () => null);
      expect(fill(_chip(1)), accent, reason: 'Action is selected');
      expect(fill(_chip(0)), isNull, reason: 'Any year is not');
    });
  });

  group('restored controls (ruling ch03 p02)', () {
    _test('Genres keeps its genre search above the tiles', (tester) async {
      await _pump(
        tester,
        'desktop',
        GenresPage(
          genresByKind: const {
            TitleKind.movie: [
              TitleFilterOption(1, 'Action'),
              TitleFilterOption(2, 'Drama'),
            ],
            TitleKind.tv: [],
          },
          onSeeAll: (_, _) {},
        ),
      );
      await tester.pump();
      final field = tester.getTopLeft(
        find.byKey(const ValueKey('genres-search')),
      );
      final tile = tester.getTopLeft(
        find.byKey(const ValueKey('genre-tile-Action')),
      );
      expect(field.dy, lessThan(tile.dy));
      await tester.enterText(
        find.byKey(const ValueKey('genres-search')),
        'dra',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('genre-tile-Action')), findsNothing);
      expect(find.byKey(const ValueKey('genre-tile-Drama')), findsOneWidget);
    });

    _test('Movies local mode keeps its title search above the chip bar', (
      tester,
    ) async {
      await _pump(tester, 'desktop', _movies());
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('library-query'))).dy,
        lessThan(tester.getTopLeft(_chip(0)).dy),
      );
      await tester.enterText(
        find.byKey(const ValueKey('library-query')),
        'Midnight',
      );
      await tester.pump();
      expect(find.byType(PosterCard), findsOneWidget);
    });

    _test('Clear chip shows only while a filter is active and clears all', (
      tester,
    ) async {
      var query = TitleQuery(kind: TitleKind.movie);
      late StateSetter set;
      await _pump(
        tester,
        'desktop',
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return FilterBar(
              query: query,
              genres: const [TitleFilterOption(28, 'Action')],
              onChanged: (q) => set(() => query = q),
            );
          },
        ),
      );
      await tester.pump();
      expect(find.text('Clear'), findsNothing);
      // 0 year, 1 Action, 2 sort.
      await tester.tap(_chip(1));
      await tester.pump();
      expect(query.genreIds, [28]);
      final clear = find.widgetWithText(AppChip, 'Clear');
      expect(clear, findsOneWidget);
      expect(tester.widget<AppChip>(clear).icon, PhosphorIconsRegular.x);
      expect(
        tester.getTopLeft(clear).dx,
        lessThan(tester.getTopLeft(find.textContaining('Sort:')).dx),
      );
      await tester.tap(clear);
      await tester.pump();
      expect(query.genreIds, isEmpty);
      expect(find.text('Clear'), findsNothing);
    });
  });

  group('search', () {
    LibrarySearchController controller(List<String> calls) =>
        LibrarySearchController(
          search: (text) async {
            calls.add(text);
            return browseGridItems(count: 1, worstCase: true);
          },
        );

    _test('AppTextField with a clear button; typing uses the controller '
        'debounce', (tester) async {
      final calls = <String>[];
      final search = controller(calls);
      addTearDown(search.dispose);
      await _pump(
        tester,
        'desktop',
        SearchScreen(search: search.search, controller: search),
      );
      await tester.pump();
      expect(find.byType(AppTextField), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.x), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'ماتریکس',
      );
      await tester.pump(const Duration(milliseconds: 349));
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(calls, ['ماتریکس']);
      expect(find.byIcon(PhosphorIconsRegular.x), findsOneWidget);
      await tester.tap(find.byIcon(PhosphorIconsRegular.x));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('search-field')))
            .controller!
            .text,
        isEmpty,
      );
    });

    _test('the field is full width on a phone and 720 centred on desktop', (
      tester,
    ) async {
      final search = controller([]);
      addTearDown(search.dispose);
      await _pump(
        tester,
        'phone',
        SearchScreen(search: search.search, controller: search),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(AppTextField)).width, 400 - 2 * 16);
      await _pump(
        tester,
        'desktop',
        SearchScreen(search: search.search, controller: search),
        size: const Size(1280, 800),
      );
      await tester.pump();
      final field = tester.getRect(find.byType(AppTextField));
      expect(field.width, 720);
      expect(field.center.dx, closeTo(640, 0.5));
    });

    _test('worst case: a Persian query and one result lay out', (tester) async {
      final search = controller([]);
      addTearDown(search.dispose);
      await _pump(
        tester,
        'phone',
        SearchScreen(search: search.search, controller: search),
      );
      search.activateRecent('ماتریکس');
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(PosterCard), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('search-field')))
            .controller!
            .text,
        'ماتریکس',
      );
    });
  });

  group('goldens', () {
    _test('liked_empty phone', (tester) async {
      await _pump(tester, 'phone', _liked(empty: true));
      await tester.pump();
      await _golden(tester, 'liked_empty_phone');
    });
    _test('liked_empty desktop', (tester) async {
      await _pump(tester, 'desktop', _liked(empty: true));
      await tester.pump();
      await _golden(tester, 'liked_empty_desktop');
    });
    _test('liked_empty tv', (tester) async {
      await _pump(tester, 'tv', _liked(empty: true));
      await tester.pump();
      await _golden(tester, 'liked_empty_tv');
    });

    for (final factor in ['phone', 'desktop']) {
      _test('search_no_results $factor', (tester) async {
        final search = LibrarySearchController(search: (_) async => []);
        addTearDown(search.dispose);
        await _pump(
          tester,
          factor,
          SearchScreen(search: search.search, controller: search),
        );
        search.activateRecent('zzzz');
        await tester.pump();
        await tester.pump();
        await _golden(tester, 'search_no_results_$factor');
      });
    }

    _test('movies_filters_open desktop: the year dialog', (tester) async {
      await _pump(tester, 'desktop', _movies());
      await tester.pump();
      await tester.tap(_chip(0));
      await tester.pumpAndSettle();
      await _golden(tester, 'movies_filters_open_desktop');
    });

    _test('movies_worst_case phone', (tester) async {
      await _pump(
        tester,
        'phone',
        _movies(items: browseGridItems(worstCase: true)),
      );
      await tester.pump();
      await _golden(tester, 'movies_worst_case_phone');
    });
  });
}
