import 'package:ui/src/detail/rating_mark.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/l10n_tools.dart';
import 'support/state_screen_registry.dart';
import 'support/fixture_artwork.dart';

import 'package:flutter/foundation.dart';

class _CastFixture implements CastUiController {
  @override
  final ValueNotifier<CastUiState> state = ValueNotifier<CastUiState>(
    const CastUiState(
      targets: [CastTarget(id: 'tv', name: 'Living room', playable: false)],
      airPlayAvailable: true,
    ),
  );
  @override
  Future<void> startDiscovery() async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> cast(String targetId) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      builder: (_, child) =>
          Directionality(textDirection: TextDirection.ltr, child: child!),
      theme: AppTheme.dark(tv: false),
      home: AdaptiveBehavior(child: Scaffold(body: child)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _check(WidgetTester tester) {
  expect(
    findUntranslatedText(
      tester,
      allow: {...fixtureContentStrings, ...kTechAllowlist},
    ),
    isEmpty,
  );
}

void main() {
  _goldens();
  for (final name in [
    'home',
    'movies',
    'genres',
    'search',
    'movie_detail',
    'series_detail',
    'person_detail',
    'play_source',
    'play_link',
  ]) {
    testWidgets('$name contains only Persian copy or fixture content', (
      tester,
    ) async {
      final fixture = await p06MatrixFixtures[name]!();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      });
      await _pump(tester, fixture.widget);
      _check(tester);
    });
  }
  for (final entry in [
    ('source_loading', sourcesLoadingFixture),
    ('source_failed', sourcesFailedFixture),
    (
      'search_no_results',
      () => publicScreenFixtures
          .firstWhere((f) => f.name == 'SearchScreen')
          .build(ScreenFixtureState.empty),
    ),
  ]) {
    testWidgets('${entry.$1} contains only Persian copy', (tester) async {
      final fixture = await entry.$2();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      });
      await _pump(tester, fixture.widget);
      _check(tester);
    });
  }
  testWidgets('search prompt contains only Persian copy', (tester) async {
    final controller = LibrarySearchController(search: (_) async => []);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      SearchScreen(
        search: controller.search,
        controller: controller,
        onItemTap: (_) {},
      ),
    );
    _check(tester);
  });
  testWidgets('Liked empty contains only Persian copy', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => PagedTitleGrid(
          source: (_, _) async => TitlePage(items: []),
          initialQuery: TitleQuery(kind: TitleKind.movie),
          title: AppStrings.of(context).common_liked,
          showFilters: false,
          empty: EmptyView(
            headline: AppStrings.of(context).liked_emptyTitle,
            body: AppStrings.of(context).liked_emptyBody,
            primaryLabel: AppStrings.of(context).liked_browseMovies,
            onPrimary: () {},
          ),
          onItemTap: (_) {},
        ),
      ),
    );
    await tester.pump();
    _check(tester);
  });
  testWidgets('Play link recent contains only Persian copy', (tester) async {
    final recent = RecentLinks(MemorySettingsStore());
    await recent.add(
      'https://example.invalid/recent.mp4',
      kind: 'http',
      title: 'Recent fixture',
    );
    await _pump(
      tester,
      PlayLinkPage(
        recents: recent,
        onPlay: (_) async => null,
        pickTorrent: () async => null,
      ),
    );
    _check(tester);
  });
  testWidgets('cast picker contains only Persian copy', (tester) async {
    final cast = _CastFixture();
    addTearDown(cast.state.dispose);
    await _pump(tester, CastPicker(controller: cast, dismiss: () {}));
    _check(tester);
  });
  testWidgets('offline state contains only Persian copy', (tester) async {
    final outage = ConnectionOutageController()
      ..updateConnection(healthy: false);
    addTearDown(outage.dispose);
    await _pump(
      tester,
      ConnectionOutageBanner(controller: outage, onRetry: () async {}),
    );
    _check(tester);
  });
  testWidgets('error state contains only Persian copy', (tester) async {
    await _pump(
      tester,
      ErrorView(
        failure: UnexpectedFailure(cause: 'fixture'),
        onRetry: () {},
      ),
    );
    _check(tester);
  });
  testWidgets('menu panel contains only Persian copy', (tester) async {
    await _pump(
      tester,
      AppShell(
        activeId: 'home',
        destinations: [
          AppDestination(
            id: 'home',
            labelOf: (s) => s.common_home,
            icon: PhosphorIconsRegular.house,
            builder: (_) => const SizedBox.shrink(),
          ),
          AppDestination(
            id: 'movies',
            labelOf: (s) => s.common_movies,
            icon: PhosphorIconsRegular.filmSlate,
            builder: (_) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('menu-pill')));
    await tester.pump(const Duration(milliseconds: 400));
    _check(tester);
  });
  testWidgets(
    'Persian ratings and legacy English size/runtime retain their format',
    (tester) async {
      final out = <String, String>{};
      for (final locale in ['en', 'fa']) {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppStrings.localizationsDelegates,
            supportedLocales: AppStrings.supportedLocales,
            theme: AppTheme.dark(tv: false),
            home: Builder(
              builder: (context) {
                out['$locale runtime'] = formatDuration(
                  context,
                  const Duration(hours: 2),
                  includeZeroMinutes: true,
                );
                out['$locale bytes'] = formatFileSize(
                  context,
                  512,
                  decimalBytes: true,
                );
                return const Column(
                  children: [
                    RatingMark(imdb: '7.8', scale: 1),
                    RatingMark(rottenTomatoes: '87%', scale: 1),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pump();
        expect(find.text(locale == 'en' ? '7.8' : '۷٫۸'), findsOneWidget);
        expect(find.text(locale == 'en' ? '87%' : '۸۷٪'), findsOneWidget);
      }
      expect(out['en runtime'], '2h 0m');
      expect(out['en bytes'], '512.0 B');
      expect(out['fa runtime'], '۲ ساعت');
      expect(out['fa bytes'], '۵۱۲٫۰ بایت');
    },
  );
}

const _factors = <String, ({Size size, double dpr, bool tv})>{
  'phone': (size: Size(400, 800), dpr: 1, tv: false),
  'desktop': (size: Size(1280, 800), dpr: 1, tv: false),
  'tv': (size: Size(960, 540), dpr: 2, tv: true),
};

void _goldens() {
  for (final id in [
    'home',
    'movies',
    'genres',
    'search',
    'movie_detail',
    'series_detail',
    'person_detail',
    'play_source',
    'play_link',
  ]) {
    for (final entry in _factors.entries) {
      // Person detail has no Farsi TV golden in the matrix (phone + desktop).
      if (id == 'person_detail' && entry.key == 'tv') continue;
      final factor = entry.value;
      testWidgets('$id ${entry.key} fa golden', (tester) async {
        debugDefaultTargetPlatformOverride = switch (entry.key) {
          'desktop' => TargetPlatform.macOS,
          _ => TargetPlatform.android,
        };
        tester.view.physicalSize = factor.size * factor.dpr;
        tester.view.devicePixelRatio = factor.dpr;
        addTearDown(tester.view.reset);
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final artwork = await loadFixtureArtworkResolver(tester);
        final built = await p06MatrixFixtures[id]!();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('fa'),
            builder: (_, child) =>
                Directionality(textDirection: TextDirection.ltr, child: child!),
            localizationsDelegates: AppStrings.localizationsDelegates,
            supportedLocales: AppStrings.supportedLocales,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(tv: factor.tv),
            home: AdaptiveBehavior(
              capabilities: factor.tv
                  ? const PlatformCapabilities.directionalPad()
                  : entry.key == 'phone'
                  ? const PlatformCapabilities.touch()
                  : const PlatformCapabilities(),
              child: ArtworkResolverScope(
                resolver: artwork,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: RepaintBoundary(
                    key: const ValueKey<String>('p06-matrix'),
                    child: built.widget,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        _check(tester);
        await expectLater(
          find.byKey(const ValueKey<String>('p06-matrix')),
          matchesGoldenFile('goldens/p06/${id}_${entry.key}_fa.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await built.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
