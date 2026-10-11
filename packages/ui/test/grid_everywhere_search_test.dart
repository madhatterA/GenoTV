import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

void main() {
  _finiteYearTest();
  testWidgets('search empty filters, real paging, filters and Movies/TV base', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    final calls = <(TitleQuery, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: SearchScreen(
          source: (query, page) async {
            calls.add((query, page));
            return TitlePage(
              items: [
                for (var i = 0; i < 20; i++)
                  MediaItem(
                    id: '${query.kind.name}-$page-$i',
                    title: 'Title $page $i',
                    kind: query.kind == TitleKind.movie
                        ? MediaKind.movie
                        : MediaKind.episode,
                  ),
              ],
              nextPage: page < 3 ? page + 1 : null,
            );
          },
          genresByKind: const {
            TitleKind.movie: [TitleFilterOption(28, 'Action')],
            TitleKind.tv: [TitleFilterOption(18, 'Drama')],
          },
          countries: const [TitleFilterOption('US', 'United States')],
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'alpha');
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump();
    expect(calls.first, (
      TitleQuery(
        kind: TitleKind.movie,
        base: TitleBase.search,
        searchText: 'alpha',
      ),
      1,
    ));
    expect(find.byType(PagedTitleGrid), findsOneWidget);
    expect(find.byType(FilterBar), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('media-grid')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.$2), contains(2));
    // Chips: 0 year, 1 country, 2 genre Action, 3 sort.
    await tester.tap(find.byKey(const ValueKey('filter-chip-2')));
    await tester.pumpAndSettle();
    expect(calls.last.$1.genreIds, [28]);
    expect(calls.last.$1.base, TitleBase.search);
    await tester.tap(find.byKey(const ValueKey('title-kind-tv')));
    await tester.pumpAndSettle();
    expect(calls.last.$1.kind, TitleKind.tv);
    expect(calls.last.$1.searchText, 'alpha');
    expect(
      tester.widget<FilterBar>(find.byType(FilterBar)).genres.single.value,
      18,
    );
  });
  testWidgets('mixed-case input reuses the first page', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: SearchScreen(
          source: (query, page) async {
            calls++;
            return TitlePage(
              items: [
                const MediaItem(id: 'one', title: 'One', kind: MediaKind.movie),
              ],
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'Alpha');
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump();
    expect(calls, 1);
  });
  testWidgets('stale movie response cannot replace TV after switch', (
    tester,
  ) async {
    final movie = Completer<TitlePage>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: SearchScreen(
          source: (query, page) async {
            if (query.kind == TitleKind.movie) return movie.future;
            return TitlePage(
              items: [
                const MediaItem(
                  id: 'tv',
                  title: 'TV result',
                  kind: MediaKind.episode,
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'title');
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tap(find.byKey(const ValueKey('title-kind-tv')));
    await tester.pump();
    await tester.pump();
    movie.complete(
      TitlePage(
        items: [
          const MediaItem(
            id: 'movie',
            title: 'Stale movie',
            kind: MediaKind.movie,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TV result'), findsOneWidget);
    expect(find.text('Stale movie'), findsNothing);
  });
  testWidgets('trending sorts accumulated loaded pages and preserves base', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PagedTitleGrid(
          title: 'Trending',
          initialQuery: TitleQuery(
            kind: TitleKind.movie,
            base: TitleBase.trending,
            sort: TitleSort.title,
          ),
          source: (query, page) async => TitlePage(
            items: [
              MediaItem(
                id: '$page',
                title: page == 1 ? 'Zulu' : 'Alpha',
                kind: MediaKind.movie,
              ),
            ],
            nextPage: page == 1 ? 2 : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MediaGrid>(find.byType(MediaGrid))
          .items
          .map((i) => i.title),
      ['Alpha', 'Zulu'],
    );
    expect(
      tester.widget<FilterBar>(find.byType(FilterBar)).query.base,
      TitleBase.trending,
    );
  });
}

void _finiteYearTest() {
  testWidgets(
    'finite library grid applies inclusive years and excludes unknown years',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: SearchScreen(
            search: (_) async => const [
              MediaItem(
                id: 'old',
                title: 'Old',
                kind: MediaKind.movie,
                year: 2019,
              ),
              MediaItem(
                id: 'match',
                title: 'Match',
                kind: MediaKind.movie,
                year: 2020,
              ),
              MediaItem(
                id: 'new',
                title: 'New',
                kind: MediaKind.movie,
                year: 2021,
              ),
              MediaItem(id: 'unknown', title: 'Unknown', kind: MediaKind.movie),
            ],
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'title',
      );
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      final bar = tester.widget<FilterBar>(find.byType(FilterBar));
      bar.onChanged(bar.query.copyWith(yearFrom: 2020, yearTo: 2020));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MediaGrid>(find.byType(MediaGrid))
            .items
            .map((item) => item.id),
        ['match'],
      );
    },
  );
}
