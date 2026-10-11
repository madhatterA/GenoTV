import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

SeriesViewModel _model() => SeriesViewModel(seasons: fixtureSeriesSeasons());

Future<void> _pumpSeries(
  WidgetTester tester,
  SeriesViewModel model, {
  ValueChanged<SeriesEpisode>? onPlay,
  ValueChanged<SeriesEpisode>? onShowEpisodeDetails,
}) async {
  await setLogicalSize(tester, const Size(1920, 1080));
  await tester.pumpWidget(
    _app(
      SeriesDetailScreen(
        presentation: fixtureSeriesPresentation(),
        viewModel: model,
        onPlay: onPlay ?? (_) {},
        onShowEpisodeDetails: onShowEpisodeDetails,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await _reveal(tester, find.byKey(const ValueKey<String>('season-selector')));
}

/// Scrolls [finder] into view at the bottom of the viewport.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 1);
  await tester.pump();
}

void main() {
  group('season chips', () {
    testWidgets('the selected season is the filled chip; tapping swaps', (
      tester,
    ) async {
      final model = _model();
      await _pumpSeries(tester, model);
      AppChip chip(int i) => tester.widget<AppChip>(
        find.byKey(ValueKey<String>('season-chip-$i')),
      );
      expect(chip(0).selected, isTrue);
      expect(chip(1).selected, isFalse);
      await tester.tap(find.byKey(const ValueKey<String>('season-chip-1')));
      await tester.pump();
      expect(model.selectedSeason, 2);
      expect(chip(0).selected, isFalse);
      expect(chip(1).selected, isTrue);
    });
  });

  group('episode row text', () {
    for (final size in const <Size>[
      Size(480, 700),
      Size(800, 700),
      Size(1920, 1080),
    ]) {
      testWidgets('title, length and overview at ${size.width.toInt()}', (
        tester,
      ) async {
        await setLogicalSize(tester, size);
        await tester.pumpWidget(
          _app(
            EpisodeRow(
              episode: SeriesEpisode(
                season: 1,
                episode: 1,
                title: 'A very long episode title that cannot possibly fit on one line',
                duration: const Duration(minutes: 43),
                description:
                    'The crew follows a lead that surfaces after the storm, and Elena has to decide how much of the truth she can afford to tell before the harbor board meets again.' *
                    6,
              ),
              onPlay: () {},
            ),
          ),
        );
        final desc = find.textContaining('The crew follows');
        expect(find.text('43 min'), findsOneWidget);
        if (size.width < 600) {
          // Phone: no overview (DESIGN_SPEC §8.5).
          expect(desc, findsNothing);
          return;
        }
        final text = tester.widget<Text>(desc);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(
          tester.renderObject<RenderParagraph>(desc).didExceedMaxLines,
          isTrue,
        );
        expect(
          tester.getRect(desc).top,
          greaterThanOrEqualTo(tester.getRect(find.text('43 min')).bottom),
        );
      });
    }
  });

  group('episode list', () {
    testWidgets('tapping an episode plays exactly that season/episode', (
      tester,
    ) async {
      final model = _model();
      final played = <SeriesEpisode>[];
      await _pumpSeries(tester, model, onPlay: played.add);
      await tester.tap(find.byKey(const ValueKey<String>('season-chip-1')));
      await tester.pump();
      final row = find.byKey(const ValueKey<String>('episode-row-2-5'));
      await tester.dragUntilVisible(
        row,
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      expect(played, hasLength(1));
      expect(played.single.season, 2);
      expect(played.single.episode, 5);
      expect(model.focusedEpisode?.episode, 5);
    });

    testWidgets('Play plays the next-up episode', (tester) async {
      final seasons = fixtureSeriesSeasons();
      final nextUpEpisode = seasons
          .singleWhere((s) => s.number == 2)
          .episodes[6];
      final model = SeriesViewModel(seasons: seasons);
      // Simulate an already-loaded next-up without a repository round trip.
      await model.setNextUp(nextUpEpisode);
      final played = <SeriesEpisode>[];
      await _pumpSeries(tester, model, onPlay: played.add);
      await tester.tap(
        find.byKey(const ValueKey<String>('detail-play-action')),
      );
      await tester.pump();
      expect(played.single, nextUpEpisode);
    });

    testWidgets('playback-return refresh keeps season and focused row', (
      tester,
    ) async {
      final model = _model();
      await _pumpSeries(tester, model);
      await tester.tap(find.byKey(const ValueKey<String>('season-chip-1')));
      await tester.pump();
      final row = find.byKey(const ValueKey<String>('episode-row-2-1'));
      await _reveal(tester, row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      final stateBefore = tester.state<SeriesDetailScreenState>(
        find.byType(SeriesDetailScreen),
      );
      // A refreshed presentation (same item id, new progress) must not
      // remount the page.
      await tester.pumpWidget(
        _app(
          SeriesDetailScreen(
            presentation: fixtureSeriesPresentation(),
            viewModel: model,
            onPlay: (_) {},
          ),
        ),
      );
      await tester.pump();
      final stateAfter = tester.state<SeriesDetailScreenState>(
        find.byType(SeriesDetailScreen),
      );
      expect(identical(stateBefore, stateAfter), isTrue);
      expect(model.selectedSeason, 2);
    });
  });

  group('cast popup and person navigation', () {
    testWidgets('person detail renders portrait, name, and filmography', (
      tester,
    ) async {
      final memory = FocusMemory();
      final person = fixtureCastMembers().first;
      await tester.pumpWidget(
        _app(
          PersonDetailScreen(
            person: person,
            memory: memory,
            source: (_, _) async =>
                TitlePage(items: fixturePersonFilmography()),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('person-portrait')),
        findsOneWidget,
      );
      expect(find.text(person.name), findsOneWidget);
      expect(find.byType(PagedTitleGrid), findsOneWidget);
      expect(find.byType(FilterBar), findsOneWidget);
    });
  });

  group('series page layout sweep', () {
    for (final size in const [
      Size(480, 480),
      Size(800, 600),
      Size(1280, 800),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await setLogicalSize(tester, size);
          await tester.pumpWidget(
            _app(
              SeriesDetailScreen(
                presentation: fixtureSeriesPresentation(),
                viewModel: _model(),
                onPlay: (_) {},
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('episode thumbnail size', () {
    for (final (width, expected) in <(double, double)>[
      (480, 160),
      (1400, 240),
    ]) {
      testWidgets(
        'thumbnail is $expected wide, 16:9, in a ${width.toInt()} window',
        (tester) async {
          await setLogicalSize(tester, Size(width, 900));
          await tester.pumpWidget(
            _app(
              SeriesDetailScreen(
                presentation: fixtureSeriesPresentation(),
                viewModel: _model(),
                onPlay: (_) {},
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final thumb = tester.getSize(
            find.byKey(const ValueKey<String>('episode-thumb')).first,
          );
          expect(thumb.width, expected);
          expect(thumb.height, closeTo(expected * 9 / 16, 0.5));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('2x text and goldens', () {
    testWidgets('season/episode layout is safe at 2x text scale', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final model = _model();
      await tester.pumpWidget(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: ArtworkResolverScope(
              resolver: resolver,
              child: _app(
                SeriesDetailScreen(
                  presentation: fixtureSeriesPresentation(),
                  viewModel: model,
                  onPlay: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('series detail golden at 1920x1080', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            SeriesDetailScreen(
              presentation: fixtureSeriesPresentation(),
              viewModel: _model(),
              onPlay: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(SeriesDetailScreen),
        matchesGoldenFile('goldens/series_detail_1920.png'),
      );
    });

    testWidgets('person detail golden at 1920x1080', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            PersonDetailScreen(
              person: fixtureCastMembers().first,
              memory: memory,
              source: (_, _) async =>
                  TitlePage(items: fixturePersonFilmography()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(PersonDetailScreen),
        matchesGoldenFile('goldens/person_detail_1920.png'),
      );
    });
  });

  group('callback idempotence', () {
    testWidgets('selecting the same season twice notifies once', (
      tester,
    ) async {
      final model = _model();
      await _pumpSeries(tester, model);
      var notifications = 0;
      model.addListener(() => notifications++);
      model.selectSeason(1); // already selected season 1: no-op
      expect(notifications, 0);
      model.selectSeason(2);
      expect(notifications, 1);
      model.selectSeason(2); // repeat select: idempotent
      expect(notifications, 1);
    });
  });
}
