import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppStrings.localizationsDelegates,
  supportedLocales: AppStrings.supportedLocales,
  theme: AppTheme.dark(tv: false),
  home: child,
);

Widget _stateApp(Widget child) => MaterialApp(
  localizationsDelegates: AppStrings.localizationsDelegates,
  supportedLocales: AppStrings.supportedLocales,
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

const _item = MediaItem(
  id: 'acceptance-movie',
  title: 'Acceptance Movie',
  kind: MediaKind.movie,
  duration: Duration(minutes: 90),
);

CapabilityReport _report() => CapabilityReport(
  hardwareDecode: true,
  decoders: const <String>['h264'],
  hdrOutput: false,
  hdrFormats: const <String>[],
  displayModeSwitching: false,
  audioPassthrough: false,
  passthroughFormats: const <String>[],
  diagnostics: const <String, String>{'fallbackReason': 'acceptance fixture'},
);

void main() {
  testWidgets('every Part 04 public surface renders from fixture contracts', (
    tester,
  ) async {
    final settings = AppSettings(MemorySettingsStore());
    final controller = FakePlaybackController();
    final series = SeriesViewModel(
      seasons: const <SeriesSeason>[
        SeriesSeason(
          number: 1,
          title: 'Season 1',
          episodes: <SeriesEpisode>[
            SeriesEpisode(
              season: 1,
              episode: 1,
              title: 'Episode 1',
              duration: Duration(minutes: 42),
              description: 'Acceptance episode',
            ),
          ],
        ),
      ],
    );
    final surfaces = <Widget>[
      HomeScreen(
        viewModel: HomeViewModel(
          rows: <HomeRow>[
            HomeRow(title: 'Acceptance row', items: <MediaItem>[_item]),
          ],
        ),
      ),
      LibraryScreen(items: <MediaItem>[_item], scope: BrowseScope.movies),
      MovieDetailScreen(
        presentation: MovieDetailPresentation(item: _item),
        onPlay: () {},
      ),
      SeriesDetailScreen(
        presentation: MovieDetailPresentation(item: _item),
        viewModel: series,
        onPlay: (_) {},
      ),
      SearchScreen(search: (_) async => const <MediaItem>[]),
      PlayerScreen(
        controller: controller,
        videoSurface: const FakeVideoSurface(),
        setSystemUiMode: (_) async {},
      ),
      SettingsScreen(
        settings: settings,
        capabilities: _report(),
        available: const <SettingCapability>{},
      ),
      DiagnosticsScreen(report: _report()),
      const LoadingView(),
      const EmptyView(headline: 'Acceptance empty'),
      ErrorView(failure: const CancelledFailure()),
    ];

    for (final surface in surfaces) {
      await tester.pumpWidget(_app(surface));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(surface.runtimeType), findsOneWidget);
    }
    expect(find.text('Unable to continue'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    series.dispose();
    await controller.dispose();
  });

  testWidgets('shared state goldens have stable rendered evidence', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(800, 600));
    await tester.pumpWidget(_stateApp(const LoadingView()));
    await tester.pump();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/part04_loading.png'),
    );
    await tester.pumpWidget(
      _stateApp(const EmptyView(headline: 'No media available')),
    );
    await tester.pump();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/part04_empty.png'),
    );
    await tester.pumpWidget(
      _stateApp(const ErrorView(failure: CancelledFailure())),
    );
    await tester.pump();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/part04_error.png'),
    );
    // Flush the zero-delay timer the loading skeleton's pulse started.
    await tester.pump(const Duration(milliseconds: 1));
  });

  // The old-plan "typed navigation round-trip" test against `AppRouter` /
  // `AppShell(initialTab: ...)` / `routes.dart` was removed here: Part 04
  // Chapter 01 Phase 02 (rewritten plan) replaced that shell with the
  // generic `AppShell(destinations, activeId, onExitRequested)`, per
  // `EXECUTION.md`'s baseline note that this file's prior content has no
  // authority. The rewritten plan's own acceptance gate is
  // `part04_rivulet_acceptance_test.dart` (PART.md "Part acceptance"),
  // not yet written; this file's remaining tests cover shared
  // state/detail/series surfaces untouched by this phase.
}
