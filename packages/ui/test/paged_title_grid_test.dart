import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

MediaItem item(int id) =>
    MediaItem(id: '$id', title: 'Title $id', kind: MediaKind.movie);
Widget host(TitlePageSource source) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: PagedTitleGrid(
    title: 'Movies',
    source: source,
    initialQuery: TitleQuery(kind: TitleKind.movie),
    genres: const [TitleFilterOption(28, 'Action')],
    countries: const [TitleFilterOption('US', 'United States')],
  ),
);
void main() {
  testWidgets('library source uses shared grid and selected query', (
    tester,
  ) async {
    final query = TitleQuery(kind: TitleKind.tv, genreIds: [18]);
    final calls = <(TitleQuery, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: LibraryScreen(
          items: const [],
          scope: BrowseScope.series,
          initialQuery: query,
          source: (q, p) async {
            calls.add((q, p));
            return TitlePage(items: [item(7)]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PagedTitleGrid), findsOneWidget);
    expect(calls, [(query, 1)]);
  });

  testWidgets('underfilled pages continue without mouse scroll', (
    tester,
  ) async {
    final calls = <int>[];
    await tester.pumpWidget(
      host((q, p) async {
        calls.add(p);
        return TitlePage(items: [item(p)], nextPage: p < 3 ? p + 1 : null);
      }),
    );
    await tester.pumpAndSettle();
    expect(calls, [1, 2, 3]);
    expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).items.length, 3);
  });
  testWidgets('each filter and sort resets page one with exact query', (
    tester,
  ) async {
    final calls = <(TitleQuery, int)>[];
    await tester.pumpWidget(
      host((q, p) async {
        calls.add((q, p));
        return TitlePage(items: List.generate(20, item));
      }),
    );
    await tester.pumpAndSettle();
    var q = TitleQuery(kind: TitleKind.movie);
    for (final next in [
      q.copyWith(countryCode: 'US'),
      q.copyWith(yearFrom: 1990, yearTo: 2020),
      q.copyWith(genreIds: [28]),
      q.copyWith(sort: TitleSort.title),
    ]) {
      tester.widget<FilterBar>(find.byType(FilterBar)).onChanged(next);
      await tester.pumpAndSettle();
      expect(calls.last, (next, 1));
    }
    expect(calls.length, 5);
  });
  testWidgets('search sorts all loaded pages together', (tester) async {
    final query = TitleQuery(
      kind: TitleKind.movie,
      base: TitleBase.search,
      searchText: 'Title',
      sort: TitleSort.title,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PagedTitleGrid(
          title: 'Search',
          initialQuery: query,
          source: (q, p) async => TitlePage(
            items: [item(p == 1 ? 9 : 1)],
            nextPage: p == 1 ? 2 : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MediaGrid>(find.byType(MediaGrid)).items.map((i) => i.id),
      ['1', '9'],
    );
  });
  test('query validates and keeps genres immutable', () {
    final ids = [28, 18];
    final q = TitleQuery(kind: TitleKind.movie, genreIds: ids);
    ids.add(1);
    expect(q.genreIds, [18, 28]);
    final countries = ['US'];
    final metadata = TitleMetadata(genreIds: ids, countryCodes: countries);
    countries.add('GB');
    ids.add(99);
    expect(metadata.countryCodes, ['US']);
    expect(metadata.genreIds, [28, 18, 1]);
    expect(() => metadata.countryCodes.add('FR'), throwsUnsupportedError);
    expect(() => q.genreIds.add(1), throwsUnsupportedError);
    expect(
      () => TitleQuery(kind: TitleKind.tv, base: TitleBase.person),
      throwsArgumentError,
    );
    expect(
      () => TitleQuery(
        kind: TitleKind.tv,
        base: TitleBase.search,
        searchText: ' ',
      ),
      throwsArgumentError,
    );
    expect(
      () => TitleQuery(kind: TitleKind.movie, yearFrom: 2020, yearTo: 2000),
      throwsArgumentError,
    );
  });

  testWidgets('paging appends stops and error retains pages with user retry', (
    tester,
  ) async {
    final calls = <int>[];
    var fail = true;
    await tester.pumpWidget(
      host((q, p) async {
        calls.add(p);
        if (p == 2 && fail) throw StateError('offline');
        return TitlePage(
          items: List.generate(20, (i) => item((p - 1) * 20 + i)),
          nextPage: p < 3 ? p + 1 : null,
        );
      }),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('media-grid')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(calls, [1, 2]);
    expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).items.length, 20);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, [1, 2]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('title-page-retry')),
      500,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('media-grid')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('title-page-retry')));
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.byKey(const ValueKey('title-page-retry')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('media-grid')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(calls, [1, 2, 2, 3]);
    expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).items.length, 60);
  });
  testWidgets(
    'changed query waits discards stale response requests exact page one',
    (tester) async {
      final pending = Completer<TitlePage>();
      final calls = <(TitleQuery, int)>[];
      await tester.pumpWidget(
        host((q, p) {
          calls.add((q, p));
          return calls.length == 1
              ? pending.future
              : Future.value(TitlePage(items: [item(99)]));
        }),
      );
      await tester.pump();
      final bar = tester.widget<FilterBar>(find.byType(FilterBar));
      final next = bar.query.copyWith(
        genreIds: [28],
        countryCode: 'US',
        yearFrom: 2000,
        yearTo: 2020,
        sort: TitleSort.rating,
      );
      bar.onChanged(next);
      await tester.pump();
      expect(calls.length, 1);
      pending.complete(TitlePage(items: [item(1)], nextPage: 2));
      await tester.pumpAndSettle();
      expect(calls, [(TitleQuery(kind: TitleKind.movie), 1), (next, 1)]);
      expect(find.text('Title 1'), findsNothing);
      expect(find.text('Title 99'), findsOneWidget);
    },
  );
  testWidgets('empty uses existing empty view', (tester) async {
    await tester.pumpWidget(host((q, p) async => TitlePage(items: [])));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyView), findsOneWidget);
  });
  testWidgets('filter chips stay in place when a dialog opens', (tester) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(host((q, p) async => TitlePage(items: [])));
    await tester.pumpAndSettle();
    final chips = [for (var i = 0; i < 4; i++) _chip(i)];
    final positions = chips.map(tester.getTopLeft).toList();
    expect(positions[0].dx, lessThan(positions[1].dx));
    expect(positions[1].dx, lessThan(positions[2].dx));
    expect(positions[2].dx, lessThan(positions[3].dx));
    await tester.tap(chips[0]);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(chips.map(tester.getTopLeft).toList(), positions);
  });
  testWidgets('filter chips stay on one scrolling line on a narrow screen', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(400, 800));
    await tester.pumpWidget(host((q, p) async => TitlePage(items: [])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(_chip(0)).dy,
      tester.getTopLeft(_chip(3)).dy,
      reason: 'one horizontal line',
    );
    await expectLater(
      find.byType(PagedTitleGrid),
      matchesGoldenFile('goldens/paged_title_filters_400.png'),
    );
  });
  testWidgets('sort, genre, country and year chips set the query', (
    tester,
  ) async {
    final calls = <TitleQuery>[];
    await tester.pumpWidget(
      host((q, p) async {
        calls.add(q);
        return TitlePage(items: []);
      }),
    );
    await tester.pumpAndSettle();
    // 0 year, 1 country, 2 genre Action, 3 sort.
    await tester.tap(_chip(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rating').last);
    await tester.pumpAndSettle();
    expect(calls.last.sort, TitleSort.rating);
    await tester.tap(_chip(2));
    await tester.pumpAndSettle();
    expect(calls.last.genreIds, [28]);
    await tester.tap(_chip(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('United States').last);
    await tester.pumpAndSettle();
    expect(calls.last.countryCode, 'US');
    await tester.tap(_chip(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('year-preset-5')));
    await tester.pumpAndSettle();
    expect(calls.last.yearFrom, DateTime.now().year - 5);
    await tester.tap(_chip(2));
    await tester.pumpAndSettle();
    expect(calls.last.genreIds, isEmpty);
    expect(calls.last.sort, TitleSort.rating);
    expect(calls.last.countryCode, 'US');
  });
  testWidgets('desktop filter bar and grid', (tester) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(
      host((q, p) async => TitlePage(items: List.generate(20, item))),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PagedTitleGrid),
      matchesGoldenFile('goldens/paged_title_grid_1400.png'),
    );
  });
}

Finder _chip(int i) => find.byKey(ValueKey('filter-chip-$i'));
