import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

void main() {
  group('RivuletGeometry — every value equals its cited Swift constant', () {
    const geometry = RivuletGeometry.standard;

    test('poster / continue-watching tiles', () {
      // MediaRowMetrics.swift:53-54
      expect(geometry.posterWidth, 296);
      expect(geometry.posterHeight, 444);
      // MediaRowMetrics.swift:63-64
      expect(geometry.cwWidth, 357);
      expect(geometry.cwHeight, 277);
    });

    test('shelf counts', () {
      // MediaRowMetrics.swift:67-68
      expect(geometry.shelfPosterCount, 6);
      expect(geometry.shelfCwCount, 5);
    });

    test('row chrome insets and gaps', () {
      // MediaRowMetrics.swift:77-78
      expect(geometry.rowTopInset, 8);
      expect(geometry.rowBottomInset, 8);
      // MediaRowMetrics.swift:87-88
      expect(geometry.rowLeading, 52);
      expect(geometry.rowTrailing, 52);
      // MediaRowMetrics.swift:91-92
      expect(geometry.posterGap, 8);
      expect(geometry.cwGap, 8);
    });

    test('hero button geometry', () {
      // HeroButtonRowView.swift:186-187, 208
      expect(geometry.heroPillWidth, 250);
      expect(geometry.heroPillHeight, 66);
      expect(geometry.heroButtonRadius, 33);
      // HeroButtonRowView.swift:354,387-388
      expect(geometry.heroCircleDiameter, 66);
      // PlexHomeViewController.swift:3536
      expect(geometry.heroItemCap, 9);
    });

    test('player rail geometry', () {
      // PlayerRailView.swift:19,22-26
      expect(geometry.railHeight, 260);
      expect(geometry.railPadV, 34);
      expect(geometry.railPadH, 42);
      expect(geometry.railButtonGap, 20);
      expect(geometry.railTopRowGap, 32);
      expect(geometry.railButtonDiameter, 74);
    });

    test('the shelf equation holds for posters, and peek == 44 for both shelf types', () {
      // MediaRowMetrics.swift:22-48. The comment block documents the poster
      // row as an EXACT identity (`= 1920`) but the continue-watching row as
      // an approximation (`≈ 1920`) — 2*52 + 5*357 + 4*8 = 1921, one pixel
      // over. Both share the same peek because peek = rowLeading - gap,
      // independent of the total-width rounding.
      expect(
        geometry.shelfEquationHolds(
          tileWidth: geometry.posterWidth,
          count: geometry.shelfPosterCount,
          gap: geometry.posterGap,
        ),
        isTrue,
      );
      final cwTotal =
          2 * geometry.rowLeading +
          geometry.shelfCwCount * geometry.cwWidth +
          (geometry.shelfCwCount - 1) * geometry.cwGap;
      expect(cwTotal, 1921); // documented "≈ 1920" in the source, not exact.
      expect(
        RivuletGeometry.shelfPeek(geometry.rowLeading, geometry.posterGap),
        44,
      );
      expect(
        RivuletGeometry.shelfPeek(geometry.rowLeading, geometry.cwGap),
        44,
      );
    });
  });

  group('RivuletMotion — every duration equals its cited Swift constant', () {
    const motion = RivuletMotion.standard;

    test('input timing constants from InputConfig.swift', () {
      // InputConfig.swift:14-17,28-29
      expect(motion.holdThreshold, const Duration(milliseconds: 400));
      expect(motion.seekCoalesce, const Duration(milliseconds: 50));
      expect(motion.actionDedupe, const Duration(milliseconds: 80));
      expect(motion.transportDedupe, const Duration(milliseconds: 350));
      expect(motion.scrubNudgeDedupe, const Duration(milliseconds: 250));
      expect(motion.blockDismiss, const Duration(milliseconds: 300));
    });

    test('deferred hero gates from PlexHomeViewController.swift', () {
      // PlexHomeViewController.swift:1507 (+2), :1306 (+3)
      expect(motion.heroAutoScrollGate, const Duration(seconds: 2));
      expect(motion.heroStripIdleGate, const Duration(seconds: 3));
    });
  });

  group('RivuletFocusMetrics', () {
    const focus = RivuletFocusMetrics.standard;

    test('scale constants', () {
      // DESIGN_SPEC §4.7, §5.2
      expect(focus.tileFocusScale, 1.04);
      expect(focus.tileFocusScaleTv, 1.06);
      expect(focus.tileHoverScale, 1.03);
      // TransportControlButton.swift:141
      expect(focus.railFocusScale, 1.15);
      expect(focus.pressScale, 0.97);
      // MediaRowMetrics.swift:74
      expect(focus.focusGrowthPadding, 48);
    });
  });

  group('effectiveDuration', () {
    testWidgets('zero under disableAnimations, the token otherwise', (
      tester,
    ) async {
      const token = Duration(milliseconds: 220);
      Duration? disabled;
      Duration? enabled;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              disabled = effectiveDuration(context, token);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              enabled = effectiveDuration(context, token);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(disabled, Duration.zero);
      expect(enabled, token);
    });
  });

  group('Ui* model equality, hashCode and copyWith round-trip', () {
    test('UiMediaCard', () {
      const a = UiMediaCard(id: '1', title: 'Alpha', subtitle: 'Sub');
      const b = UiMediaCard(id: '1', title: 'Alpha', subtitle: 'Sub');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a.copyWith(title: 'Beta'),
        UiMediaCard(id: '1', title: 'Beta', subtitle: 'Sub'),
      );
      expect(a.copyWith(), a);
    });

    test('UiHeroItem', () {
      const a = UiHeroItem(id: '1', title: 'Alpha');
      expect(a, const UiHeroItem(id: '1', title: 'Alpha'));
      expect(
        a.copyWith(title: 'Beta'),
        const UiHeroItem(id: '1', title: 'Beta'),
      );
    });

    test('UiShelf', () {
      const cards = <UiMediaCard>[UiMediaCard(id: '1', title: 'Alpha')];
      const a = UiShelf(id: 's', title: 'Shelf', cards: cards);
      expect(a, const UiShelf(id: 's', title: 'Shelf', cards: cards));
      expect(a.copyWith(title: 'Renamed').title, 'Renamed');
    });

    test('UiEpisode', () {
      const a = UiEpisode(id: 'e1', seasonId: 's1', index: 1, title: 'Pilot');
      expect(
        a,
        const UiEpisode(id: 'e1', seasonId: 's1', index: 1, title: 'Pilot'),
      );
      expect(a.copyWith(index: 2).index, 2);
    });

    test('UiSeason', () {
      const a = UiSeason(
        id: 's1',
        seriesId: 'sr1',
        index: 1,
        title: 'Season 1',
        episodeIds: <String>['e1'],
      );
      expect(
        a,
        const UiSeason(
          id: 's1',
          seriesId: 'sr1',
          index: 1,
          title: 'Season 1',
          episodeIds: <String>['e1'],
        ),
      );
      expect(a.copyWith(title: 'Renamed').title, 'Renamed');
    });

    test('UiPerson', () {
      const a = UiPerson(id: 'p1', name: 'Jane');
      expect(a, const UiPerson(id: 'p1', name: 'Jane'));
      expect(a.copyWith(role: 'Director').role, 'Director');
    });

    test('UiChapter', () {
      const a = UiChapter(
        id: 'c1',
        title: 'One',
        start: Duration.zero,
        end: Duration(minutes: 5),
      );
      expect(
        a,
        const UiChapter(
          id: 'c1',
          title: 'One',
          start: Duration.zero,
          end: Duration(minutes: 5),
        ),
      );
      expect(a.copyWith(title: 'Renamed').title, 'Renamed');
    });

    test('UiMarker', () {
      const a = UiMarker(
        id: 'm1',
        kind: UiMarkerKind.intro,
        start: Duration.zero,
        end: Duration(seconds: 30),
      );
      expect(
        a,
        const UiMarker(
          id: 'm1',
          kind: UiMarkerKind.intro,
          start: Duration.zero,
          end: Duration(seconds: 30),
        ),
      );
      expect(a.copyWith(kind: UiMarkerKind.credits).kind, UiMarkerKind.credits);
    });

    test('UiTrackOption', () {
      const a = UiTrackOption(id: 't1', label: 'English', isAudio: true);
      expect(a, const UiTrackOption(id: 't1', label: 'English', isAudio: true));
      expect(a.copyWith(isSelected: true).isSelected, isTrue);
    });
  });

  group('TokenGallery rendering', () {
    Future<void> pumpGallery(
      WidgetTester tester, {
      required Size size,
      TextDirection direction = TextDirection.ltr,
      double textScale = 1.0,
    }) async {
      await setLogicalSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          builder: (context, child) => Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          // `Scaffold`, not a bare `home:`: without a `Material` ancestor,
          // descendant `Text` loses the fallback to Theme's `Roboto`
          // default entirely, which renders as tofu/placeholder glyphs
          // under `flutter test`'s font-less environment. See `decisions.md`.
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey<String>('token-gallery'),
              child: const TokenGallery(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('renders Persian samples and does not overflow under RTL', (
      tester,
    ) async {
      await pumpGallery(
        tester,
        size: const Size(844, 390),
        direction: TextDirection.rtl,
      );
      expect(find.text('فیلم ایرانی'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'text size is identical across viewport scales at a fixed TextScaler',
      (tester) async {
        await pumpGallery(tester, size: const Size(400, 800));
        final smallStyle = tester
            .widget<Text>(find.text('فیلم ایرانی').first)
            .style!;
        await pumpGallery(tester, size: const Size(1920, 1080));
        final largeStyle = tester
            .widget<Text>(find.text('فیلم ایرانی').first)
            .style!;
        expect(smallStyle.fontSize, largeStyle.fontSize);
      },
    );

    testWidgets('renders at text scale 1.0 and 2.0 without overflow', (
      tester,
    ) async {
      for (final scale in <double>[1.0, 2.0]) {
        await pumpGallery(
          tester,
          size: const Size(1280, 800),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      }
    });

    for (final size in const <Size>[
      Size(400, 800),
      Size(844, 390),
      Size(1280, 800),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'dark token gallery golden and non-flat pixels at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await pumpGallery(tester, size: size);
          final gallery = find.byKey(const ValueKey<String>('token-gallery'));
          await expectLater(
            gallery,
            matchesGoldenFile(
              'goldens/token_sheet_${size.width.toInt()}x${size.height.toInt()}.png',
            ),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(gallery);
          // WidgetTester.runAsync: "use runAsync to make the async work run
          // outside of the fake zone ... lets it run in real time" — toImage
          // and toByteData are real engine/raster futures that never
          // complete inside testWidgets' fake-async zone otherwise.
          final pixels = await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return bytes!.buffer.asUint32List();
          });
          expect(pixels!.toSet().length, greaterThan(1));
        },
      );
    }
  });
}
