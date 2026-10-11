import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 01 (planning/part-04-ui/chapter-02-browse/phase-01-home.md) proof
// file. Part A of the phase: hero item cap, staged 2s/3s section-reveal
// gates, late-upgrade-without-shelf-recreation, callbacks, semantics,
// scrim stops, reduced motion, timer cancellation, and content/loading/
// empty/error goldens at four viewports.
//
// Part B adds: the secondary-action gate (Details focusable only once focus
// enters the hero; Play always focusable), hero slide cross-fade timing
// (without recreating shelves), the hero leaving focus traversal while focus
// is in the first shelf row, and Back staging (Back from the first row
// returns focus to the hero).

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

/// Rows with no "Continue watching" row, so `MediaRow`'s
/// `autofocus: index == 0 && title == 'Continue watching'` never fires —
/// isolates the "nothing has been focused yet" hero state from the
/// pre-existing row-autofocus behaviour.
List<HomeRow> _rowsWithoutAutofocus({int rowCount = 5, int itemsPerRow = 20}) {
  return <HomeRow>[
    for (var row = 0; row < rowCount; row++)
      HomeRow(
        title: 'Row $row',
        items: <MediaItem>[
          for (var index = 0; index < itemsPerRow; index++)
            MediaItem(
              id: 'r$row-i$index',
              title: 'Row $row item $index',
              kind: MediaKind.movie,
              artwork: Uri.parse(
                'https://example.invalid/$row/$index.jpg?ar=port',
              ),
            ),
        ],
      ),
  ];
}

void main() {
  group('hero item cap', () {
    test('heroItems is capped at 9 even when the row holds more', () {
      final model = HomeViewModel(rows: _rowsWithoutAutofocus(itemsPerRow: 20));
      expect(heroItemCap, 9);
      expect(model.heroItems.length, 9);
      expect(model.heroItems, model.rows.first.items.sublist(0, 9));
    });

    test('heroItems is unaffected by focusing an item outside the cap', () {
      final model = HomeViewModel(rows: _rowsWithoutAutofocus(itemsPerRow: 20));
      final before = model.heroItems;
      model.focus(model.rows.first.items[15]);
      expect(model.heroItems, before);
    });
  });

  group('hero default (phone broken-image bug fix)', () {
    test('hero getter defaults to the first hero item before any focus', () {
      final model = HomeViewModel(rows: _rowsWithoutAutofocus());
      expect(model.hero, model.heroItems.first);
    });

    testWidgets(
      'hero backdrop shows the first item\'s title/art with nothing focused',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        final rows = _rowsWithoutAutofocus();
        await setLogicalSize(tester, const Size(400, 800));
        await tester.pumpWidget(
          ArtworkResolverScope(
            resolver: resolver,
            child: _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
          ),
        );
        await tester.pump();
        expect(find.text(rows.first.items.first.title), findsWidgets);
        // The old bug: no focus yet -> `HeroBackdrop.item == null` -> a null
        // artwork provider -> `ArtworkView`'s failure placeholder
        // ("Artwork unavailable"). That semantic label must not appear.
        expect(find.bySemanticsLabel('Artwork unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('staged section reveal (2s / 3s fake-time gates)', () {
    testWidgets('deferred rows are hidden, then revealed at 2s and 3s', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 1);
      await setLogicalSize(tester, const Size(800, 3000));
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('row-Row 0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('row-Row 3')), findsNothing);
      expect(find.byKey(const ValueKey<String>('row-Row 4')), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey<String>('row-Row 3')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('row-Row 4')), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey<String>('row-Row 4')), findsOneWidget);
    });

    testWidgets('sections already ready reveal immediately, no wait', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 1);
      await setLogicalSize(tester, const Size(800, 3000));
      await tester.pumpWidget(
        _app(
          HomeScreen(
            viewModel: HomeViewModel(
              rows: rows,
              firstDeferredSectionReady: true,
              secondDeferredSectionReady: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('row-Row 3')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('row-Row 4')), findsOneWidget);
    });

    testWidgets('marking a section ready before its timer cancels the timer', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 1);
      final model = HomeViewModel(rows: rows);
      await setLogicalSize(tester, const Size(800, 3000));
      await tester.pumpWidget(_app(HomeScreen(viewModel: model)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      model.markFirstDeferredSectionReady();
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('row-Row 3')), findsOneWidget);
      // Advancing past the original 2s deadline must not double-fire/throw.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing the screen before a gate fires cancels its timer', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 1);
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();
      await tester.pumpWidget(_app(const SizedBox.shrink()));
      // If the 2s/3s timers weren't cancelled on dispose, this would call
      // setState on an unmounted State and throw.
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new home session cancels the previous session\'s timers', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 1);
      await setLogicalSize(tester, const Size(800, 3000));
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();
      // Same widget, new HomeViewModel instance == a new session.
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('row-Row 3')), findsOneWidget);
    });
  });

  group('late upgrade without shelf recreation', () {
    testWidgets(
      'upgrading the focused hero item updates content without recreating rows',
      (tester) async {
        final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 3);
        final model = HomeViewModel(rows: rows);
        await tester.pumpWidget(_app(HomeScreen(viewModel: model)));
        await tester.pump();

        final originalRowsRef = model.rows;
        final original = model.heroItems.first;
        expect(find.text(original.title), findsWidgets);

        final upgraded = MediaItem(
          id: original.id,
          title: '${original.title} (upgraded)',
          kind: original.kind,
          artwork: original.artwork,
        );
        model.upgradeItem(upgraded);
        await tester.pump();

        expect(model.hero, upgraded);
        expect(find.text(upgraded.title), findsWidgets);
        // Same `rows` list identity: the shelf/row structure itself was
        // never torn down and rebuilt, only the one item's data changed.
        expect(model.rows, same(originalRowsRef));
        expect(
          find.byKey(ValueKey<String>('row-${rows.first.title}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    test('upgradeItem is a no-op for an unknown id', () {
      final model = HomeViewModel(rows: _rowsWithoutAutofocus());
      final before = model.hero;
      model.upgradeItem(
        const MediaItem(
          id: 'does-not-exist',
          title: 'x',
          kind: MediaKind.movie,
        ),
      );
      expect(model.hero, before);
    });
  });

  group('scrims', () {
    testWidgets('the hero uses scrimSide and scrimBottom under one fade', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus();
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();

      final colors = RivuletTokens.of(
        tester.element(find.byKey(const ValueKey<String>('home-screen'))),
      ).colors;
      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>()
          .toList();
      expect(gradients, contains(colors.scrimSide));
      expect(gradients, contains(colors.scrimBottom));

      // The bottom fade is an alpha mask (AmbientFade), not an opaque
      // bgBase band, so the ambient background continues under the rows.
      expect(find.byType(AmbientFade), findsOneWidget);
    });
  });

  group('callbacks', () {
    testWidgets(
      'hero Play and Details open the item, a page dot pages the hero',
      (tester) async {
        final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 3);
        final model = HomeViewModel(rows: rows);
        final opened = <MediaItem>[];
        await tester.pumpWidget(
          _app(HomeScreen(viewModel: model, onItemTap: opened.add)),
        );
        await tester.pump();
        final hero = model.hero!;

        await tester.tap(find.text('Play'));
        await tester.pump();
        await tester.tap(find.text('Details'));
        await tester.pump();
        expect(opened, <MediaItem>[hero, hero]);

        await tester.tap(find.byKey(const ValueKey<String>('hero-dot-2')));
        await tester.pump();
        expect(model.hero, model.heroItems[2]);
      },
    );

    testWidgets('error state retry fires onRetry', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        _app(
          HomeScreen(
            viewModel: HomeViewModel(
              rows: const <HomeRow>[],
              loadState: HomeLoadState.error,
              failure: const UnexpectedFailure(cause: 'boom'),
            ),
            onRetry: () => retried = true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('home-error')), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });

  group('semantics', () {
    testWidgets('hero controls and page dots expose semantic labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rows = _rowsWithoutAutofocus(rowCount: 1, itemsPerRow: 3);
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Toggle Watchlist'), findsNothing);
      expect(find.bySemanticsLabel('More info'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Featured item 1 of 3')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('reduced motion', () {
    testWidgets('disableAnimations collapses the hero slide change to zero', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus();
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: HomeScreen(viewModel: HomeViewModel(rows: rows)),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final key in const <String>[
        'hero-image-switcher',
        'hero-metadata-switcher',
      ]) {
        expect(
          tester
              .widget<AnimatedSwitcher>(find.byKey(ValueKey<String>(key)))
              .duration,
          Duration.zero,
        );
      }
    });
  });

  group('secondary-action gate', () {
    testWidgets(
      'Details is not a focus candidate until focus enters the hero, Play always is',
      (tester) async {
        final rows = _rowsWithoutAutofocus(rowCount: 5, itemsPerRow: 3);
        await tester.pumpWidget(
          _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
        );
        await tester.pump();

        FocusNode nodeOf(String key) => tester
            .widget<AppButton>(find.byKey(ValueKey<String>(key)))
            .focusNode!;

        final play = nodeOf('hero-focus-play');
        final details = nodeOf('hero-focus-details');
        expect(play.canRequestFocus, isTrue);
        expect(details.canRequestFocus, isFalse);

        // Focus enters the hero via Play.
        play.requestFocus();
        await tester.pump();

        expect(details.canRequestFocus, isTrue);
      },
    );
  });

  group('hero metadata crossfade timing', () {
    testWidgets(
      'the slide change cross-fades the picture and text over base (200 ms)',
      (tester) async {
        final rows = _rowsWithoutAutofocus();
        await tester.pumpWidget(
          _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
        );
        await tester.pump();
        final switcher = tester.widget<AnimatedSwitcher>(
          find.byKey(const ValueKey<String>('hero-metadata-switcher')),
        );
        expect(switcher.duration, RivuletMotion.base);
        expect(switcher.reverseDuration, isNull);
        expect(
          tester
              .widget<AnimatedSwitcher>(
                find.byKey(const ValueKey<String>('hero-image-switcher')),
              )
              .duration,
          RivuletMotion.base,
        );
      },
    );

    testWidgets(
      'switching the active hero item does not recreate the shelf rows',
      (tester) async {
        final rows = _rowsWithoutAutofocus(rowCount: 3, itemsPerRow: 3);
        final model = HomeViewModel(rows: rows);
        await tester.pumpWidget(_app(HomeScreen(viewModel: model)));
        await tester.pump();
        final rowElementBefore = tester.element(
          find.byKey(ValueKey<String>('row-${rows.first.title}')),
        );
        model.focus(model.heroItems[1]);
        await tester.pump(const Duration(milliseconds: 300));
        final rowElementAfter = tester.element(
          find.byKey(ValueKey<String>('row-${rows.first.title}')),
        );
        expect(rowElementAfter, same(rowElementBefore));
      },
    );
  });

  group('first-row focus and Back staging', () {
    testWidgets(
      'focusing the first shelf row takes the hero out of traversal',
      (tester) async {
        final rows = _rowsWithoutAutofocus(rowCount: 3, itemsPerRow: 3);
        await setLogicalSize(tester, const Size(800, 1400));
        await tester.pumpWidget(
          _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
        );
        await tester.pump();

        // Focus must genuinely visit the hero first — only a real
        // hero-to-shelf transition counts (see `_heroEverFocused`'s doc
        // comment in `home_screen.dart`).
        final play = tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('hero-focus-play')),
            )
            .focusNode!;
        play.requestFocus();
        await tester.pump();
        expect(play.canRequestFocus, isTrue);

        await tester.tap(find.byKey(const ValueKey<String>('r0-i0')));
        await tester.pumpAndSettle();

        expect(play.canRequestFocus, isFalse);
      },
    );

    testWidgets('Back from the first row returns focus to the hero', (
      tester,
    ) async {
      final rows = _rowsWithoutAutofocus(rowCount: 3, itemsPerRow: 3);
      await setLogicalSize(tester, const Size(800, 1400));
      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
      );
      await tester.pump();
      final play = tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('hero-focus-play')),
          )
          .focusNode!;
      play.requestFocus();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('r0-i0')));
      await tester.pumpAndSettle();
      expect(play.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(play.hasFocus, isTrue);
    });
  });

  group('four-viewport goldens', () {
    testWidgets(
      'content golden at phone, tablet, desktop and reference widths',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        for (final size in const <Size>[
          Size(400, 800),
          Size(800, 800),
          Size(1400, 900),
          Size(1920, 1080),
        ]) {
          await setLogicalSize(tester, size);
          await tester.pumpWidget(
            ArtworkResolverScope(
              resolver: resolver,
              child: _app(
                HomeScreen(viewModel: HomeViewModel(rows: fixtureHomeRows())),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await expectLater(
            find.byKey(const ValueKey<String>('home-screen')),
            matchesGoldenFile(
              'goldens/browse_home_content_${size.width.toInt()}.png',
            ),
          );
        }
      },
    );

    testWidgets('loading/empty/error state goldens', (tester) async {
      await setLogicalSize(tester, const Size(800, 800));
      await tester.pumpWidget(
        _app(
          HomeScreen(
            viewModel: HomeViewModel(
              rows: const <HomeRow>[],
              loadState: HomeLoadState.loading,
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey<String>('home-screen')),
        matchesGoldenFile('goldens/browse_home_loading_800.png'),
      );

      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: const <HomeRow>[]))),
      );
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey<String>('home-empty')),
        matchesGoldenFile('goldens/browse_home_empty_800.png'),
      );

      await tester.pumpWidget(
        _app(
          HomeScreen(
            viewModel: HomeViewModel(
              rows: const <HomeRow>[],
              loadState: HomeLoadState.error,
              failure: const UnexpectedFailure(cause: 'boom'),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey<String>('home-error')),
        matchesGoldenFile('goldens/browse_home_error_800.png'),
      );
    });
  });
}
