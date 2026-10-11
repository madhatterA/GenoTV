import 'dart:io';

import 'package:contracts/fakes.dart';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'package:video_player/catalogue_views.dart';

const _movie = MediaItem(
  id: 'tmdb:movie:42',
  title: 'Fixture movie',
  kind: MediaKind.movie,
  tmdbId: 42,
);
const _tv = MediaItem(
  id: 'tmdb:tv:43',
  title: 'Fixture show',
  kind: MediaKind.episode,
  tmdbId: 43,
);

class _Client extends TmdbClient {
  _Client() : super(http: ProviderHttp());

  final rolesRequested = <bool>[];
  final titleRequests = <({TitleQuery query, int page})>[];

  @override
  Future<({int movies, int tv})> personCreditCounts(
    int id, {
    bool crew = false,
  }) async {
    rolesRequested.add(crew);
    return crew ? (movies: 4, tv: 1) : (movies: 1, tv: 4);
  }

  @override
  Future<List<TmdbNamedId>> genres({required bool isTv}) async => const [
    TmdbNamedId(18, 'Drama'),
  ];

  @override
  Future<List<TmdbCountry>> countries() async => const [
    TmdbCountry('GB', 'United Kingdom'),
  ];

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
    titleRequests.add((
      query: TitleQuery(
        kind: isTv ? TitleKind.tv : TitleKind.movie,
        base: trending
            ? TitleBase.trending
            : personId != null
            ? TitleBase.person
            : searchText != null
            ? TitleBase.search
            : TitleBase.discover,
        personId: personId,
        personRole: crew ? TitlePersonRole.crew : TitlePersonRole.cast,
        searchText: searchText ?? '',
        genreIds: genreIds,
        keywordIds: keywordIds,
        countryCode: countryCode,
        yearFrom: yearFrom,
        yearTo: yearTo,
        sort: TitleSort.values.byName(sort),
      ),
      page: page,
    ));
    return const TmdbTitlePage(items: []);
  }
}

class _Catalogue extends TmdbCatalogue {
  _Catalogue(this.fakeClient) : super(client: fakeClient);
  final _Client fakeClient;

  @override
  Future<MediaPage> browse(BrowseQuery query) async => MediaPage(
    items: [query.kind == MediaKind.episode ? _tv : _movie],
    hasMore: false,
  );

  @override
  Future<TmdbDetails> details(MediaItem item) async => TmdbDetails(
    item: item,
    genreIds: const [TmdbNamedId(18, 'Drama')],
    genres: const ['Drama'],
    countries: const [TmdbCountry('GB', 'United Kingdom')],
    people: const [
      TmdbPerson('Fixture actor', 'Hero', null, id: 9),
      TmdbPerson('Fixture director', 'Director', null, id: 10, isCrew: true),
    ],
  );

  @override
  Future<List<TmdbSeasonSummary>> seasons(MediaItem show) async => [];

  @override
  Future<List<MediaItem>> episodes(MediaItem show, int seasonNumber) async =>
      [];
}

class _ShowCatalogue extends _Catalogue {
  _ShowCatalogue(super.fakeClient);

  @override
  Future<List<TmdbSeasonSummary>> seasons(MediaItem show) async => const [
    TmdbSeasonSummary(number: 1, name: 'Season 1', episodeCount: 2),
  ];

  @override
  Future<List<MediaItem>> episodes(MediaItem show, int seasonNumber) async => [
    for (var i = 1; i <= 2; i++)
      MediaItem(
        id: 'tmdb:tv:43:s1e$i',
        title: show.title,
        kind: MediaKind.episode,
        duration: const Duration(minutes: 40),
        subtitle: 'S01E0$i · Episode $i',
        seasonNumber: 1,
        episodeNumber: i,
      ),
  ];
}

Future<void> _desktop(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _openDetail(
  WidgetTester tester,
  TmdbCatalogue catalogue,
  MediaItem item, {
  ProgressRepository? progress,
}) async {
  await _desktop(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openTmdbDetail(
              context,
              catalogue: catalogue,
              item: item,
              onPlayMovie: (_, _) {},
              onPlayEpisode: (_, _, _) {},
              progress: progress,
            ),
            child: const Text('Open detail'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open detail'));
  await tester.pumpAndSettle();
}

void _expectQuery(WidgetTester tester, TitleQuery expected) {
  expect(find.byType(PagedTitleGrid), findsOneWidget);
  expect(
    tester.widget<PagedTitleGrid>(find.byType(PagedTitleGrid)).initialQuery,
    expected,
  );
  expect(tester.widget<FilterBar>(find.byType(FilterBar)).query, expected);
}

void main() {
  episodeProgressTests();
  testWidgets(
    'home lists Liked favourites and Watched history as separate rows',
    (tester) async {
      await _desktop(tester);
      final catalogue = _Catalogue(_Client());
      addTearDown(catalogue.dispose);
      final favourites = FakeFavouritesRepository();
      await favourites.setFavourite('tmdb:movie:42', true);
      await favourites.setFavourite('tmdb:tv:43', true);
      final progress = FakeProgressRepository();
      for (final entry in [
        (id: 'tmdb:movie:44', day: 1, completed: true),
        (id: 'tmdb:movie:45', day: 3, completed: true),
        (id: 'tmdb:tv:43:s1e2', day: 4, completed: true),
        (id: 'tmdb:movie:42', day: 5, completed: true),
        (id: 'tmdb:movie:46', day: 6, completed: false),
      ]) {
        await progress.upsert(
          PlaybackProgress(
            mediaId: entry.id,
            position: const Duration(minutes: 90),
            duration: const Duration(minutes: 90),
            updatedAt: DateTime.utc(2024, 1, entry.day),
            completed: entry.completed,
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: TmdbHomeView(
            catalogue: catalogue,
            favourites: favourites,
            progress: progress,
            onItemTap: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rows = tester
          .widget<HomeScreen>(find.byType(HomeScreen))
          .viewModel
          .rows;
      expect(rows.map((row) => row.title), [
        'Trending Movies',
        'Trending Shows',
        'Liked',
        'Watched',
      ]);
      expect(rows[2].items.map((item) => item.id), [
        'tmdb:movie:42',
        'tmdb:tv:43',
      ]);
      expect(rows.last.items.map((item) => item.id), [
        'tmdb:movie:46',
        'tmdb:movie:42',
        'tmdb:tv:43',
        'tmdb:movie:45',
        'tmdb:movie:44',
      ]);
      expect(rows.last.query, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final crew in [false, true]) {
    testWidgets(
      'detail ${crew ? 'crew' : 'cast'} opens role-specific person grid',
      (tester) async {
        final client = _Client();
        final catalogue = _Catalogue(client);
        addTearDown(catalogue.dispose);
        await _openDetail(tester, catalogue, _movie);
        final member = find.byKey(ValueKey('cast-member-${crew ? 10 : 9}'));
        await tester.ensureVisible(member);
        await tester.tap(member);
        await tester.pumpAndSettle();
        expect(find.byType(PersonDetailScreen), findsOneWidget);
        expect(
          find.text(crew ? 'Fixture director' : 'Fixture actor'),
          findsOneWidget,
        );
        expect(client.rolesRequested, [crew]);
        final initialKind = crew ? TitleKind.movie : TitleKind.tv;
        final expected = TitleQuery(
          kind: initialKind,
          base: TitleBase.person,
          personId: crew ? 10 : 9,
          personRole: crew ? TitlePersonRole.crew : TitlePersonRole.cast,
        );
        _expectQuery(tester, expected);
        final nextKind = crew ? TitleKind.tv : TitleKind.movie;
        await tester.tap(
          find.byKey(ValueKey('title-kind-${crew ? 'tv' : 'movie'}')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilterBar>(find.byType(FilterBar)).query,
          expected.copyWith(kind: nextKind),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final item in [_movie, _tv]) {
    for (final country in [false, true]) {
      testWidgets(
        '${item.kind.name} ${country ? 'country' : 'genre'} opens preselected grid',
        (tester) async {
          final catalogue = _Catalogue(_Client());
          addTearDown(catalogue.dispose);
          await _openDetail(tester, catalogue, item);
          final link = find.byKey(
            ValueKey(
              'detail-link-${country ? 'with_origin_country-GB' : 'with_genres-18'}',
            ),
          );
          await tester.ensureVisible(link.first);
          await tester.tap(link.first);
          await tester.pumpAndSettle();
          _expectQuery(
            tester,
            TitleQuery(
              kind: item.kind == MediaKind.movie
                  ? TitleKind.movie
                  : TitleKind.tv,
              genreIds: country ? [] : [18],
              countryCode: country ? 'GB' : null,
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final base in [TitleBase.trending, TitleBase.discover]) {
    for (final kind in TitleKind.values) {
      testWidgets(
        'home ${kind.name} ${base.name} See all preserves row query',
        (tester) async {
          await _testHomeRow(tester, TitleQuery(kind: kind, base: base));
        },
      );
    }
  }
  testWidgets('home Top rated See all preserves rating discover query', (
    tester,
  ) async {
    await _testHomeRow(
      tester,
      TitleQuery(kind: TitleKind.movie, sort: TitleSort.rating),
    );
  });

  for (final row in [
    (title: 'Trending Movies', kind: TitleKind.movie, base: TitleBase.trending),
    (title: 'Trending Shows', kind: TitleKind.tv, base: TitleBase.trending),
  ]) {
    testWidgets('actual TMDB home ${row.title} opens the matching source', (
      tester,
    ) async {
      await _desktop(tester);
      final client = _Client();
      final catalogue = _Catalogue(client);
      addTearDown(catalogue.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: TmdbHomeView(
            catalogue: catalogue,
            favourites: FakeFavouritesRepository(),
            progress: FakeProgressRepository(),
            onItemTap: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // On desktop "See all" is the last card of its row: bring the row into
      // view, then scroll the row sideways until the end card is built.
      final shelf = find.byKey(ValueKey('row-${row.title}'));
      await tester.dragUntilVisible(
        shelf,
        find
            .descendant(
              of: find.byType(HomeScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -400),
        maxIteration: 8,
      );
      final seeAll = find.descendant(of: shelf, matching: find.text('See all'));
      await tester.dragUntilVisible(
        seeAll,
        find.descendant(of: shelf, matching: find.byType(Scrollable)).first,
        const Offset(-300, 0),
        maxIteration: 30,
      );
      await tester.ensureVisible(seeAll);
      await tester.pumpAndSettle();
      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      final expected = TitleQuery(kind: row.kind, base: row.base);
      _expectQuery(tester, expected);
      expect(client.titleRequests, [(query: expected, page: 1)]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('actual TMDB search types with no filters and switches kind', (
    tester,
  ) async {
    await _desktop(tester);
    final client = _Client();
    final catalogue = _Catalogue(client);
    addTearDown(catalogue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: TmdbSearchView(catalogue: catalogue, onItemTap: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.titleRequests, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('search-field')),
      'Arrival',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();
    final expected = TitleQuery(
      kind: TitleKind.movie,
      base: TitleBase.search,
      searchText: 'Arrival',
    );
    _expectQuery(tester, expected);
    expect(client.titleRequests, [(query: expected, page: 1)]);
    expect(expected.genreIds, isEmpty);
    expect(expected.countryCode, isNull);
    expect(expected.yearFrom, isNull);
    expect(expected.yearTo, isNull);
    await tester.tap(find.byKey(const ValueKey('title-kind-tv')));
    await tester.pumpAndSettle();
    final television = expected.copyWith(kind: TitleKind.tv);
    _expectQuery(tester, television);
    expect(client.titleRequests.last, (query: television, page: 1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _testHomeRow(WidgetTester tester, TitleQuery query) async {
  await _desktop(tester);
  final catalogue = _Catalogue(_Client());
  addTearDown(catalogue.dispose);
  final viewModel = HomeViewModel(
    rows: [
      HomeRow(title: 'Fixture row', items: const [_movie], query: query),
    ],
  );
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: Builder(
        builder: (context) => HomeScreen(
          viewModel: viewModel,
          onSeeAll: (row) => openTmdbGrid(
            context,
            catalogue: catalogue,
            query: row.query!,
            title: row.title,
            onItemTap: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final seeAll = find.text('See all');
  await tester.ensureVisible(seeAll);
  await tester.tap(seeAll);
  await tester.pumpAndSettle();
  _expectQuery(tester, query);
  expect(tester.takeException(), isNull);
}

// Part 06 ch03 p03: a partly watched episode shows its progress bar, read
// from the progress store Continue watching uses (keyed by episode id).
void episodeProgressTests() {
  testWidgets('series detail draws the saved progress of an episode', (
    tester,
  ) async {
    final catalogue = _ShowCatalogue(_Client());
    addTearDown(catalogue.dispose);
    final progress = FakeProgressRepository();
    await progress.upsert(
      PlaybackProgress(
        mediaId: 'tmdb:tv:43:s1e2',
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 40),
        updatedAt: DateTime.utc(2026, 1, 1),
        completed: false,
      ),
    );
    await _openDetail(tester, catalogue, _tv, progress: progress);
    ProgressBar barOf(String id) => tester.widget<ProgressBar>(
      find.descendant(
        of: find.byKey(ValueKey<String>('episode-row-$id')),
        matching: find.byType(ProgressBar),
      ),
    );
    expect(barOf('1-2').fraction, 0.25);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('episode-row-1-1')),
        matching: find.byType(ProgressBar),
      ),
      findsNothing,
    );
  });
}
