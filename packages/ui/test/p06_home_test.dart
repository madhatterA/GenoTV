import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';

// Part 06 ch03 p01: Home (DESIGN_SPEC §8.1). Decode size (P7), first-load
// entry, image fade, blur/shadow limits, and the loading and worst-case
// goldens.

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

typedef _Factor = ({Size size, double dpr, bool tv, PlatformCapabilities caps});

final Map<String, _Factor> _factors = <String, _Factor>{
  'phone': (
    size: Size(400, 800),
    dpr: 1,
    tv: false,
    caps: PlatformCapabilities.touch(),
  ),
  'desktop': (
    size: Size(1280, 800),
    dpr: 1,
    tv: false,
    caps: PlatformCapabilities(),
  ),
  'tv': (
    size: Size(960, 540),
    dpr: 2,
    tv: true,
    caps: PlatformCapabilities.directionalPad(),
  ),
};

/// Pumps [home] in the matrix harness of `p06_screen_matrix_test.dart`.
Future<void> _pump(
  WidgetTester tester,
  String factor,
  Widget home, {
  double? dpr,
  Size? size,
  bool withArtwork = true,
}) async {
  final spec = _factors[factor]!;
  debugDefaultTargetPlatformOverride = factor == 'desktop'
      ? TargetPlatform.macOS
      : TargetPlatform.android;
  final scale = dpr ?? spec.dpr;
  tester.view.physicalSize = (size ?? spec.size) * scale;
  tester.view.devicePixelRatio = scale;
  addTearDown(tester.view.reset);
  final artwork = withArtwork ? await loadFixtureArtworkResolver(tester) : null;
  Widget tree = MaterialApp(
    localizationsDelegates: const [AppStrings.delegate],
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(tv: spec.tv),
    home: AdaptiveBehavior(
      capabilities: spec.caps,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RepaintBoundary(
          key: const ValueKey<String>('p06-home'),
          child: home,
        ),
      ),
    ),
  );
  if (artwork != null) {
    tree = ArtworkResolverScope(resolver: artwork, child: tree);
  }
  await tester.pumpWidget(tree);
}

HomeViewModel _model(List<HomeRow> rows, {HomeLoadState? state}) =>
    HomeViewModel(
      rows: rows,
      loadState: state ?? HomeLoadState.content,
      firstDeferredSectionReady: true,
      secondDeferredSectionReady: true,
    );

/// Six rows of four titled, illustrated items.
List<HomeRow> _rows() => <HomeRow>[
  for (var row = 0; row < 6; row++)
    HomeRow(
      title: 'Row $row',
      items: <MediaItem>[
        for (var i = 0; i < 4; i++)
          MediaItem(
            id: 'r$row-i$i',
            title: 'Row $row title $i',
            kind: MediaKind.movie,
            year: 2020 + i,
            artwork: Uri.parse('https://example.invalid/$row/$i.jpg?ar=port'),
          ),
      ],
    ),
];

/// DESIGN_SPEC P7: ceil(rendered width x dpr / 50) x 50.
int _expectedDecodeWidth(double width, double dpr) =>
    (width * dpr / 50).ceil() * 50;

double _rowTop(WidgetTester tester, int index) =>
    tester.getTopLeft(find.byType(MediaRow).at(index)).dy;

/// The break-ui worst case: a 90 character title with no poster and no
/// backdrop, a Persian title, a row of one, a row of none, a continue row
/// with a long title and no year, and no rating anywhere (the contract has
/// none).
List<HomeRow> _worstCaseRows() => <HomeRow>[
  HomeRow(
    title: 'Trending this week on every service we know about, all of it',
    items: <MediaItem>[
      MediaItem(
        id: 'worst-0',
        title:
            'The Extraordinarily Long and Unnecessarily Detailed Title of a '
            'Film Nobody Could Fit',
        kind: MediaKind.movie,
      ),
      MediaItem(
        id: 'worst-1',
        title: 'شب‌های روشن',
        kind: MediaKind.movie,
        year: 1960,
        duration: const Duration(minutes: 87),
        artwork: Uri.parse('https://example.invalid/w/1.jpg?ar=port'),
      ),
      MediaItem(
        id: 'worst-2',
        title: 'Short',
        kind: MediaKind.movie,
        year: 2024,
        artwork: Uri.parse('https://example.invalid/w/2.jpg?ar=port'),
      ),
      MediaItem(
        id: 'worst-3',
        title: 'یک عنوان فارسی بسیار طولانی برای آزمایش برش متن در ردیف',
        kind: MediaKind.episode,
        year: 2019,
        artwork: Uri.parse('https://example.invalid/w/3.jpg?ar=port'),
      ),
      for (var i = 4; i < 9; i++)
        MediaItem(
          id: 'worst-$i',
          title: 'Film number $i',
          kind: MediaKind.movie,
          year: 2000 + i,
          artwork: Uri.parse('https://example.invalid/w/$i.jpg?ar=port'),
        ),
    ],
  ),
  const HomeRow(title: 'Hidden, no items', items: <MediaItem>[]),
  HomeRow(
    title: 'A row of one',
    items: <MediaItem>[
      MediaItem(
        id: 'worst-one',
        title: 'The only one',
        kind: MediaKind.movie,
        year: 2001,
        artwork: Uri.parse('https://example.invalid/w/one.jpg?ar=port'),
      ),
    ],
  ),
  HomeRow(
    title: 'Continue watching',
    items: <MediaItem>[
      MediaItem(
        id: 'worst-cw',
        title:
            'An Episode Whose Name Runs On and On Past Any Card Width You Have',
        kind: MediaKind.episode,
        artwork: Uri.parse('https://example.invalid/w/cw.jpg?ar=land'),
      ),
      MediaItem(
        id: 'worst-cw2',
        title: 'Next up',
        kind: MediaKind.episode,
        artwork: Uri.parse('https://example.invalid/w/cw2.jpg?ar=land'),
      ),
    ],
  ),
];

Map<String, PlaybackProgress> _progress() => <String, PlaybackProgress>{
  for (final id in const <String>['worst-cw', 'worst-cw2'])
    id: PlaybackProgress(
      mediaId: id,
      position: const Duration(minutes: 31),
      duration: const Duration(minutes: 100),
      updatedAt: DateTime.utc(2026, 10, 9),
      completed: false,
    ),
};

void main() {
  group('image decode size (P7)', () {
    for (final factor in _factors.keys) {
      _test('$factor: every picture is decoded at its display size', (
        tester,
      ) async {
        final spec = _factors[factor]!;
        final model = _model(fixtureHomeRows());
        await _pump(
          tester,
          factor,
          HomeScreen(viewModel: model),
          dpr: factor == 'phone' ? 3 : null,
        );
        await tester.pump(const Duration(milliseconds: 600));
        final dpr = factor == 'phone' ? 3.0 : spec.dpr;
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        expect(images, isNotEmpty);
        for (final image in images) {
          final provider = image.image;
          expect(provider, isA<ResizeImage>());
          final rendered = tester.getSize(find.byWidget(image)).width;
          expect(
            (provider as ResizeImage).width,
            _expectedDecodeWidth(rendered, dpr),
            reason: 'picture rendered ${rendered}px wide at dpr $dpr',
          );
        }
        model.dispose();
      });
    }
  });

  group('first-load entry (P5, §5.2)', () {
    _test('rows 0-4 fade and rise with a 40 ms stagger, once', (tester) async {
      final model = _model(_rows());
      final home = HomeScreen(viewModel: model);
      await _pump(tester, 'desktop', home, size: const Size(1280, 3000));
      await tester.pump();

      double opacityOf(int index) => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byType(MediaRow).at(index),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;

      for (var i = 0; i < 5; i++) {
        expect(opacityOf(i), lessThan(1), reason: 'row $i starts hidden');
      }
      final startTop = _rowTop(tester, 0);
      final settledTop = <double>[];

      // The 5th row (delay 4 x 40 ms) is done 200 ms after that.
      await tester.pump(const Duration(milliseconds: 200 + 4 * 40));
      for (var i = 0; i < 5; i++) {
        expect(opacityOf(i), 1, reason: 'row $i is shown');
        settledTop.add(_rowTop(tester, i));
      }
      expect(startTop - settledTop[0], 8, reason: 'rows rise 8 px');

      // The same data again: nothing animates.
      model.replaceRows(_rows());
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: await loadFixtureArtworkResolver(tester),
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: AdaptiveBehavior(
              capabilities: _factors['desktop']!.caps,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: RepaintBoundary(
                  key: const ValueKey<String>('p06-home'),
                  child: HomeScreen(viewModel: model),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        expect(opacityOf(i), 1, reason: 'row $i does not replay');
        expect(_rowTop(tester, i), settledTop[i]);
      }
      model.dispose();
    });

    _test('row 0 starts first: its opacity leads row 4 mid-way', (
      tester,
    ) async {
      final model = _model(_rows());
      await _pump(
        tester,
        'desktop',
        HomeScreen(viewModel: model),
        size: const Size(1280, 3000),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      double opacityOf(int index) => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byType(MediaRow).at(index),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(opacityOf(0), greaterThan(opacityOf(4)));
      await tester.pump(const Duration(seconds: 1));
      model.dispose();
    });

    _test('TV runs no entry animation', (tester) async {
      final model = _model(_rows());
      await _pump(
        tester,
        'tv',
        HomeScreen(viewModel: model),
        size: const Size(960, 2400),
      );
      await tester.pump();
      // The TV hero is tall, so the lazy list builds only the rows in view.
      final built = find.byType(MediaRow).evaluate().length;
      expect(built, greaterThanOrEqualTo(2));
      final first = [for (var i = 0; i < built; i++) _rowTop(tester, i)];
      await tester.pump(const Duration(seconds: 1));
      expect([for (var i = 0; i < built; i++) _rowTop(tester, i)], first);
      for (var i = 0; i < built; i++) {
        final fades = find.ancestor(
          of: find.byType(MediaRow).at(i),
          matching: find.byType(FadeTransition),
        );
        for (final fade in tester.widgetList<FadeTransition>(fades)) {
          expect(fade.opacity.value, 1);
        }
      }
      model.dispose();
    });

    _test('reduced motion runs no entry animation', (tester) async {
      final model = _model(_rows());
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pump(
        tester,
        'desktop',
        HomeScreen(viewModel: model),
        size: const Size(1280, 3000),
      );
      await tester.pump();
      final first = [for (var i = 0; i < 3; i++) _rowTop(tester, i)];
      await tester.pump(const Duration(seconds: 1));
      expect([for (var i = 0; i < 3; i++) _rowTop(tester, i)], first);
      model.dispose();
    });
  });

  group('image fade (§5.2)', () {
    _test('a picture already in memory shows with no fade', (tester) async {
      final model = _model(_rows());
      await _pump(tester, 'desktop', HomeScreen(viewModel: model));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ArtworkView),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(find.byType(RawImage), findsWidgets);
      await tester.pump(const Duration(seconds: 1));
      model.dispose();
    });
  });

  group('blur and shadow limits (P1, P3, P10)', () {
    for (final factor in _factors.keys) {
      _test('$factor: Home draws at most 2 blurs and no shadow in rows', (
        tester,
      ) async {
        final model = _model(fixtureHomeRows());
        await _pump(tester, factor, HomeScreen(viewModel: model));
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.byType(BackdropFilter).evaluate().length,
          lessThanOrEqualTo(2),
        );
        final shadows = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(MediaRow),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .expand((d) => d.boxShadow ?? const <BoxShadow>[]);
        expect(shadows, isEmpty);
        model.dispose();
      });
    }
  });

  group('empty rows', () {
    _test('a row with no items is not drawn', (tester) async {
      final model = _model(_worstCaseRows());
      await _pump(
        tester,
        'desktop',
        HomeScreen(viewModel: model),
        size: const Size(1280, 3000),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Hidden, no items'), findsNothing);
      expect(find.text('A row of one'), findsOneWidget);
      model.dispose();
    });
  });

  group('goldens', () {
    for (final factor in _factors.keys) {
      _test('home_loading_$factor', (tester) async {
        final model = _model(const <HomeRow>[], state: HomeLoadState.loading);
        await _pump(tester, factor, HomeScreen(viewModel: model));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey<String>('p06-home')),
          matchesGoldenFile('goldens/p06/home_loading_$factor.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
      });
    }

    for (final factor in const <String>['phone', 'desktop']) {
      _test('home_worst_case_$factor', (tester) async {
        final model = _model(_worstCaseRows());
        await _pump(
          tester,
          factor,
          HomeScreen(viewModel: model, progress: _progress()),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey<String>('p06-home')),
          matchesGoldenFile('goldens/p06/home_worst_case_$factor.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
      });
    }
  });
}
