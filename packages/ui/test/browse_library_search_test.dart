import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 03 (planning/part-04-ui/chapter-02-browse/phase-03-library-search.md)
// proof file: `LibraryScreen` grids/sort/pagination + `LibrarySearchController`/
// `SearchScreen`'s race-safe grouped search. Geometry/decisions cited inline.

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

final _movies = <MediaItem>[
  MediaItem(
    id: 'm-alpha',
    title: 'Alpha',
    kind: MediaKind.movie,
    artwork: Uri.parse('https://example.invalid/search/alpha.jpg?ar=port'),
  ),
  MediaItem(
    id: 'm-about',
    title: 'About',
    kind: MediaKind.movie,
    artwork: Uri.parse('https://example.invalid/search/about.jpg?ar=port'),
  ),
];
final _episodes = <MediaItem>[
  const MediaItem(
    id: 'e-alpha',
    title: 'Alpha Episode',
    kind: MediaKind.episode,
  ),
];

/// A mapped failure code (`failure_messages.dart`), standing in for the real
/// transport error a search-provider failure would surface.
final class _FixtureSearchFailure extends AppFailure {
  const _FixtureSearchFailure()
    : super(code: 'transport.http.unreachable', message: 'fixture unreachable');
}

void main() {
  group('LibrarySearchController — threshold and debounce', () {
    test(
      '0 and 1 character never issue a request; prompt/recents only',
      () async {
        var calls = 0;
        final controller = LibrarySearchController(
          search: (_) async {
            calls++;
            return _movies;
          },
        );
        controller.updateQuery('');
        expect(controller.status, LibrarySearchStatus.prompt);
        controller.updateQuery('a');
        expect(controller.status, LibrarySearchStatus.prompt);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(calls, 0);
        controller.dispose();
      },
    );

    testWidgets('2 characters issues exactly one request after 350ms', (
      tester,
    ) async {
      // Was flaky under load with a real `Future.delayed` clock ("349ms
      // must not have fired the debounce yet" firing early/late depending
      // on scheduler jitter). `testWidgets` already runs inside
      // flutter_test's own fake-async zone, so `tester.pump(duration)`
      // advances the controller's internal debounce `Timer`
      // (search_controller.dart) deterministically without any extra
      // dependency. Same assertions, same 349ms/350ms boundary.
      var calls = 0;
      final controller = LibrarySearchController(
        search: (_) async {
          calls++;
          return _movies;
        },
      );
      controller.updateQuery('al');
      expect(controller.status, LibrarySearchStatus.loading);
      await tester.pump(const Duration(milliseconds: 349));
      expect(calls, 0, reason: '349ms must not have fired the debounce yet');
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 1, reason: '350ms+ must have fired exactly once');
      controller.dispose();
    });

    test('rapid keystrokes collapse into a single debounced search', () async {
      var calls = 0;
      final controller = LibrarySearchController(
        search: (_) async {
          calls++;
          return _movies;
        },
      );
      for (var i = 0; i < 10; i++) {
        controller.updateQuery('a' * (i + 2));
      }
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(calls, 1);
      controller.dispose();
    });
  });

  group('LibrarySearchController — race safety', () {
    test(
      'rapid A to B completion: B lands after slower A resolves last',
      () async {
        final calls = <String>[];
        final controller = LibrarySearchController(
          search: (query) async {
            calls.add(query);
            await Future<void>.delayed(
              Duration(milliseconds: query == 'aa' ? 200 : 20),
            );
            return <MediaItem>[
              MediaItem(id: query, title: query, kind: MediaKind.movie),
            ];
          },
        );
        controller.updateQuery('aa');
        await Future<void>.delayed(const Duration(milliseconds: 360));
        controller.updateQuery('bb');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(calls, <String>['aa', 'bb']);
        expect(controller.flatResults.single.id, 'bb');
        controller.dispose();
      },
    );

    test('B to A: typing back to an earlier query still re-issues with a fresh token', () async {
      final calls = <String>[];
      final controller = LibrarySearchController(
        search: (query) async {
          calls.add(query);
          return <MediaItem>[
            MediaItem(id: query, title: query, kind: MediaKind.movie),
          ];
        },
      );
      controller.updateQuery('aa');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      controller.updateQuery('bb');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      controller.updateQuery('aa');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(calls, <String>['aa', 'bb', 'aa']);
      expect(controller.flatResults.single.id, 'aa');
      controller.dispose();
    });

    test('a stale error arriving after a newer request is ignored', () async {
      final controller = LibrarySearchController(
        search: (query) async {
          if (query == 'aa') {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            throw StateError('stale failure');
          }
          return _movies;
        },
      );
      controller.updateQuery('aa');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      controller.updateQuery('bb');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(controller.status, LibrarySearchStatus.results);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('retry re-issues the current query with a fresh token', () async {
      var attempt = 0;
      final controller = LibrarySearchController(
        search: (_) async {
          attempt++;
          if (attempt == 1) throw StateError('first attempt fails');
          return _movies;
        },
      );
      controller.updateQuery('ok');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(controller.status, LibrarySearchStatus.error);
      controller.retry();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.status, LibrarySearchStatus.results);
      expect(attempt, 2);
      controller.dispose();
    });
  });

  group('LibrarySearchController — recents and grouping', () {
    test('recents dedupe and cap at 10, most-recent-first', () async {
      final controller = LibrarySearchController(search: (_) async => _movies);
      for (var i = 0; i < 12; i++) {
        controller.updateQuery('term$i');
        await Future<void>.delayed(const Duration(milliseconds: 360));
      }
      // Re-search an already-remembered term: it moves to the front rather
      // than duplicating.
      controller.updateQuery('term5');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(controller.recents.length, 10);
      expect(controller.recents.first, 'term5');
      expect(controller.recents.toSet().length, 10, reason: 'no duplicates');
      controller.dispose();
    });

    test('results group by kind with stable ordering', () async {
      final controller = LibrarySearchController(
        search: (_) async => <MediaItem>[..._episodes, ..._movies],
      );
      controller.updateQuery('alpha');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(controller.groups.map((g) => g.kind), <MediaKind>[
        MediaKind.movie,
        MediaKind.episode,
      ]);
      controller.dispose();
    });

    test('activating a recent runs immediately with no debounce', () async {
      var calls = 0;
      final controller = LibrarySearchController(
        search: (_) async {
          calls++;
          return _movies;
        },
      );
      controller.updateQuery('alpha');
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(calls, 1);
      controller.updateQuery('');
      expect(controller.status, LibrarySearchStatus.recents);
      controller.activateRecent('alpha');
      expect(controller.status, LibrarySearchStatus.loading);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        calls,
        2,
        reason: 'activating a recent must not wait for the debounce',
      );
      controller.dispose();
    });
  });

  group('SearchScreen — states and keyboard', () {
    testWidgets(
      'prompt, recents, loading, results, no-results, error are distinct',
      (tester) async {
        final controller = LibrarySearchController(
          search: (query) async {
            if (query == 'error') throw StateError('fixture');
            if (query == 'none') return const <MediaItem>[];
            return _movies;
          },
        );
        await tester.pumpWidget(
          _app(SearchScreen(search: controller.search, controller: controller)),
        );
        expect(
          find.byKey(const ValueKey<String>('search-prompt')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('search-field')),
          'ok',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('search-loading')),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 360));
        expect(
          find.byKey(const ValueKey<String>('search-results')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('search-field')),
          'none',
        );
        await tester.pump(const Duration(milliseconds: 360));
        expect(
          find.byKey(const ValueKey<String>('search-no-results')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('search-field')),
          'error',
        );
        await tester.pump(const Duration(milliseconds: 360));
        expect(
          find.byKey(const ValueKey<String>('search-error')),
          findsOneWidget,
        );

        // clearing back below 2 chars with a remembered recent shows recents.
        await tester.enterText(
          find.byKey(const ValueKey<String>('search-field')),
          '',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('search-recents')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey<String>('recent-ok')), findsOneWidget);
      },
    );

    testWidgets('arrow down enters results, arrow up returns to the field', (
      tester,
    ) async {
      final controller = LibrarySearchController(search: (_) async => _movies);
      await tester.pumpWidget(
        _app(SearchScreen(search: controller.search, controller: controller)),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'al',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('search-field')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'search-first-result',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'search-field',
      );
    });

    testWidgets('selecting a recent populates the field and runs immediately', (
      tester,
    ) async {
      final controller = LibrarySearchController(search: (_) async => _movies);
      await tester.pumpWidget(
        _app(SearchScreen(search: controller.search, controller: controller)),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'alpha',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        '',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('recent-alpha')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('recent-alpha')));
      await tester.pump();
      expect(find.text('alpha'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-results')),
        findsOneWidget,
      );
    });

    testWidgets('retry button re-runs the current query', (tester) async {
      var attempt = 0;
      final controller = LibrarySearchController(
        search: (_) async {
          attempt++;
          if (attempt == 1) throw StateError('first attempt fails');
          return _movies;
        },
      );
      await tester.pumpWidget(
        _app(SearchScreen(search: controller.search, controller: controller)),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'ok',
      );
      await tester.pump(const Duration(milliseconds: 360));
      expect(
        find.byKey(const ValueKey<String>('search-error')),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('search-results')),
        findsOneWidget,
      );
    });

    testWidgets('Movies/TV switch selects one kind in the shared grid', (
      tester,
    ) async {
      final controller = LibrarySearchController(
        search: (_) async => <MediaItem>[..._movies, ..._episodes],
      );
      await tester.pumpWidget(
        _app(SearchScreen(search: controller.search, controller: controller)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'alpha',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      expect(find.byType(PagedTitleGrid), findsOneWidget);
      expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).items, _movies);
      await tester.tap(find.byKey(const ValueKey('title-kind-tv')));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).items, _episodes);
    });

    testWidgets('five states have stable rendered evidence', (tester) async {
      final controller = LibrarySearchController(
        search: (query) async {
          // A classified failure, not a bare StateError: shows the specific
          // `failure_messages.dart` copy the real search path would surface
          // (e.g. a transport error), not the generic app.unexpected
          // fallback — matches Rivulet's `SearchCells.swift:354-360`, which
          // always passes a real message through, never a boilerplate one.
          if (query == 'error') throw const _FixtureSearchFailure();
          if (query == 'none') return const <MediaItem>[];
          return _movies;
        },
      );
      await setLogicalSize(tester, const Size(400, 800));
      // Real fixture posters, same tiles/resolver as the home shelves
      // (`browse_shelves_test.dart`) — not the network-failure placeholder.
      final resolver = await loadFixtureArtworkResolver(tester);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            SearchScreen(search: controller.search, controller: controller),
          ),
        ),
      );
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search_prompt.png'),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'ok',
      );
      await tester.pump();
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search_loading.png'),
      );

      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search_results.png'),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'none',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search_no_results.png'),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'error',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search_error.png'),
      );
    });

    testWidgets('results at 1920x1080 use the shared paged grid', (
      tester,
    ) async {
      // Desktop search uses the same column formula as other title grids.
      final manyMovies = <MediaItem>[
        for (var i = 0; i < 8; i++)
          MediaItem(
            id: 'm-row-$i',
            title: 'Row $i',
            kind: MediaKind.movie,
            artwork: Uri.parse(
              'https://example.invalid/search-row/$i.jpg?ar=port',
            ),
          ),
      ];
      final controller = LibrarySearchController(
        search: (_) async => manyMovies,
      );
      await setLogicalSize(tester, const Size(1920, 1080));
      final resolver = await loadFixtureArtworkResolver(tester);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            SearchScreen(search: controller.search, controller: controller),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'row',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      expect(find.text('Movies'), findsOneWidget);
      final tile = tester.getRect(
        find.byKey(const ValueKey<String>('grid-m-row-0')),
      );
      // 7 columns of 230 px posters on a 1920 desktop (DESIGN_SPEC §4.5); the
      // line's spare width is shared out, art stays 2:3.
      expect(tile.width, closeTo((1920 - 64 - 6 * 16) / 7, 0.5));
      expect(tile.height, greaterThan(tile.width * 1.5));
      expect(tile.left, 32.0);
      expect(find.text('Row 0'), findsOneWidget);
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search_results_1920.png'),
      );
    });
  });

  group('LibraryScreen — pagination and restoration', () {
    testWidgets(
      'onLoadMore fires once per distinct count when focus nears the tail',
      (tester) async {
        await setLogicalSize(tester, const Size(800, 3200));
        var calls = 0;
        var items = fixtureLibraryItems(count: 20);
        Future<void> pumpWith(
          List<MediaItem> current, {
          bool loading = false,
        }) => tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => LibraryScreen(
                items: current,
                scope: BrowseScope.movies,
                isLoadingMore: loading,
                onLoadMore: () => calls++,
              ),
            ),
          ),
        );
        await pumpWith(items);
        await tester.pump();
        // Focus the last realized item to enter the final-five window.
        await tester.tap(find.byKey(ValueKey<String>('grid-${items.last.id}')));
        await tester.pump();
        expect(calls, 1);
        // Re-focusing the same tail at the same item count must not re-fire.
        await tester.tap(
          find.byKey(ValueKey<String>('grid-${items[items.length - 2].id}')),
        );
        await tester.pump();
        expect(calls, 1);

        // Simulate the page landing: append more items, focus the new tail.
        items = fixtureLibraryItems(count: 30);
        await pumpWith(items);
        await tester.pump();
        await tester.tap(find.byKey(ValueKey<String>('grid-${items.last.id}')));
        await tester.pump();
        expect(calls, 2);
      },
    );

    testWidgets('a trailing loading tile renders while isLoadingMore is true', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(800, 1600));
      await tester.pumpWidget(
        _app(
          LibraryScreen(
            items: fixtureLibraryItems(count: 10),
            scope: BrowseScope.movies,
            isLoadingMore: true,
            onLoadMore: () {},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('media-grid-loading-more')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets(
      'filter, sort, and focused item survive being rebuilt in place',
      (tester) async {
        // `AppShell` keeps each destination's page mounted offstage rather
        // than disposing it on tab switch, so a `LibraryScreen` rebuilt with
        // the same widget identity (no new key) keeps its `State` — this is
        // the "destination restoration bucket" `phase-03` step 2 refers to.
        // Simulated here by rebuilding the same subtree rather than actually
        // popping a route.
        final items = fixtureLibraryItems(count: 40);
        final key = GlobalKey();
        final memory = FocusMemory();
        Widget host() => _app(
          LibraryScreen(
            key: key,
            items: items,
            scope: BrowseScope.movies,
            memory: memory,
          ),
        );
        await tester.pumpWidget(host());
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('filter-chip-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Title A–Z').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey<String>('grid-${items.first.id}')),
        );
        await tester.pump();
        expect(memory.lastFocused('library'), items.first.id);

        // Rebuild in place (same GlobalKey) — analogous to navigating away to
        // another tab and back without disposing the offstage page.
        await tester.pumpWidget(host());
        await tester.pump();
        expect(find.text('Sort: Title A–Z'), findsOneWidget);
        expect(memory.lastFocused('library'), items.first.id);
      },
    );
  });
}
