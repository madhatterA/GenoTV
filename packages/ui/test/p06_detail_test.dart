import 'package:contracts/contracts.dart' show MediaItem;
import 'package:contracts/fakes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/state_screen_registry.dart';

// Part 06 ch03 p03: Movie, Series and Person detail and the play-source
// picker (DESIGN_SPEC §8.5, §8.6). Action row, like toggle, season chips and
// episode rows, poster placement, source rows, and the resume, worst-case,
// loading, failed and sheet goldens.

typedef _Factor = ({Size size, double dpr, bool tv, PlatformCapabilities caps});

final Map<String, _Factor> _factors = <String, _Factor>{
  'phone': (
    size: const Size(400, 800),
    dpr: 1,
    tv: false,
    caps: const PlatformCapabilities.touch(),
  ),
  'desktop': (
    size: const Size(1280, 800),
    dpr: 1,
    tv: false,
    caps: const PlatformCapabilities(),
  ),
  'tv': (
    size: const Size(960, 540),
    dpr: 2,
    tv: true,
    caps: const PlatformCapabilities.directionalPad(),
  ),
};

/// [testWidgets] that restores the platform override before the framework's
/// invariant check, even when the body fails.
void _test(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

/// Pumps [home] in the matrix harness of `p06_screen_matrix_test.dart`.
Future<void> _pump(
  WidgetTester tester,
  String factor,
  Widget home, {
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) async {
  final spec = _factors[factor]!;
  debugDefaultTargetPlatformOverride = factor == 'desktop'
      ? TargetPlatform.macOS
      : TargetPlatform.android;
  tester.view.physicalSize = spec.size * spec.dpr;
  tester.view.devicePixelRatio = spec.dpr;
  addTearDown(tester.view.reset);
  final artwork = await loadFixtureArtworkResolver(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      debugShowCheckedModeBanner: false,
      navigatorObservers: observers,
      theme: AppTheme.dark(tv: spec.tv),
      home: AdaptiveBehavior(
        capabilities: spec.caps,
        child: ArtworkResolverScope(
          resolver: artwork,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: RepaintBoundary(
              key: const ValueKey<String>('p06-detail'),
              child: home,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _golden(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byKey(const ValueKey<String>('p06-detail')),
    matchesGoldenFile('goldens/p06/$name.png'),
  );
}

Widget _movie({
  bool resume = false,
  bool worstCase = false,
  bool trailer = true,
  bool favourites = true,
}) {
  final base = moviePresentation(resume: resume, worstCase: worstCase);
  final screen = MovieDetailScreen(
    presentation: trailer
        ? base
        : MovieDetailPresentation(
            item: base.item,
            poster: base.poster,
            year: base.year,
            summary: base.summary,
            cast: base.cast,
          ),
    onPlay: () {},
    onTrailerTap: (_) {},
    onLinkTap: (_) {},
  );
  return favourites
      ? FavouritesScope(repository: FakeFavouritesRepository(), child: screen)
      : screen;
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey<String>(key)));

/// A trivial navigator observer counting pushes.
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  group('action row', () {
    _test('Play, Trailer, Like in that order, left-aligned, gap 12', (
      tester,
    ) async {
      await _pump(tester, 'desktop', _movie());
      final title = _rect(tester, 'detail-hero-title');
      final play = _rect(tester, 'detail-play-action');
      final trailer = _rect(tester, 'detail-trailer');
      final like = _rect(tester, 'detail-like');
      expect(play.left, title.left);
      expect(trailer.left - play.right, 12);
      expect(like.left - trailer.right, 12);
      final row = find.descendant(
        of: find.byKey(const ValueKey<String>('detail-actions')),
        matching: find.byWidgetPredicate(
          (w) => w is AppButton || w is AppIconButton,
        ),
      );
      expect(row, findsNWidgets(3));
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Trailer'), findsOneWidget);
      expect(find.text('Watched'), findsNothing);
      expect(find.text('Watchlist'), findsNothing);
      expect(find.text('Info'), findsNothing);
    });

    _test('no trailer: no Trailer button, Like follows Play', (tester) async {
      await _pump(tester, 'desktop', _movie(trailer: false));
      expect(
        find.byKey(const ValueKey<String>('detail-trailer')),
        findsNothing,
      );
      final play = _rect(tester, 'detail-play-action');
      expect(_rect(tester, 'detail-like').left - play.right, 12);
    });

    _test('"Resume 12:34" when progress exists', (tester) async {
      await _pump(tester, 'desktop', _movie(resume: true));
      expect(find.text('Resume 12:34'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      await _golden(tester, 'movie_detail_resume_desktop');
    });
  });

  group('like toggle', () {
    _test('heart <-> heartFill with a 1 -> 1.2 -> 1 scale in 2 x press', (
      tester,
    ) async {
      await _pump(tester, 'desktop', _movie());
      final like = find.byKey(const ValueKey<String>('detail-like'));
      double scale() => tester
          .widget<ScaleTransition>(
            find
                .ancestor(of: like, matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
          .value;
      expect(find.byIcon(PhosphorIconsRegular.heart), findsOneWidget);
      expect(scale(), 1);
      await tester.tap(like);
      await tester.pump();
      expect(find.byIcon(PhosphorIconsFill.heart), findsOneWidget);
      await tester.pump(RivuletMotion.press);
      expect(scale(), closeTo(1.2, 0.001));
      await tester.pump(RivuletMotion.press);
      expect(scale(), closeTo(1, 0.001));
      await tester.tap(like);
      await tester.pumpAndSettle();
      expect(find.byIcon(PhosphorIconsRegular.heart), findsOneWidget);
    });

    _test('no favourites store: no Like button', (tester) async {
      await _pump(tester, 'desktop', _movie(favourites: false));
      expect(find.byKey(const ValueKey<String>('detail-like')), findsNothing);
    });
  });

  group('poster', () {
    for (final factor in const <String>['desktop', 'tv']) {
      _test('$factor: left of the text block', (tester) async {
        await _pump(tester, factor, _movie());
        final poster = _rect(tester, 'detail-poster');
        final title = _rect(tester, 'detail-hero-title');
        expect(poster.right, lessThanOrEqualTo(title.left));
        expect(title.left - poster.right, 24);
        expect(poster.height, closeTo(poster.width * 1.5, 0.5));
      });
    }

    _test('phone: no poster', (tester) async {
      await _pump(tester, 'phone', _movie());
      expect(find.byKey(const ValueKey<String>('detail-poster')), findsNothing);
    });
  });

  group('series', () {
    SeriesViewModel model() => SeriesViewModel(seasons: fixtureSeriesSeasons());

    Widget series(SeriesViewModel m) => SeriesDetailScreen(
      presentation: fixtureSeriesPresentation(),
      viewModel: m,
      onPlay: (_) {},
    );

    _test('season chips sit directly above the episode list', (tester) async {
      final m = model();
      addTearDown(m.dispose);
      await _pump(tester, 'desktop', series(m));
      final chips = _rect(tester, 'season-selector');
      final first = _rect(tester, 'episode-0');
      expect(first.top, greaterThan(chips.bottom));
      expect(first.top - chips.bottom, lessThan(RivuletSpacing.s16));
    });

    _test('selecting a chip swaps the episodes without a page push', (
      tester,
    ) async {
      final m = model();
      addTearDown(m.dispose);
      final observer = _PushCounter();
      await _pump(tester, 'desktop', series(m), observers: [observer]);
      final pushes = observer.pushes;
      expect(
        find.byKey(const ValueKey<String>('episode-row-1-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('season-chip-1')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('episode-row-1-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('episode-row-2-1')),
        findsOneWidget,
      );
      expect(observer.pushes, pushes);
    });

    _test('Down from Play enters the season chips on the selected chip', (
      tester,
    ) async {
      final m = model();
      addTearDown(m.dispose);
      m.selectSeason(2);
      await _pump(tester, 'desktop', series(m));
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('detail-play-action')),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        focused.findAncestorWidgetOfExactType<AppChip>()?.key,
        const ValueKey<String>('season-chip-1'),
      );
    });

    _test('a partly watched episode shows a 3 px accent progress bar', (
      tester,
    ) async {
      final m = model();
      addTearDown(m.dispose);
      await _pump(tester, 'desktop', series(m));
      final row = find.byKey(const ValueKey<String>('episode-row-1-2'));
      await tester.dragUntilVisible(
        row,
        find.byType(CustomScrollView),
        const Offset(0, -200),
      );
      final bar = find.descendant(of: row, matching: find.byType(ProgressBar));
      expect(bar, findsOneWidget);
      expect(tester.widget<ProgressBar>(bar).fraction, 0.45);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('episode-row-1-1')),
          matching: find.byType(ProgressBar),
        ),
        findsNothing,
      );
    });

    _test('worst case: 40 episodes, no thumbnails, Persian overview', (
      tester,
    ) async {
      final m = SeriesViewModel(
        seasons: <SeriesSeason>[
          SeriesSeason(
            number: 1,
            title: 'Season 1',
            episodes: <SeriesEpisode>[
              for (var i = 1; i <= 40; i++)
                SeriesEpisode(
                  season: 1,
                  episode: i,
                  title: i.isEven
                      ? 'قسمت $i: بازگشت به شهر بندری که هیچ‌کس ترکش نکرد'
                      : 'S01E$i · An episode title that is far too long to '
                            'fit on one line of a phone',
                  duration: Duration(minutes: 40 + i),
                  description:
                      'خلاصهٔ این قسمت درباره‌ی مأموری است که پس از '
                          'سال‌ها به شهر خود بازمی‌گردد. ' *
                      4,
                ),
            ],
          ),
        ],
      );
      addTearDown(m.dispose);
      for (final factor in const <String>['phone', 'desktop']) {
        await _pump(tester, factor, series(m));
        expect(tester.takeException(), isNull);
        expect(find.byType(EpisodeRow), findsWidgets);
      }
    });
  });

  group('person', () {
    _test('Known for is the first 10 titles of the filmography', (
      tester,
    ) async {
      final tapped = <MediaItem>[];
      await _pump(
        tester,
        'desktop',
        PersonDetailScreen(
          person: const CastMember(id: 1, name: 'Mara Voss'),
          memory: FocusMemory(),
          source: (_, _) async => TitlePage(items: browseGridItems(count: 14)),
          onTitleTap: tapped.add,
        ),
      );
      final row = find.byKey(const ValueKey('person-known-for'));
      expect(row, findsOneWidget);
      expect(tester.widget<MediaRow>(row).items.map((i) => i.id), [
        for (var i = 0; i < 10; i++) 'browse-$i',
      ]);
      // The row sits above the first filmography poster, in the same scroll.
      expect(
        tester.getRect(row).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('grid-item-0'))).top,
        ),
      );
    });

    _test('no filmography: no Known for row', (tester) async {
      await _pump(
        tester,
        'desktop',
        PersonDetailScreen(
          person: const CastMember(id: 1, name: 'Mara Voss'),
          memory: FocusMemory(),
          source: (_, _) async => TitlePage(items: const <MediaItem>[]),
        ),
      );
      expect(find.byKey(const ValueKey('person-known-for')), findsNothing);
    });

    _test('long biography shows six lines and More expands it', (tester) async {
      await _pump(
        tester,
        'phone',
        PersonDetailScreen(
          person: CastMember(
            id: 1,
            name: 'Mara Voss',
            biography:
                'She grew up in a fishing town on the northern coast and '
                    'began acting in school plays before moving to the city. ' *
                4,
          ),
          memory: FocusMemory(),
          source: (_, _) async => TitlePage(items: browseGridItems(count: 4)),
        ),
      );
      final bio = find.byKey(const ValueKey('person-bio'));
      expect(
        tester
            .widget<Text>(find.descendant(of: bio, matching: find.byType(Text)))
            .maxLines,
        6,
      );
      final toggle = find.byKey(const ValueKey('person-bio-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.descendant(of: bio, matching: find.byType(Text)))
            .maxLines,
        isNull,
      );
      expect(find.text('Less'), findsOneWidget);
    });
  });

  group('play source', () {
    _test('rows are AppRows; "Insert link…" is the last provider row', (
      tester,
    ) async {
      final built = await p06MatrixFixtures['play_source']!();
      await _pump(tester, 'desktop', built.widget);
      final rows = find.descendant(
        of: find.byKey(const ValueKey<String>('play-source-providers')),
        matching: find.byType(AppRow),
      );
      expect(rows, findsNWidgets(4));
      expect(
        tester.widget<AppRow>(rows.last).key,
        const ValueKey<String>('provider-row-insert-link'),
      );
      expect(tester.widget<AppRow>(rows.last).label, 'Insert link…');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('play-source-streams')),
          matching: find.byType(AppRow),
        ),
        findsNWidgets(3),
      );
      await built.dispose();
    });

    _test('loading shows OrbLoader.medium and "Finding sources…"', (
      tester,
    ) async {
      final built = await sourcesLoadingFixture();
      await _pump(tester, 'desktop', built.widget);
      expect(find.text('Finding sources…'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byKey(const ValueKey<String>('play-source-loading')),
                matching: find.byType(OrbLoader),
              ),
            )
            .width,
        48,
      );
      await _golden(tester, 'play_source_loading_desktop');
      await built.dispose();
    });

    _test('failed shows the error with Retry', (tester) async {
      final built = await sourcesFailedFixture();
      await _pump(tester, 'desktop', built.widget);
      expect(
        find.byKey(const ValueKey<String>('play-source-failed')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      await _golden(tester, 'play_source_failed_desktop');
      await built.dispose();
    });

    _test('in the phone sheet: no back arrow, title 16 px under the handle', (
      tester,
    ) async {
      final built = await p06MatrixFixtures['play_source']!();
      await _pump(tester, 'phone', AppSheet(child: built.widget));
      expect(find.byKey(const ValueKey<String>('top-back')), findsNothing);
      final handle = _rect(tester, 'app-sheet-handle');
      final title = _rect(tester, 'play-source-title');
      expect(title.top - handle.bottom, RivuletSpacing.s16);
      await _golden(tester, 'play_source_sheet_phone');
      await built.dispose();
    });

    _test('sort is an AppChip that opens a choice dialog', (tester) async {
      final built = await p06MatrixFixtures['play_source']!();
      await _pump(tester, 'desktop', built.widget);
      final chip = find.byKey(const ValueKey<String>('stream-sort'));
      expect(
        tester.widget<AppChip>(chip).icon,
        PhosphorIconsRegular.sortAscending,
      );
      await tester.tap(chip);
      // The second provider's orb loops, so the page never settles.
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey<String>('choice-option-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('choice-option-1')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sort: Size'), findsOneWidget);
      await built.dispose();
    });
  });

  group('owner fixes p03b', () {
    _test('Cast row: titled "Cast", director first, 2:3 radius-14 cards', (
      tester,
    ) async {
      await _pump(tester, 'desktop', _movie());
      expect(find.text('Cast'), findsOneWidget);
      expect(find.text('People'), findsNothing);
      final first = find.byKey(const ValueKey<String>('people-item-0'));
      expect(
        find.descendant(of: first, matching: find.text('Ines Halvorsen')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('Director')),
        findsOneWidget,
      );
      for (var i = 0; i < 3; i++) {
        final card = find.byKey(ValueKey<String>('people-item-$i'));
        final thumb = tester.getSize(
          find.descendant(
            of: card,
            matching: find.byKey(const ValueKey<String>('cast-thumb')),
          ),
        );
        expect(thumb.width / thumb.height, closeTo(2 / 3, 0.001));
        final clip = tester.widget<ClipRRect>(
          find.descendant(of: card, matching: find.byType(ClipRRect)),
        );
        expect(clip.borderRadius, BorderRadius.circular(RivuletRadius.medium));
      }
    });

    _test('no quality badges in the hero; certification stays', (tester) async {
      await _pump(tester, 'desktop', _movie());
      expect(find.text('4K'), findsNothing);
      expect(find.textContaining('HDR'), findsNothing);
      expect(find.text('PG-13'), findsOneWidget);
    });

    _test('rating score uses the meta caption style', (tester) async {
      await _pump(tester, 'desktop', _movie());
      final meta = tester.widget<Text>(find.text('1h 52m')).style!;
      for (final score in const <String>['7.8', '91%']) {
        final style = tester.widget<Text>(find.text(score)).style!;
        expect(style.fontSize, meta.fontSize);
        expect(style.fontWeight, meta.fontWeight);
        expect(style.color, meta.color);
      }
    });

    for (final factor in const <String>['phone', 'desktop', 'tv']) {
      _test('source rows: info buttons and chevrons share one right edge '
          '($factor)', (tester) async {
        final built = await p06MatrixFixtures['play_source']!();
        await _pump(tester, factor, built.widget);
        final rows = find.descendant(
          of: find.byKey(const ValueKey<String>('play-source-streams')),
          matching: find.byType(AppRow),
        );
        expect(rows, findsNWidgets(3));
        final infoRights = <double>{};
        for (var i = 0; i < 3; i++) {
          final row = rows.at(i);
          final rowRect = tester.getRect(row);
          final info = tester.getRect(
            find.descendant(
              of: row,
              matching: find.byKey(const ValueKey<String>('stream-info')),
            ),
          );
          final chevron = tester.getRect(
            find.descendant(
              of: row,
              matching: find.byIcon(PhosphorIconsRegular.caretRight),
            ),
          );
          infoRights.add(info.right);
          expect(chevron.left, greaterThan(info.right));
          expect(rowRect.right - chevron.right, RivuletSpacing.s16);
        }
        expect(infoRights.length, 1);
        await built.dispose();
      });
    }
  });

  group('worst-case goldens', () {
    for (final factor in const <String>['phone', 'desktop']) {
      _test('movie_detail_worst_case_$factor', (tester) async {
        await _pump(tester, factor, _movie(worstCase: true));
        await _golden(tester, 'movie_detail_worst_case_$factor');
      });
    }
  });

  group('fact line', () {
    for (final factor in ['phone', 'desktop', 'tv']) {
      _test('$factor: 16 px gaps, no separators, year aligned with title', (
        tester,
      ) async {
        await _pump(tester, factor, _movie());
        final facts = find.byKey(const ValueKey<String>('detail-hero-badges'));
        expect(
          find.descendant(of: facts, matching: find.text('·')),
          findsNothing,
        );
        expect(tester.widget<Wrap>(facts).spacing, 16);
        final year = find.byKey(
          const ValueKey<String>('detail-link-primary_release_year-2024'),
        );
        expect(
          tester
              .getTopLeft(
                find.descendant(of: year, matching: find.text('2024')),
              )
              .dx,
          closeTo(_rect(tester, 'detail-hero-title').left, 0.5),
        );
      });
    }
  });
}
