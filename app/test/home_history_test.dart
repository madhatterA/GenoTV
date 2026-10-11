import 'dart:async';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:video_player/catalogue_views.dart';

class _Catalogue extends TmdbCatalogue {
  _Catalogue() : super(client: TmdbClient(http: ProviderHttp()));

  final queries = <BrowseQuery>[];
  final resolved = <String>[];

  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    queries.add(query);
    return MediaPage(
      items: [
        MediaItem(
          id: query.kind == MediaKind.movie ? 'tmdb:movie:1' : 'tmdb:tv:2',
          title: 'Trending ${query.kind!.name}',
          kind: query.kind!,
        ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<TmdbDetails> details(MediaItem item) async {
    resolved.add(item.id);
    return TmdbDetails(
      item: MediaItem(
        id: item.id,
        title: 'Title ${item.id}',
        kind: item.kind,
        artwork: Uri.parse('https://x/backdrop-${item.id}'),
      ),
      poster: Uri.parse('https://x/poster-${item.id}'),
    );
  }
}

PlaybackProgress _history(String id, int day, {bool completed = true}) =>
    PlaybackProgress(
      mediaId: id,
      position: const Duration(minutes: 90),
      duration: const Duration(minutes: 100),
      updatedAt: DateTime.utc(2026, 10, day),
      completed: completed,
    );

void main() {
  testWidgets(
    'home has trending, Liked (favourites) and Watched (all history) rows',
    (tester) async {
      final catalogue = _Catalogue();
      final favourites = FakeFavouritesRepository();
      final progress = FakeProgressRepository();
      await favourites.setFavourite('tmdb:movie:7', true);
      await favourites.setFavourite('tmdb:tv:8', true);
      await progress.upsert(_history('tmdb:movie:7', 4));
      await progress.upsert(_history('tmdb:tv:8:s1e2', 3));
      await progress.upsert(_history('tmdb:movie:9', 2));
      await progress.upsert(_history('tmdb:movie:10', 1));
      await progress.upsert(_history('tmdb:movie:11', 5, completed: false));
      await progress.upsert(_history('link:without-catalogue-metadata', 5));
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
      final model = tester
          .widget<HomeScreen>(find.byType(HomeScreen))
          .viewModel;
      expect(model.rows.map((row) => row.title), [
        'Trending Movies',
        'Trending Shows',
        'Liked',
        'Watched',
      ]);
      expect(model.rows[2].items.map((item) => item.id), [
        'tmdb:movie:7',
        'tmdb:tv:8',
      ]);
      // Lists show the 2:3 poster, never the detail page's wide backdrop.
      expect(
        model.rows[2].items.first.artwork,
        Uri.parse('https://x/poster-tmdb:movie:7'),
      );
      // Every watched title, finished or not, newest first; episodes map to
      // their show and links without catalogue metadata are skipped.
      expect(model.rows[3].items.map((item) => item.id), [
        'tmdb:movie:11',
        'tmdb:movie:7',
        'tmdb:tv:8',
        'tmdb:movie:9',
        'tmdb:movie:10',
      ]);
      expect(
        catalogue.queries.map((query) => query.sort),
        everyElement('trending'),
      );
      expect(catalogue.resolved, hasLength(7));
      await tester.pumpWidget(const SizedBox.shrink());
      catalogue.client.http.close();
    },
  );

  testWidgets('home reloads watch history after a pushed page returns', (
    tester,
  ) async {
    final catalogue = _Catalogue();
    final progress = FakeProgressRepository();
    final returned = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: TmdbHomeView(
          catalogue: catalogue,
          favourites: FakeFavouritesRepository(),
          progress: progress,
          onItemTap: (context, item) => Navigator.of(context)
              .push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Detail page')),
                ),
              )
              .whenComplete(returned.complete),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await progress.upsert(_history('tmdb:movie:9', 2));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(returned.isCompleted, isTrue);
    final model = tester.widget<HomeScreen>(find.byType(HomeScreen)).viewModel;
    expect(model.rows.last.title, 'Watched');
    expect(model.rows.last.items.map((item) => item.id), ['tmdb:movie:9']);
    await tester.pumpWidget(const SizedBox.shrink());
    catalogue.client.http.close();
  });

  testWidgets('Liked page lists favourites and follows like changes', (
    tester,
  ) async {
    final catalogue = _Catalogue();
    final favourites = FakeFavouritesRepository();
    await favourites.setFavourite('tmdb:movie:7', true);
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: TmdbLikedView(
          catalogue: catalogue,
          favourites: favourites,
          onItemTap: (item) => tapped.add(item.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilterBar), findsNothing);
    expect(find.text('Title tmdb:movie:7'), findsOneWidget);
    await favourites.setFavourite('tmdb:tv:8', true);
    await tester.pumpAndSettle();
    expect(find.text('Title tmdb:tv:8'), findsOneWidget);
    await tester.tap(find.text('Title tmdb:tv:8'));
    expect(tapped, ['tmdb:tv:8']);
    await favourites.setFavourite('tmdb:movie:7', false);
    await favourites.setFavourite('tmdb:tv:8', false);
    await tester.pumpAndSettle();
    expect(find.text('No liked titles yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    catalogue.client.http.close();
  });

  testWidgets('returning from a pushed page keeps Home loaded: no refetch', (
    tester,
  ) async {
    final catalogue = _Catalogue();
    final progress = FakeProgressRepository();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: TmdbHomeView(
          catalogue: catalogue,
          favourites: FakeFavouritesRepository(),
          progress: progress,
          onItemTap: (context, item) => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Detail page')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fetches = catalogue.queries.length;
    final model = tester.widget<HomeScreen>(find.byType(HomeScreen)).viewModel;
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Detail page'), findsOneWidget);
    await progress.upsert(_history('tmdb:movie:9', 2));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    // Every frame of the pop already shows the loaded rows, never a spinner.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LoadingView), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('row-Trending Movies')),
        findsOneWidget,
      );
    }
    await tester.pumpAndSettle();
    expect(catalogue.queries, hasLength(fetches));
    final after = tester.widget<HomeScreen>(find.byType(HomeScreen)).viewModel;
    expect(after, same(model));
    // Only the local Watched row was refreshed.
    expect(after.rows.last.title, 'Watched');
    expect(after.rows.last.items.map((item) => item.id), ['tmdb:movie:9']);
    await tester.pumpWidget(const SizedBox.shrink());
    catalogue.client.http.close();
  });
}
