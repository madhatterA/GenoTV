import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

MovieDetailPresentation _presentation({bool relatedOnly = false}) =>
    MovieDetailPresentation(
      item: fixtureSeriesPresentation().item,
      year: '2023',
      summary: fixtureSeriesPresentation().summary,
      imdbRating: '8.1',
      genres: const ['Crime', 'Drama'],
      links: relatedOnly
          ? const []
          : const [DetailLink('Crime', '80', 'with_genres')],
      cast: relatedOnly
          ? const []
          : List.generate(
              24,
              (i) => CastMember(id: i, name: 'Actor $i', role: 'Character $i'),
            ),
      about: relatedOnly ? const [] : const [AboutFact('Creator', 'Jane Doe')],
      trailers: relatedOnly
          ? const []
          : fixtureLibraryItems().take(12).toList(),
      related: fixtureLibraryItems().take(24).toList(),
    );

Future<void> _pump(
  WidgetTester tester,
  Size size,
  bool series, {
  bool relatedOnly = false,
}) async {
  await setLogicalSize(tester, size);
  final resolver = await loadFixtureArtworkResolver(tester);
  final model = SeriesViewModel(seasons: fixtureSeriesSeasons());
  addTearDown(model.dispose);
  final presentation = _presentation(relatedOnly: relatedOnly);
  await tester.pumpWidget(
    ArtworkResolverScope(
      resolver: resolver,
      child: MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(tv: false),
        home: Scaffold(
          body: series
              ? SeriesDetailScreen(
                  presentation: presentation,
                  viewModel: model,
                  onPlay: (_) {},
                  onCastTap: (_) {},
                )
              : MovieDetailScreen(
                  presentation: presentation,
                  onPlay: () {},
                  onCastTap: (_) {},
                  onRelatedTap: (_) {},
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  _vertical(tester).jumpTo(0);
  await tester.pumpAndSettle();
}

ScrollPosition _vertical(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Scrolls to the end of the page; a lazily built episode list only knows its
/// length once it has been scrolled, so it takes a second jump.
Future<void> _toBottom(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    _vertical(tester).jumpTo(_vertical(tester).maxScrollExtent);
    await tester.pumpAndSettle();
  }
}

final _related = find.byKey(const ValueKey('detail-section-related'));

/// The page is scrolled to its end: the last section ends inside the window
/// (above the 48 px bottom padding) and the back button stays reachable.
void _expectBottom(WidgetTester tester, Size size) {
  expect(_related, findsOneWidget);
  expect(
    tester.getRect(find.byType(DetailSections)).bottom,
    lessThanOrEqualTo(size.height + 0.01),
  );
  expect(_vertical(tester).pixels, greaterThan(0));
  final hero = find.byType(DetailHero, skipOffstage: false);
  if (hero.evaluate().isNotEmpty) {
    expect(tester.getRect(hero).bottom, lessThanOrEqualTo(0));
  }
  expect(find.byType(PageBackButton).hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

/// A focused section is revealed: it lies inside the window.
void _expectRelatedVisible(WidgetTester tester, Size size) {
  final rect = tester.getRect(_related);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(size.height + 0.01));
}

Future<void> _horizontal(WidgetTester tester, Finder section) async {
  await tester.ensureVisible(section);
  await tester.pumpAndSettle();
  final row = tester.widget(section) is ListView
      ? section
      : find.descendant(of: section, matching: find.byType(ListView)).first;
  final scrollable = find.descendant(
    of: row,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  final before = position.pixels;
  final verticalBefore = _vertical(tester).pixels;
  await tester.drag(row, const Offset(-320, 0));
  await tester.pumpAndSettle();
  expect(position.pixels, greaterThan(before));
  expect(_vertical(tester).pixels, closeTo(verticalBefore, 0.1));
}

void main() {
  for (final series in [false, true]) {
    final name = series ? 'series' : 'movie';
    for (final size in const [
      Size(390, 844),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets('$name scroll and horizontal rows at $size', (tester) async {
        await _pump(tester, size, series);
        expect(tester.getRect(find.byType(DetailHero)).top, 0);
        await _toBottom(tester);
        _expectBottom(tester, size);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('detail-section-cast')))
              .bottom,
          lessThan(tester.getRect(_related).top),
        );
        await _horizontal(
          tester,
          find.byKey(const ValueKey('detail-section-cast')),
        );
        await _horizontal(tester, _related);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$name TV D-pad down reaches similar titles', (tester) async {
      const size = Size(1920, 1080);
      await _pump(tester, size, series);
      tester
          .widget<AppButton>(find.byKey(const ValueKey('detail-play-action')))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      var reached = false;
      for (var i = 0; i < 60 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final context = FocusManager.instance.primaryFocus?.context;
        reached =
            context != null &&
            context.findAncestorWidgetOfExactType<MediaShelf>()?.title ==
                'More like this';
      }
      expect(reached, isTrue);
      _expectRelatedVisible(tester, size);
    });

    testWidgets('$name desktop top and bottom goldens', (tester) async {
      const size = Size(1440, 900);
      await _pump(tester, size, series);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/detail_scroll_${name}_top.png'),
      );
      await _toBottom(tester);
      _expectBottom(tester, size);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/detail_scroll_${name}_bottom.png'),
      );
    });
  }

  testWidgets('series related-only presentation is retained', (tester) async {
    await _pump(tester, const Size(1440, 900), true, relatedOnly: true);
    await _toBottom(tester);
    expect(_related, findsOneWidget);
  });
}
