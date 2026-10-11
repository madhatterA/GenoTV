import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// `Scaffold`, not a bare `home:`: production always hosts `HomeScreen` inside
// `AppShell`'s own `Scaffold` — without one here, descendant `Text` loses
// the `Material`-provided default text style entirely (no `Roboto`
// fallback), which is invisible on a host with a system fallback font but
// renders as tofu/placeholder glyphs under `flutter test`'s font-less
// environment. See `decisions.md`.
Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

Future<void> _historyGolden(WidgetTester tester) async {
  final resolver = await loadFixtureArtworkResolver(tester);
  final fixtures = fixtureHomeRows();
  final rows = [
    HomeRow(
      title: 'Trending Movies',
      items: fixtures[1].items.take(4).toList(),
    ),
    HomeRow(title: 'Trending Shows', items: fixtures[2].items.take(4).toList()),
    HomeRow(title: 'Liked', items: fixtures[1].items.reversed.take(4).toList()),
    HomeRow(
      title: 'Watched',
      items: fixtures[2].items.reversed.take(3).toList(),
    ),
  ];
  await setLogicalSize(tester, const Size(800, 1800));
  await tester.pumpWidget(
    ArtworkResolverScope(
      resolver: resolver,
      child: _app(HomeScreen(viewModel: HomeViewModel(rows: rows))),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(
    find.byKey(const ValueKey<String>('home-screen')),
    matchesGoldenFile('goldens/home_history_800.png'),
  );
}

void main() {
  testWidgets(
    'trending, Liked and Watched rows and the single Play action',
    _historyGolden,
  );
  testWidgets(
    'fixture rows render exact cards, hero follows focus, and rows stay scoped',
    (tester) async {
      final rows = fixtureHomeRows();
      final model = HomeViewModel(rows: rows);
      final builds = <String, int>{};
      // Not a golden test: this call is not affected by the
      // setSurfaceSize/devicePixelRatio golden-width bug (see
      // bug_history.md), left as-is to avoid changing this test's
      // long-standing virtualization behavior.
      await tester.binding.setSurfaceSize(const Size(4000, 800));
      await tester.pumpWidget(
        _app(
          HomeScreen(
            viewModel: model,
            onRowBuild: (title) => builds[title] = (builds[title] ?? 0) + 1,
          ),
        ),
      );
      await tester.pump();

      final firstRow = find.byKey(
        const ValueKey<String>('row-Continue watching'),
      );
      final realizedCards = find
          .descendant(of: firstRow, matching: find.byType(FocusableCard))
          .evaluate()
          .length;
      expect(realizedCards, greaterThan(0));
      expect(realizedCards, lessThanOrEqualTo(rows.first.items.length));
      // Poster/CW tiles no longer render a title caption over the artwork
      // (`PosterCell.swift:12-15`: the caption block stays reserved but
      // unused — the title surfaces in the preview popover instead), so
      // identity is checked by the card's item-id key, not visible text.
      expect(
        find.descendant(
          of: firstRow,
          matching: find.byKey(ValueKey<String>(rows.first.items.first.id)),
        ),
        findsOneWidget,
      );
      // Nothing grabs focus on mount any more (DESIGN_SPEC §6.4 rule 9): the
      // page entry decides, and only in keyboard/remote mode.
      await tester.tap(find.byKey(ValueKey<String>(rows.first.items.first.id)));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        rows.first.items.first.id,
      );
      expect(model.hero, rows.first.items.first);

      final focusedCard = find.byKey(ValueKey<String>(rows.first.items[10].id));
      await tester.ensureVisible(focusedCard);
      await tester.pumpAndSettle();
      await tester.tap(focusedCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(model.hero, rows.first.items[10]);
      expect(find.text(rows.first.items[10].title), findsWidgets);
      expect(builds.values.every((count) => count <= 2), isTrue);
      // ignore: avoid_print
      print('row builds after focus: $builds');
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'missing artwork, progress, long titles, and empty state are safe',
    (tester) async {
      final rows = fixtureHomeRows();
      final progress = <String, PlaybackProgress>{
        rows.first.items.first.id: PlaybackProgress(
          mediaId: rows.first.items.first.id,
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 10),
          updatedAt: DateTime.utc(2026, 1, 1),
          completed: false,
        ),
      };
      await tester.pumpWidget(
        _app(
          HomeScreen(
            viewModel: HomeViewModel(rows: rows),
            progress: progress,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is ProgressBar && w.fraction == 0.2),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _app(HomeScreen(viewModel: HomeViewModel(rows: const <HomeRow>[]))),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('home-empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home layout is stable at phone, tablet, and desktop widths', (
    tester,
  ) async {
    final resolver = await loadFixtureArtworkResolver(tester);
    for (final size in const <Size>[
      Size(400, 800),
      Size(800, 800),
      Size(1400, 900),
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
        matchesGoldenFile('goldens/home_${size.width.toInt()}.png'),
      );
    }
  });
}
