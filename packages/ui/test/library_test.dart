import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: child,
);

void main() {
  testWidgets('2000-item library stays lazy and preserves fixture edges', (
    tester,
  ) async {
    final items = fixtureLibraryItems();
    await tester.pumpWidget(
      _app(LibraryScreen(items: items, scope: BrowseScope.movies)),
    );
    await tester.pump();
    final realized = find.byType(FocusableCard).evaluate().length;
    expect(realized, lessThan(60));
    expect(find.text(items.first.title), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(items.last.title),
      800,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 250,
    );
    expect(find.text(items.last.title), findsOneWidget);
    // ignore: avoid_print
    print('realized FocusableCards at top: $realized');
  });

  testWidgets('filter and empty-library states are distinct', (tester) async {
    await tester.pumpWidget(
      _app(
        LibraryScreen(
          items: fixtureLibraryItems(count: 20),
          scope: BrowseScope.movies,
          genres: const [TitleFilterOption(1, 'Drama')],
        ),
      ),
    );
    await tester.pump();
    // The items carry no metadata, so the Drama chip matches none of them.
    await tester.tap(find.byKey(const ValueKey<String>('filter-chip-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('library-filter-empty')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('library-empty')), findsNothing);

    await tester.pumpWidget(
      _app(
        const LibraryScreen(items: <MediaItem>[], scope: BrowseScope.movies),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('library-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('library-filter-empty')),
      findsNothing,
    );
  });

  testWidgets('title sort retains focused item identity', (tester) async {
    final items = fixtureLibraryItems(count: 40);
    final memory = FocusMemory();
    await tester.pumpWidget(
      _app(
        LibraryScreen(items: items, scope: BrowseScope.movies, memory: memory),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('grid-library-0')));
    await tester.pump();
    expect(memory.lastFocused('library'), 'library-0');

    await tester.tap(find.byKey(const ValueKey<String>('filter-chip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z').last);
    await tester.pumpAndSettle();
    expect(memory.lastFocused('library'), 'library-0');
    final sorted = List<MediaItem>.of(items)
      ..sort((a, b) => a.title.compareTo(b.title));
    expect(find.text(sorted.first.title), findsOneWidget);
  });

  testWidgets('grid changes columns at phone, tablet, and desktop widths', (
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
            LibraryScreen(
              items: fixtureLibraryItems(count: 40),
              scope: BrowseScope.movies,
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(LibraryScreen),
        matchesGoldenFile('goldens/library_${size.width.toInt()}.png'),
      );
    }
  });
}
