import 'dart:io';

import 'package:contracts/fakes.dart';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:video_player/catalogue_views.dart';

class _Client extends TmdbClient {
  _Client() : super(http: ProviderHttp());
  final requests = <({bool isTv, List<int> genreIds, int page})>[];

  @override
  Future<List<TmdbNamedId>> genres({required bool isTv}) async => [
    for (var i = 1; i <= 15; i++) TmdbNamedId(i + (isTv ? 100 : 0), 'G$i'),
  ];

  @override
  Future<List<TmdbCountry>> countries() async => const [];

  @override
  Future<TmdbTitlePage> titlePage({
    required bool isTv,
    int page = 1,
    List<int> genreIds = const [],
    List<int> keywordIds = const [],
    String? countryCode,
    int? yearFrom,
    int? yearTo,
    String sort = 'popularity',
    int? personId,
    bool crew = false,
    String? searchText,
    bool trending = false,
  }) async {
    requests.add((isTv: isTv, genreIds: genreIds, page: page));
    return const TmdbTitlePage(items: []);
  }
}

class _Catalogue extends TmdbCatalogue {
  _Catalogue(this.fake) : super(client: fake);
  final _Client fake;
  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: [], hasMore: false);
}

void main() {
  testWidgets('Movies, TV shows and Genres destinations open their pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = _Client();
    final catalogue = _Catalogue(client);
    addTearDown(catalogue.dispose);
    final destinations = tmdbDestinations(
      favourites: FakeFavouritesRepository(),
      progress: FakeProgressRepository(),
      catalogue: catalogue,
      onItemTap: (_, _) {},
    );
    expect(destinations.map((d) => d.label), [
      'Home',
      'Movies',
      'TV shows',
      'Genres',
      'Liked',
      'Search',
    ]);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: AppShell(activeId: 'home', destinations: destinations),
      ),
    );
    await tester.pump();

    Future<void> open(String id) async {
      await tester.tap(find.byKey(const ValueKey('menu-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('menu-item-$id')));
      await tester.pumpAndSettle();
    }

    await open('movies');
    var grid = tester.widget<PagedTitleGrid>(find.byType(PagedTitleGrid));
    expect(grid.initialQuery, TitleQuery(kind: TitleKind.movie));
    expect(find.byType(FilterBar), findsOneWidget);
    expect(client.requests.any((r) => !r.isTv), isTrue);

    await open('tv');
    grid = tester.widget<PagedTitleGrid>(find.byType(PagedTitleGrid));
    expect(grid.initialQuery, TitleQuery(kind: TitleKind.tv));
    expect(find.byType(FilterBar), findsOneWidget);
    expect(client.requests.any((r) => r.isTv), isTrue);

    await open('genres');
    expect(find.byType(GenresPage), findsOneWidget);
    expect(find.byType(FocusableCard), findsWidgets);
    await tester.tap(find.byType(FocusableCard).first);
    await tester.pumpAndSettle();
    final seeAll = tester.widget<PagedTitleGrid>(
      find.byType(PagedTitleGrid).last,
    );
    expect(
      seeAll.initialQuery,
      TitleQuery(kind: TitleKind.movie, genreIds: [1]),
    );
    expect(find.byType(FilterBar), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty Liked offers Browse movies, which opens Movies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final catalogue = _Catalogue(_Client());
    addTearDown(catalogue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: AppShell(
          activeId: 'liked',
          destinations: tmdbDestinations(
            favourites: FakeFavouritesRepository(),
            progress: FakeProgressRepository(),
            catalogue: catalogue,
            onItemTap: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No liked titles yet'), findsOneWidget);
    expect(find.text('Titles you like appear here.'), findsOneWidget);
    await tester.tap(find.text('Browse movies'));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsWidgets);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    expect(shell.activeId, 'movies');
  });
}
