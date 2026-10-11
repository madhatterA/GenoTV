import 'package:contracts/contracts.dart';
import 'package:contracts/fakes/fake_repositories.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

MediaItem _item(int i, {MediaKind kind = MediaKind.movie}) => MediaItem(
  id: 'tmdb:movie:$i',
  title: 'Poster title $i',
  kind: kind,
  artwork: Uri.parse('https://example.invalid/p$i?ar=poster'),
);

Future<Widget> _scoped(WidgetTester tester, Widget child) async =>
    ArtworkResolverScope(
      resolver: await loadFixtureArtworkResolver(tester),
      child: MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('every card shows its name: row, grid and shelf share one card', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1400, 900));
    final items = [for (var i = 0; i < 4; i++) _item(i)];
    await tester.pumpWidget(
      await _scoped(
        tester,
        Column(
          children: [
            MediaRow(
              title: 'Liked',
              items: items,
              memory: FocusMemory(),
              onFocused: (_) {},
            ),
            Expanded(
              child: MediaGrid(
                items: items,
                memory: FocusMemory(),
                onFocused: (_) {},
                autofocus: false,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PosterCard), findsNWidgets(8));
    expect(find.text('Poster title 0'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('title-card-name')), findsNWidgets(8));
  });

  testWidgets('a focused card has no glow', (tester) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(
      await _scoped(
        tester,
        Padding(
          padding: const EdgeInsets.only(top: 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaRow(
                title: 'Liked',
                items: [for (var i = 0; i < 3; i++) _item(i)],
                memory: FocusMemory(),
                onFocused: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final list = tester.getRect(find.byType(ListView));
    final card = tester.getRect(find.byType(FocusableCard).first);
    // The scroll viewport reaches at least the glow room beyond the card on
    // top and bottom, so nothing clips the glow in a straight line.
    expect(list.top, lessThanOrEqualTo(card.top - FocusableCard.glowInset));
    expect(
      list.bottom,
      greaterThanOrEqualTo(card.bottom + FocusableCard.glowInset),
    );
    expect(card.left - 0, greaterThanOrEqualTo(FocusableCard.glowInset));
    await tester.pumpWidget(
      await _scoped(
        tester,
        SizedBox(
          width: 200,
          height: 300,
          child: Center(
            child: FocusableCard(
              surfaceId: 's',
              itemId: 'i',
              memory: _memory,
              autofocus: true,
              width: 100,
              height: 150,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shadows = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(FocusableCard),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .expand((d) => d.boxShadow ?? const <BoxShadow>[]);
    expect(shadows, isEmpty);
  });

  testWidgets('a focused card and its glow never touch the row heading', (
    tester,
  ) async {
    for (final width in [400.0, 800.0, 1400.0]) {
      await setLogicalSize(tester, Size(width, 900));
      await tester.pumpWidget(
        await _scoped(
          tester,
          MediaRow(
            title: 'Continue watching',
            items: [for (var i = 0; i < 3; i++) _item(i)],
            memory: FocusMemory(),
            onFocused: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = tester.getRect(find.text('Continue watching'));
      final card = tester.getRect(find.byType(FocusableCard).first);
      final profile = AdaptiveBehavior.of(
        tester.element(find.byType(MediaRow)),
      );
      final scale = profile.formFactor == FormFactor.tv
          ? RivuletFocusMetrics.standard.tileFocusScaleTv
          : RivuletFocusMetrics.standard.tileFocusScale;
      // Growth on each side plus the 3 px ring and its 2 px stroke.
      final reach = card.height * (scale - 1) / 2 + 4;
      expect(card.top - reach, greaterThanOrEqualTo(heading.bottom));
      // Below the card the next row starts after the row gap.
      expect(
        RivuletSpacing.rowGap(profile.formFactor),
        greaterThanOrEqualTo(reach),
      );
    }
  });

  testWidgets('heart on a detail page likes and unlikes the title', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1400, 900));
    final repository = FakeFavouritesRepository();
    final item = _item(7);
    await tester.pumpWidget(
      FavouritesScope(
        repository: repository,
        child: await _scoped(
          tester,
          MovieDetailScreen(
            presentation: MovieDetailPresentation(item: item),
            onPlay: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final heart = find.byKey(const ValueKey('detail-like'));
    expect(heart, findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.heart), findsOneWidget);
    await tester.tap(heart);
    await tester.pumpAndSettle();
    expect(await repository.isFavourite(item.id), isTrue);
    expect(find.byIcon(PhosphorIconsFill.heart), findsOneWidget);
    await expectLater(
      find.byType(MovieDetailScreen),
      matchesGoldenFile('goldens/detail_like_heart.png'),
    );
    await tester.tap(heart);
    await tester.pumpAndSettle();
    expect(await repository.isFavourite(item.id), isFalse);
  });

  testWidgets('detail page without a favourites store has no heart', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(
      await _scoped(
        tester,
        MovieDetailScreen(
          presentation: MovieDetailPresentation(item: _item(7)),
          onPlay: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-like')), findsNothing);
  });

  // Every top-level page, at desktop and narrow-desktop widths: no text or
  // input may sit behind the floating Home pill.
  final pages = <String, Widget Function(BuildContext)>{
    'Play link': (_) => PlayLinkPage(
      recents: RecentLinks(MemorySettingsStore()),
      onPlay: (_) async => null,
      pickTorrent: () async => null,
    ),
    'Genres': (_) => GenresPage(
      genresByKind: {
        TitleKind.movie: [TitleFilterOption(1, 'Drama')],
        TitleKind.tv: [TitleFilterOption(2, 'Comedy')],
      },
      onSeeAll: (_, _) {},
    ),
    'Movies': (_) => PagedTitleGrid(
      source: (q, p) async => TitlePage(items: [_item(1)]),
      initialQuery: TitleQuery(kind: TitleKind.movie),
      title: 'Movies',
    ),
    'Liked': (_) => PagedTitleGrid(
      source: (q, p) async => TitlePage(items: [_item(1)]),
      initialQuery: TitleQuery(kind: TitleKind.movie),
      title: 'Liked',
      showFilters: false,
    ),
    'Search': (_) =>
        SearchScreen(source: (q, p) async => TitlePage(items: [_item(1)])),
  };
  for (final entry in pages.entries) {
    for (final size in const [Size(800, 600), Size(1400, 900)]) {
      testWidgets(
        '${entry.key} content never renders behind the pill at ${size.width.toInt()}',
        (tester) async {
          await setLogicalSize(tester, size);
          await tester.pumpWidget(
            ArtworkResolverScope(
              resolver: await loadFixtureArtworkResolver(tester),
              child: MaterialApp(
                localizationsDelegates: const [AppStrings.delegate],
                theme: AppTheme.dark(tv: false),
                home: AppShell(
                  activeId: 'page',
                  destinations: [
                    AppDestination(
                      id: 'page',
                      label: entry.key,
                      icon: Icons.circle,
                      builder: entry.value,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final pill = AppShellScope.pillRectOf(
            tester.element(find.byType(Scaffold).first),
          );
          expect(pill, isNot(Rect.zero));
          final sidebar = find.byType(AppSidebar);
          final candidates = [
            ...find.byType(Text).evaluate(),
            ...find.byType(EditableText).evaluate(),
          ];
          var checked = 0;
          for (final element in candidates) {
            if (find
                .descendant(
                  of: sidebar,
                  matching: find.byWidget(element.widget),
                )
                .evaluate()
                .isNotEmpty) {
              continue;
            }
            final box = element.renderObject! as RenderBox;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            checked++;
            expect(
              rect.overlaps(pill),
              isFalse,
              reason: '${element.widget} at $rect sits behind the pill $pill',
            );
          }
          expect(checked, greaterThan(0));
        },
      );
    }
  }
}

final _memory = FocusMemory();
