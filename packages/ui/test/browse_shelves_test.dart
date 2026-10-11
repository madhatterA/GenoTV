import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 02 (planning/part-04-ui/chapter-02-browse/phase-02-library-browse.md)
// proof file: `MediaShelf`/`PosterCard`/`ContinueCard`/`MediaContextMenu`.
// Geometry/decisions cited inline at each assertion.

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark(tv: false),
  home: Scaffold(
    body: DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.dark(tv: false)
            .extension<RivuletTokens>()!
            .colors
            .ambientGlow,
      ),
      child: child,
    ),
  ),
);

/// Presses arrow-right [times] times. `MediaShelf`'s outer `Focus`
/// autofocuses on mount with nothing selected, so the FIRST press lands on
/// index 0 — [times] presses land on index `times - 1`.
Future<void> _stepFocusRight(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

List<MediaItem> _items(
  int count, {
  String prefix = 'row',
  bool episodes = false,
}) => <MediaItem>[
  for (var i = 0; i < count; i++)
    MediaItem(
      id: '$prefix-$i',
      title: '$prefix item $i',
      kind: episodes ? MediaKind.episode : MediaKind.movie,
      subtitle: episodes ? 'S1E${i + 1} · Episode ${i + 1}' : null,
      artwork: Uri.parse(
        'https://example.invalid/$prefix/$i.jpg?ar=${episodes ? 'land' : 'port'}',
      ),
    ),
];

void main() {
  group('progress_format', () {
    test('seasonEpisodeLabel parses SxxEyy prefixes', () {
      expect(seasonEpisodeLabel('S1E2 · Sample'), 'S1, E2');
      expect(seasonEpisodeLabel('S02E04 · Sample Episode'), 'S2, E4');
      expect(seasonEpisodeLabel(null), isNull);
      expect(seasonEpisodeLabel('No pattern here'), isNull);
    });

    test('formatRemaining renders Xh Ym / Ym and omits sub-minute values', () {
      expect(formatRemaining(const Duration(hours: 1, minutes: 7)), '1h 7m');
      expect(formatRemaining(const Duration(minutes: 35)), '35m');
      expect(formatRemaining(const Duration(hours: 2)), '2h');
      expect(formatRemaining(const Duration(seconds: 30)), isNull);
      expect(formatRemaining(null), isNull);
    });

    test(
      'progressInfoText joins season/episode and remaining, or returns null',
      () {
        expect(
          progressInfoText(
            subtitle: 'S1E2 · x',
            remaining: const Duration(minutes: 35),
          ),
          'S1, E2 • 35m',
        );
        expect(
          progressInfoText(
            subtitle: null,
            remaining: const Duration(minutes: 35),
          ),
          '35m',
        );
        expect(
          progressInfoText(subtitle: 'S1E2 · x', remaining: null),
          'S1, E2',
        );
        expect(progressInfoText(subtitle: null, remaining: null), isNull);
      },
    );
  });

  group('row metrics (DESIGN_SPEC §4.3, §4.5, §9.5)', () {
    Future<RowMetrics> pumpShelf(
      WidgetTester tester,
      Size size, {
      bool continueRow = false,
    }) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, size);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: continueRow ? 'Continue watching' : 'Recently Added',
              isContinueRow: continueRow,
              items: _items(6, prefix: continueRow ? 'cw' : 'row'),
              memory: FocusMemory(),
              onFocused: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return RowMetrics.of(
        tester.element(find.byType(MediaShelf)),
        continueRow: continueRow,
      );
    }

    testWidgets('poster row: sizes, gutter and gap come from the tokens', (
      tester,
    ) async {
      final metrics = await pumpShelf(tester, const Size(1920, 1080));
      final sizes = AdaptiveBehavior.sizesOf(
        tester.element(find.byType(MediaShelf)),
      );
      final firstCard = tester.getRect(
        find.byKey(const ValueKey<String>('row-0')),
      );
      final secondCard = tester.getRect(
        find.byKey(const ValueKey<String>('row-1')),
      );
      expect(metrics.width, sizes.posterWidth);
      expect(firstCard.width, sizes.posterWidth);
      expect(
        firstCard.height,
        closeTo(
          sizes.posterHeight +
              PosterCard.captionBlockHeight(
                tester.element(find.byType(MediaShelf)),
              ),
          0.5,
        ),
      );
      expect(firstCard.left, metrics.gutter);
      expect(secondCard.left - firstCard.right, closeTo(metrics.gap, 0.5));
    });

    testWidgets('continue-watching row: 16:9 art, card taller by the title', (
      tester,
    ) async {
      final metrics = await pumpShelf(
        tester,
        const Size(1920, 1080),
        continueRow: true,
      );
      final sizes = AdaptiveBehavior.sizesOf(
        tester.element(find.byType(MediaShelf)),
      );
      final firstCard = tester.getRect(
        find.byKey(const ValueKey<String>('cw-0')),
      );
      expect(metrics.width, sizes.continueCardWidth);
      expect(firstCard.width, sizes.continueCardWidth);
      expect(
        firstCard.height,
        closeTo(
          sizes.continueCardHeight +
              PosterCard.captionBlockHeight(
                tester.element(find.byType(MediaShelf)),
              ),
          0.5,
        ),
      );
    });

    testWidgets('the poster width follows the window (desktop, then phone)', (
      tester,
    ) async {
      var metrics = await pumpShelf(tester, const Size(800, 900));
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('row-0'))).width,
        metrics.width,
      );
      expect(metrics.width, 150.0);
      metrics = await pumpShelf(tester, const Size(500, 900));
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('row-0'))).width,
        metrics.width,
      );
      expect(metrics.width, 112.0);
    });
  });

  group('focus movement', () {
    testWidgets('arrow-right moves focus exactly one item at a time', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      final focused = <String>[];
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Row',
              items: _items(10),
              memory: memory,
              onFocused: (item) => focused.add(item.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The shelf's outer `Focus` autofocuses on mount; the first
      // arrow-right moves selection from "nothing" onto the first tile.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focused.last, 'row-0');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focused.last, 'row-1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focused.last, 'row-2');
    });
  });

  group('tap / long-press / physical play-pause', () {
    testWidgets('tap activates the tile', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      MediaItem? tapped;
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Row',
              items: _items(3),
              memory: memory,
              onFocused: (_) {},
              onItemTap: (item) => tapped = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('row-1')));
      await tester.pumpAndSettle();
      expect(tapped?.id, 'row-1');
    });

    testWidgets('long-press opens the context menu', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Continue watching',
              isContinueRow: true,
              items: _items(3, prefix: 'cw'),
              memory: memory,
              onFocused: (_) {},
              onRemove: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey<String>('cw-0')));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Continue Watching'), findsOneWidget);
    });

    testWidgets(
      'long-press on a non-continue row with no onRemove opens nothing',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        await setLogicalSize(tester, const Size(1920, 1080));
        final memory = FocusMemory();
        await tester.pumpWidget(
          ArtworkResolverScope(
            resolver: resolver,
            child: _app(
              MediaShelf(
                title: 'Row',
                items: _items(3),
                memory: memory,
                onFocused: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(const ValueKey<String>('row-0')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets('physical Play/Pause activates the focused tile', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      MediaItem? activated;
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Row',
              items: _items(3),
              memory: memory,
              onFocused: (_) {},
              onItemTap: (item) => activated = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _stepFocusRight(tester, 2); // index 0, then index 1
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(activated?.id, 'row-1');
    });
  });

  group('pagination', () {
    testWidgets(
      'fires once when focus enters the final five items, not again for the same count',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        await setLogicalSize(tester, const Size(1920, 1080));
        final memory = FocusMemory();
        var loadMoreCalls = 0;
        await tester.pumpWidget(
          ArtworkResolverScope(
            resolver: resolver,
            child: _app(
              MediaShelf(
                title: 'Row',
                items: _items(10),
                memory: memory,
                onFocused: (_) {},
                onLoadMore: () => loadMoreCalls++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Index 5..9 are within the last five of 10; land on index 6.
        await _stepFocusRight(tester, 7);
        expect(loadMoreCalls, 1);

        await _stepFocusRight(tester, 1); // one more step: index 7
        // Same item count (no page appended yet) — must not refire.
        expect(loadMoreCalls, 1);
      },
    );

    testWidgets(
      'fires again once more items are appended and focus re-enters the tail',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        await setLogicalSize(tester, const Size(1920, 1080));
        final memory = FocusMemory();
        var loadMoreCalls = 0;
        var items = _items(10);
        await tester.pumpWidget(
          ArtworkResolverScope(
            resolver: resolver,
            child: _app(
              StatefulBuilder(
                builder: (context, setState) => MediaShelf(
                  title: 'Row',
                  items: items,
                  memory: memory,
                  onFocused: (_) {},
                  onLoadMore: () => setState(() {
                    loadMoreCalls++;
                    items = _items(15);
                  }),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _stepFocusRight(tester, 7); // index 6
        expect(loadMoreCalls, 1);

        await _stepFocusRight(tester, 5); // index 6 -> index 11
        await tester.pumpAndSettle();
        expect(loadMoreCalls, 2);
      },
    );
  });

  group('append identity', () {
    testWidgets('appending pages does not reset horizontal scroll offset', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(600, 900));
      final memory = FocusMemory();
      var items = _items(30);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Row',
              items: items,
              memory: memory,
              onFocused: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(MediaShelf), const Offset(-600, 0));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final offsetBefore = scrollable.position.pixels;
      expect(offsetBefore, greaterThan(0));

      items = _items(40);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Row',
              items: items,
              memory: memory,
              onFocused: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final offsetAfter = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(offsetAfter, offsetBefore);
    });
  });

  group('optimistic removal', () {
    testWidgets('removes immediately and stays removed on success', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MediaShelf(
              title: 'Continue watching',
              isContinueRow: true,
              items: _items(3, prefix: 'cw'),
              memory: memory,
              onFocused: (_) {},
              onRemove: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey<String>('cw-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Continue Watching'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('cw-0')), findsNothing);
    });

    testWidgets(
      'restores the card at its original index and refocuses it on failure',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        await setLogicalSize(tester, const Size(1920, 1080));
        final memory = FocusMemory();
        await tester.pumpWidget(
          ArtworkResolverScope(
            resolver: resolver,
            child: _app(
              MediaShelf(
                title: 'Continue watching',
                isContinueRow: true,
                items: _items(3, prefix: 'cw'),
                memory: memory,
                onFocused: (_) {},
                onRemove: (_) async => false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(const ValueKey<String>('cw-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from Continue Watching'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('cw-1')), findsOneWidget);
        final order = tester
            .widgetList<FocusableCard>(find.byType(FocusableCard))
            .map((card) => card.itemId)
            .toList();
        expect(order, <String>['cw-0', 'cw-1', 'cw-2']);
        expect(tester.binding.focusManager.primaryFocus?.debugLabel, 'cw-1');
      },
    );
  });

  group('poster/continue goldens', () {
    testWidgets('poster and continue-watching shelves at 1920x1080', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final memory = FocusMemory();
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            Column(
              children: <Widget>[
                MediaShelf(
                  title: 'Continue watching',
                  isContinueRow: true,
                  items: _items(5, prefix: 'cw', episodes: true),
                  memory: memory,
                  onFocused: (_) {},
                ),
                MediaShelf(
                  title: 'Recently Added',
                  items: _items(8),
                  memory: memory,
                  onFocused: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/browse_shelves_1920.png'),
      );
    });
  });
}
