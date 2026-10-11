import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

final _genres = {
  TitleKind.movie: [
    for (var i = 1; i <= 20; i++) TitleFilterOption(i, 'Movie genre $i'),
  ],
  TitleKind.tv: [
    for (var i = 101; i <= 105; i++) TitleFilterOption(i, 'TV genre $i'),
  ],
};

class _Harness {
  final taps = <(TitleQuery, String)>[];

  Widget app() => MaterialApp(
    localizationsDelegates: const [AppStrings.delegate],
    theme: AppTheme.dark(tv: false),
    home: GenresPage(
      genresByKind: _genres,
      onSeeAll: (q, t) => taps.add((q, t)),
    ),
  );
}

void main() {
  testWidgets('a tile per genre of the selected kind; tap opens its grid', (
    tester,
  ) async {
    final h = _Harness();
    await setLogicalSize(tester, const Size(1440, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('genre-tile-Movie genre 1')),
      findsOneWidget,
    );
    expect(find.text('TV genre 101'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('genre-tile-Movie genre 2')));
    expect(h.taps.single, (
      TitleQuery(kind: TitleKind.movie, genreIds: [2]),
      'Movie genre 2',
    ));
    await tester.tap(find.byKey(const ValueKey('genres-kind-tv')));
    await tester.pumpAndSettle();
    expect(find.text('Movie genre 1'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('genre-tile-TV genre 101')));
    expect(h.taps.last, (
      TitleQuery(kind: TitleKind.tv, genreIds: [101]),
      'TV genre 101',
    ));
  });

  testWidgets('genres page golden, desktop', (tester) async {
    final h = _Harness();
    await setLogicalSize(tester, const Size(1440, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(GenresPage),
      matchesGoldenFile('goldens/genres_page_1440.png'),
    );
  });

  testWidgets('sidebar with Movies, TV shows, Genres golden', (tester) async {
    await setLogicalSize(tester, const Size(1440, 900));
    final h = _Harness();
    AppDestination d(String id, String label, IconData icon) => AppDestination(
      id: id,
      label: label,
      icon: icon,
      builder: (_) => id == 'genres'
          ? GenresPage(genresByKind: _genres, onSeeAll: (_, _) {})
          : Center(child: Text('page-$id')),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: AppShell(
          activeId: 'home',
          destinations: [
            d('home', 'Home', Icons.home),
            d('movies', 'Movies', Icons.movie_outlined),
            d('tv', 'TV shows', Icons.tv_outlined),
            d('genres', 'Genres', Icons.category_outlined),
            d('search', 'Search', Icons.search),
            d('settings', 'Settings', Icons.settings),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('menu-pill')));
    await tester.pumpAndSettle();
    for (final id in ['movies', 'tv', 'genres']) {
      await tester.tap(find.byKey(ValueKey('menu-item-$id')));
      await tester.pumpAndSettle();
      if (id != 'genres') {
        expect(find.text('page-$id'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('menu-pill')));
        await tester.pumpAndSettle();
      }
    }
    expect(find.byType(GenresPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-pill')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/shell_new_destinations_1440.png'),
    );
  });

  testWidgets('kind switch sits below the page header, never behind it', (
    tester,
  ) async {
    final h = _Harness();
    await setLogicalSize(tester, const Size(1440, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final header = tester.getRect(find.byType(PageHeader));
    final toggle = tester.getRect(
      find.byKey(const ValueKey('genres-kind-movie')),
    );
    expect(toggle.top, greaterThanOrEqualTo(header.bottom));
    expect(find.text('Genres'), findsOneWidget);
  });
}
