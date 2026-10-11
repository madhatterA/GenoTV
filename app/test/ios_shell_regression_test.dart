import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:video_player/catalogue_views.dart';

import 'package:core/core.dart';

void main() {
  for (final failure in <AppFailure>[
    const ContentSourceFailure.authRequired(),
    const ContentSourceFailure.invalidResponse(),
    const ContentSourceFailure.unavailable(),
    UnexpectedFailure(cause: StateError('local library failed')),
  ]) {
    testWidgets('${failure.code} is not an offline outage', (tester) async {
      final catalogue = _FailingCatalogue(failure);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: TmdbHomeView(
            catalogue: catalogue,
            favourites: FakeFavouritesRepository(),
            progress: FakeProgressRepository(),
            onItemTap: (_, _) {},
            retryDelay: const Duration(milliseconds: 100),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.wifiSlash), findsNothing);
      final calls = catalogue.calls;
      await tester.pump(const Duration(milliseconds: 150));
      if (failure.code == 'provider.unavailable') {
        expect(catalogue.calls, greaterThan(calls));
      } else {
        expect(catalogue.calls, calls);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await catalogue.dispose();
    });
  }

  testWidgets('network outage retains automatic recovery', (tester) async {
    final catalogue = _FailingCatalogue(const ContentSourceFailure.network());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: TmdbHomeView(
          catalogue: catalogue,
          favourites: FakeFavouritesRepository(),
          progress: FakeProgressRepository(),
          onItemTap: (_, _) {},
          retryDelay: const Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(PhosphorIconsRegular.wifiSlash), findsOneWidget);
    catalogue.failure = null;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.wifiSlash), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await catalogue.dispose();
  });

  for (final padding in [
    const EdgeInsets.only(top: 59, bottom: 34),
    EdgeInsets.zero,
  ]) {
    testWidgets('menu pill clears the top system padding $padding', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(390, 844), padding: padding),
            child: AppShell(
              activeId: 'home',
              destinations: [
                AppDestination(
                  id: 'home',
                  label: 'Home',
                  icon: Icons.home,
                  builder: (_) => const ColoredBox(
                    key: Key('page-body'),
                    color: Colors.black,
                  ),
                ),
                AppDestination(
                  id: 'movies',
                  label: 'Movies',
                  icon: Icons.movie,
                  builder: (_) => const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationBar), findsNothing);
      final pill = tester.getRect(
        find.byKey(const ValueKey<String>('menu-pill')),
      );
      expect(pill.top, closeTo(padding.top + 12, 2));
      // Hero pages bleed under the pill: the shell adds no top padding.
      expect(tester.getRect(find.byKey(const Key('page-body'))).top, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _FailingCatalogue extends TmdbCatalogue {
  _FailingCatalogue(this.failure)
    : super(client: TmdbClient(http: ProviderHttp()));
  AppFailure? failure;
  int calls = 0;
  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return MediaPage(items: [], hasMore: false);
  }
}
