// Tests for `ProgressRail`
// (`packages/ui/lib/src/player/progress_rail.dart`), the port of
// `research/Rivulet/Rivulet/Views/Player/UIKit/PlayerProgressBarView.swift`,
// per `planning/part-04-ui/chapter-03-player-ui/phase-04-scrubber-thumbnails.md`.
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

/// An already-decoded, non-network image provider — same idiom as
/// `fixture_artwork.dart`'s `_FixtureImageProvider` — so thumbnail-card
/// goldens paint a real photo instead of a network placeholder, with no
/// `FileImage`/`precacheImage` deadlock risk.
class _DecodedImageProvider extends ImageProvider<_DecodedImageProvider> {
  _DecodedImageProvider(this.id, this.image);

  final String id;
  final ui.Image image;

  @override
  Future<_DecodedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DecodedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _DecodedImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
  );

  @override
  bool operator ==(Object other) =>
      other is _DecodedImageProvider && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

Future<ImageProvider> _decodeFixtureThumbnail(WidgetTester tester) async {
  final image = await tester.runAsync(() async {
    final bytes = await File(
      '${Directory.current.path}/test/fixtures/backdrop_hero.jpg',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  });
  return _DecodedImageProvider('thumb', image!);
}

/// A fixed clock for goldens/tests that render the "Ends at" wall-clock
/// label — `DateTime.now()` would make those goldens flake against real
/// time of day.
DateTime _fixedNow() => DateTime(2026, 1, 1, 15, 4);

Future<void> _pump(
  WidgetTester tester,
  Widget rail, {
  Size size = const Size(1920, 200),
}) async {
  await setLogicalSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(60, 40, 60, 20),
          child: Align(alignment: Alignment.bottomCenter, child: rail),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('formatProgressTime', () {
    test('m:ss under an hour', () {
      expect(formatProgressTime(const Duration(seconds: 65)), '1:05');
      expect(formatProgressTime(Duration.zero), '0:00');
    });

    test('h:mm:ss at or above an hour', () {
      expect(
        formatProgressTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('negative/invalid values clamp to 0:00', () {
      expect(formatProgressTime(const Duration(seconds: -5)), '0:00');
    });
  });

  group('rest-state geometry', () {
    testWidgets('renders elapsed/remaining and no scrub overlay at rest', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration(minutes: 12, seconds: 4),
          duration: Duration(hours: 1, minutes: 40),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('rail-current-time')),
        findsOneWidget,
      );
      expect(find.text('12:04'), findsOneWidget);
      expect(find.text('-1:27:56'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('rail-thumbnail-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-scrub-timecode')),
        findsNothing,
      );
    });

    testWidgets(
      'shows an Ends-at label when duration is known and not scrubbing',
      (tester) async {
        await _pump(
          tester,
          const ProgressRail(
            position: Duration(minutes: 5),
            duration: Duration(minutes: 30),
          ),
        );
        expect(
          find.byKey(const ValueKey<String>('rail-ends-at')),
          findsOneWidget,
        );
      },
    );

    testWidgets('hides the Ends-at label when duration is unknown (zero)', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(position: Duration.zero, duration: Duration.zero),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('rail-ends-at')), findsNothing);
      // Zero duration must never divide by zero / crash the painter.
      expect(find.text('0:00'), findsWidgets);
    });
  });

  group('skeleton', () {
    testWidgets('shows --:-- and hides Ends-at while loading', (tester) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration.zero,
          duration: Duration.zero,
          isSkeleton: true,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('--:--'), findsNWidgets(2));
      expect(find.byKey(const ValueKey<String>('rail-ends-at')), findsNothing);
    });

    testWidgets('the first real update after skeleton snaps to real labels', (
      tester,
    ) async {
      var isSkeleton = true;
      await setLogicalSize(tester, const Size(1920, 200));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: <Widget>[
                  ProgressRail(
                    position: const Duration(minutes: 1),
                    duration: const Duration(minutes: 10),
                    isSkeleton: isSkeleton,
                  ),
                  TextButton(
                    onPressed: () => setState(() => isSkeleton = false),
                    child: const Text('load'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('--:--'), findsNWidgets(2));
      await tester.tap(find.text('load'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('-9:00'), findsOneWidget);
    });
  });

  group('markers', () {
    testWidgets('renders with intro/credits/commercial markers without error', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration(minutes: 10),
          duration: Duration(minutes: 40),
          markers: <ProgressMarker>[
            ProgressMarker(
              kind: ProgressMarkerKind.intro,
              start: Duration.zero,
              end: Duration(seconds: 30),
            ),
            ProgressMarker(
              kind: ProgressMarkerKind.commercial,
              start: Duration(minutes: 15),
              end: Duration(minutes: 15, seconds: 5),
            ),
            ProgressMarker(
              kind: ProgressMarkerKind.credits,
              start: Duration(minutes: 38),
              end: Duration(minutes: 40),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero-width/invalid marker range is skipped, not drawn', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration.zero,
          duration: Duration(minutes: 10),
          markers: <ProgressMarker>[
            ProgressMarker(
              kind: ProgressMarkerKind.intro,
              start: Duration(minutes: 5),
              end: Duration(minutes: 5), // end == start
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('scrubbing', () {
    testWidgets('a horizontal drag enters scrub mode and shows the readout', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration(minutes: 2),
          duration: Duration(minutes: 20),
        ),
      );
      final trackFinder = find.byKey(
        const ValueKey<String>('progress-rail-track'),
      );
      final gesture = await tester.startGesture(tester.getCenter(trackFinder));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('rail-scrub-timecode')),
        findsOneWidget,
      );
      // Ends-at hides while scrubbing.
      expect(find.byKey(const ValueKey<String>('rail-ends-at')), findsNothing);
      await gesture.up();
    });

    testWidgets('onScrubUpdate/onScrubEnd fire with the dragged time', (
      tester,
    ) async {
      Duration? updated;
      Duration? ended;
      await _pump(
        tester,
        ProgressRail(
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 20),
          onScrubUpdate: (t) => updated = t,
          onScrubEnd: (t) => ended = t,
        ),
      );
      final trackFinder = find.byKey(
        const ValueKey<String>('progress-rail-track'),
      );
      final gesture = await tester.startGesture(tester.getCenter(trackFinder));
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(updated, isNotNull);
      await gesture.up();
      await tester.pump();
      expect(ended, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'shows the chapter eyebrow only when the scrub time is inside a named chapter',
      (tester) async {
        await _pump(
          tester,
          const ProgressRail(
            position: Duration.zero,
            duration: Duration(minutes: 20),
            chapters: <ProgressChapter>[
              ProgressChapter(
                start: Duration.zero,
                end: Duration(minutes: 5),
                name: 'Cold Open',
              ),
            ],
          ),
        );
        final trackFinder = find.byKey(
          const ValueKey<String>('progress-rail-track'),
        );
        final topLeft = tester.getTopLeft(trackFinder);
        final size = tester.getSize(trackFinder);
        // Drag to a point inside the chapter (near the left edge).
        final gesture = await tester.startGesture(
          Offset(topLeft.dx + size.width * 0.02, topLeft.dy + size.height / 2),
        );
        await gesture.moveBy(const Offset(1, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey<String>('rail-scrub-eyebrow')),
          findsOneWidget,
        );
        expect(find.textContaining('CHAPTER 1'), findsOneWidget);
        expect(find.textContaining('COLD OPEN'), findsOneWidget);

        // Drag well past the chapter's end.
        await gesture.moveBy(Offset(size.width * 0.8, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey<String>('rail-scrub-eyebrow')),
          findsNothing,
        );
        await gesture.up();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a chapter with no name never shows an eyebrow', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration.zero,
          duration: Duration(minutes: 20),
          chapters: <ProgressChapter>[
            ProgressChapter(start: Duration.zero, end: Duration(minutes: 5)),
          ],
        ),
      );
      final trackFinder = find.byKey(
        const ValueKey<String>('progress-rail-track'),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(trackFinder) - const Offset(500, 0),
      );
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey<String>('rail-scrub-eyebrow')),
        findsNothing,
      );
      await gesture.up();
      expect(tester.takeException(), isNull);
    });
  });

  group('thumbnail clamping/retention', () {
    testWidgets(
      'the thumbnail card stays fully inside the rail at the left edge',
      (tester) async {
        final image = await _decodeFixtureThumbnail(tester);
        await _pump(
          tester,
          ProgressRail(
            position: Duration.zero,
            duration: const Duration(minutes: 20),
            thumbnail: image,
          ),
          size: const Size(1920, 260),
        );
        final trackFinder = find.byKey(
          const ValueKey<String>('progress-rail-track'),
        );
        final topLeft = tester.getTopLeft(trackFinder);
        final gesture = await tester.startGesture(
          Offset(topLeft.dx + 1, topLeft.dy + 5),
        );
        await gesture.moveBy(const Offset(1, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        final cardFinder = find.byKey(
          const ValueKey<String>('rail-thumbnail-card'),
        );
        expect(cardFinder, findsOneWidget);
        final cardLeft = tester.getTopLeft(cardFinder).dx;
        final railLeft = tester.getTopLeft(trackFinder).dx;
        expect(
          cardLeft,
          greaterThanOrEqualTo(railLeft - 0.5),
          reason:
              'the preview card must never spill past the rail\'s left edge',
        );
        await gesture.up();
      },
    );

    testWidgets(
      'the thumbnail card stays fully inside the rail at the right edge',
      (tester) async {
        final image = await _decodeFixtureThumbnail(tester);
        await _pump(
          tester,
          ProgressRail(
            position: Duration.zero,
            duration: const Duration(minutes: 20),
            thumbnail: image,
          ),
          size: const Size(1920, 260),
        );
        final trackFinder = find.byKey(
          const ValueKey<String>('progress-rail-track'),
        );
        final topRight = tester.getTopRight(trackFinder);
        final gesture = await tester.startGesture(
          Offset(topRight.dx - 1, topRight.dy + 5),
        );
        await gesture.moveBy(const Offset(-1, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        final cardFinder = find.byKey(
          const ValueKey<String>('rail-thumbnail-card'),
        );
        final cardRight = tester.getTopRight(cardFinder).dx;
        final railRight = tester.getTopRight(trackFinder).dx;
        expect(
          cardRight,
          lessThanOrEqualTo(railRight + 0.5),
          reason:
              'the preview card must never spill past the rail\'s right edge',
        );
        await gesture.up();
      },
    );

    testWidgets(
      'the last thumbnail is retained (dim placeholder before the first one arrives)',
      (tester) async {
        await _pump(
          tester,
          const ProgressRail(
            position: Duration.zero,
            duration: Duration(minutes: 20),
            thumbnail: null,
          ),
          size: const Size(1920, 260),
        );
        final trackFinder = find.byKey(
          const ValueKey<String>('progress-rail-track'),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(trackFinder),
        );
        await gesture.moveBy(const Offset(1, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('rail-thumbnail-card')),
          findsOneWidget,
        );
        expect(
          find.byType(Image),
          findsNothing,
          reason: 'no frame yet: plain dim placeholder, no Image',
        );
        await gesture.up();
      },
    );
  });

  group('wheel indicator', () {
    testWidgets('shows only while isWheelScrubbing during an active scrub', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration(minutes: 5),
          duration: Duration(minutes: 20),
          isWheelScrubbing: true,
        ),
        size: const Size(1920, 260),
      );
      final trackFinder = find.byKey(
        const ValueKey<String>('progress-rail-track'),
      );
      final gesture = await tester.startGesture(tester.getCenter(trackFinder));
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('wheel-indicator')),
        findsOneWidget,
      );
      await gesture.up();
    });

    testWidgets(
      'is absent when not scrubbing, even with isWheelScrubbing true',
      (tester) async {
        await _pump(
          tester,
          const ProgressRail(
            position: Duration(minutes: 5),
            duration: Duration(minutes: 20),
            isWheelScrubbing: true,
          ),
        );
        expect(
          find.byKey(const ValueKey<String>('wheel-indicator')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('reduced motion', () {
    testWidgets(
      'scrub overlay appears immediately with no fade when animations are disabled',
      (tester) async {
        await setLogicalSize(tester, const Size(1920, 260));
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              localizationsDelegates: const [AppStrings.delegate],
              theme: AppTheme.dark(tv: false),
              home: const Scaffold(
                backgroundColor: Colors.black,
                body: Padding(
                  padding: EdgeInsets.fromLTRB(60, 40, 60, 20),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ProgressRail(
                      position: Duration(minutes: 2),
                      duration: Duration(minutes: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final trackFinder = find.byKey(
          const ValueKey<String>('progress-rail-track'),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(trackFinder),
        );
        await gesture.moveBy(const Offset(1, 0));
        // A single pump (no settle/duration) must already show the overlay at
        // full opacity — proves the fade duration collapsed to zero rather
        // than merely being mid-animation.
        await tester.pump();
        final opacity = tester.widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('scrub-overlay-fade')),
        );
        expect(opacity.opacity, 1.0);
        final renderOpacity = tester
            .renderObject<RenderAnimatedOpacity>(
              find.byKey(const ValueKey<String>('scrub-overlay-fade')),
            )
            .opacity
            .value;
        expect(renderOpacity, 1.0);
        expect(tester.takeException(), isNull);
        await gesture.up();
      },
    );
  });

  group('goldens', () {
    testWidgets('rest state at 1920x1080', (tester) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration(minutes: 36, seconds: 18),
          duration: Duration(hours: 1, minutes: 36),
          bufferedAhead: Duration(minutes: 4),
          markers: <ProgressMarker>[
            ProgressMarker(
              kind: ProgressMarkerKind.intro,
              start: Duration.zero,
              end: Duration(seconds: 45),
            ),
            ProgressMarker(
              kind: ProgressMarkerKind.credits,
              start: Duration(hours: 1, minutes: 33),
              end: Duration(hours: 1, minutes: 36),
            ),
          ],
          now: _fixedNow,
        ),
        size: const Size(1920, 1080),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/progress_rail_rest_1920.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paused-at-rest dims the fill and shrinks the handle', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration(minutes: 36, seconds: 18),
          duration: Duration(hours: 1, minutes: 36),
          isPaused: true,
          now: _fixedNow,
        ),
        size: const Size(1920, 1080),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/progress_rail_paused_1920.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrubbing with a chapter eyebrow and a filmstrip thumbnail', (
      tester,
    ) async {
      final image = await _decodeFixtureThumbnail(tester);
      await _pump(
        tester,
        ProgressRail(
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 40),
          thumbnail: image,
          chapters: const <ProgressChapter>[
            ProgressChapter(
              start: Duration(minutes: 8),
              end: Duration(minutes: 16),
              name: 'The Escape',
            ),
          ],
        ),
        size: const Size(1920, 1080),
      );
      final trackFinder = find.byKey(
        const ValueKey<String>('progress-rail-track'),
      );
      final gesture = await tester.startGesture(tester.getCenter(trackFinder));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/progress_rail_scrubbing_1920.png'),
      );
      expect(tester.takeException(), isNull);
      await gesture.up();
    });

    testWidgets('skeleton state at 1920x1080', (tester) async {
      await _pump(
        tester,
        const ProgressRail(
          position: Duration.zero,
          duration: Duration.zero,
          isSkeleton: true,
        ),
        size: const Size(1920, 1080),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/progress_rail_skeleton_1920.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'scrubbing near the left edge clamps thumbnail/readout on-screen',
      (tester) async {
        final image = await _decodeFixtureThumbnail(tester);
        await _pump(
          tester,
          ProgressRail(
            position: Duration.zero,
            duration: const Duration(minutes: 20),
            thumbnail: image,
          ),
          size: const Size(1920, 1080),
        );
        final trackFinder = find.byKey(
          const ValueKey<String>('progress-rail-track'),
        );
        final topLeft = tester.getTopLeft(trackFinder);
        final gesture = await tester.startGesture(
          Offset(topLeft.dx + 2, topLeft.dy + 5),
        );
        await gesture.moveBy(const Offset(1, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/progress_rail_scrub_left_clamp_1920.png'),
        );
        expect(tester.takeException(), isNull);
        await gesture.up();
      },
    );
  });
}
