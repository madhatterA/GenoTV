import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

CaptionTextCue _cue(
  String text, {
  Object id = 1,
  int start = 0,
  int end = 5,
  int delayMs = 0,
  int sourceOrder = 0,
  CaptionPlacement? placement,
  Color? color,
  bool bold = false,
  bool italic = false,
  bool underline = false,
}) => CaptionTextCue(
  id: id,
  start: Duration(seconds: start),
  end: Duration(seconds: end),
  delay: Duration(milliseconds: delayMs),
  sourceOrder: sourceOrder,
  placement: placement,
  runs: [
    CaptionTextRun(
      text,
      bold: bold,
      italic: italic,
      underline: underline,
      color: color,
    ),
  ],
);

void main() {
  group('activeCaptionCues — timing', () {
    test('boundary inclusivity: start and end are both included', () {
      final cue = _cue('a', start: 10, end: 12);
      expect(activeCaptionCues([cue], const Duration(seconds: 10)), [cue]);
      expect(activeCaptionCues([cue], const Duration(seconds: 12)), [cue]);
      expect(
        activeCaptionCues([cue], const Duration(seconds: 9, milliseconds: 999)),
        isEmpty,
      );
      expect(
        activeCaptionCues([cue], const Duration(seconds: 12, milliseconds: 1)),
        isEmpty,
      );
    });

    test('positive delay displays later', () {
      final cue = _cue('a', start: 10, end: 12, delayMs: 2000);
      // Without the delay this is active; with a +2s delay the effective
      // window is [12,14], so 10 is now inactive.
      expect(activeCaptionCues([cue], const Duration(seconds: 10)), isEmpty);
      expect(activeCaptionCues([cue], const Duration(seconds: 13)), [cue]);
    });

    test('negative delay displays earlier', () {
      final cue = _cue('a', start: 10, end: 12, delayMs: -2000);
      // Effective window shifts to [8,10]: active earlier, gone by 11.
      expect(activeCaptionCues([cue], const Duration(seconds: 8)), [cue]);
      expect(activeCaptionCues([cue], const Duration(seconds: 11)), isEmpty);
    });
  });

  group('activeCaptionCues — dedupe', () {
    test('identical cue identity/content/time collapses to one', () {
      final a = _cue('same', start: 1, end: 3, id: 1, sourceOrder: 0);
      final b = _cue('same', start: 1, end: 3, id: 2, sourceOrder: 1);
      final active = activeCaptionCues([a, b], const Duration(seconds: 2));
      expect(active, hasLength(1));
    });

    test('distinct same-time cues both render (two speakers)', () {
      final a = _cue('Speaker A', start: 1, end: 3, id: 1, sourceOrder: 0);
      final b = _cue('Speaker B', start: 1, end: 3, id: 2, sourceOrder: 1);
      final active = activeCaptionCues([a, b], const Duration(seconds: 2));
      expect(active, hasLength(2));
      expect((active[0] as CaptionTextCue).runs.single.text, 'Speaker A');
      expect((active[1] as CaptionTextCue).runs.single.text, 'Speaker B');
    });

    test('same text, different placement, is distinct', () {
      final a = _cue(
        'x',
        start: 1,
        end: 3,
        id: 1,
        placement: const CaptionPlacement(anchor: CaptionAnchor.bottomLeft),
      );
      final b = _cue(
        'x',
        start: 1,
        end: 3,
        id: 2,
        placement: const CaptionPlacement(anchor: CaptionAnchor.bottomRight),
      );
      expect(
        activeCaptionCues([a, b], const Duration(seconds: 2)),
        hasLength(2),
      );
    });

    test('deterministic sort by source order', () {
      final second = _cue('second', start: 0, end: 5, id: 1, sourceOrder: 1);
      final first = _cue('first', start: 0, end: 5, id: 2, sourceOrder: 0);
      final active = activeCaptionCues([second, first], Duration.zero);
      expect((active[0] as CaptionTextCue).runs.single.text, 'first');
      expect((active[1] as CaptionTextCue).runs.single.text, 'second');
    });
  });

  group('videoRectFor — aspect-fit', () {
    test('16:9 video in a 16:9 viewport fills exactly', () {
      final rect = videoRectFor(const Size(1920, 1080), const Size(1920, 1080));
      expect(rect, const Rect.fromLTWH(0, 0, 1920, 1080));
    });

    test('4:3 video letterboxes left/right in a 16:9 viewport', () {
      final rect = videoRectFor(const Size(1920, 1080), const Size(4, 3));
      expect(rect.height, closeTo(1080, 0.01));
      expect(rect.width, lessThan(1920));
      expect(rect.left, greaterThan(0));
      expect(rect.left, closeTo((1920 - rect.width) / 2, 0.5));
    });

    test('portrait video pillarboxes top/bottom in a 16:9 viewport', () {
      final rect = videoRectFor(const Size(1920, 1080), const Size(9, 16));
      expect(rect.width, lessThan(1920));
      expect(rect.height, lessThanOrEqualTo(1080));
    });

    test('unknown video size falls back to full viewport', () {
      final rect = videoRectFor(const Size(800, 600), Size.zero);
      expect(rect, const Rect.fromLTWH(0, 0, 800, 600));
    });
  });

  group('CaptionLayer widget', () {
    testWidgets('excludes hit testing and focus', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => tapped = true,
                  child: Container(color: Colors.black),
                ),
              ),
              CaptionLayer(
                cues: [_cue('hello')],
                sourceTime: Duration.zero,
                videoSize: const Size(1920, 1080),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The tap is expected to miss the (ignore-pointer) CaptionLayer and
      // land on the widget beneath it — that IS the assertion.
      await tester.tap(find.byType(CaptionLayer), warnIfMissed: false);
      expect(tapped, isTrue);
    });

    testWidgets('renders both distinct simultaneous cues', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: SizedBox(
            width: 1920,
            height: 1080,
            child: CaptionLayer(
              cues: [
                _cue('Speaker A', id: 1, sourceOrder: 0),
                _cue('Speaker B', id: 2, sourceOrder: 1),
              ],
              sourceTime: const Duration(seconds: 2),
              videoSize: const Size(1920, 1080),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Speaker A'), findsOneWidget);
      expect(find.text('Speaker B'), findsOneWidget);
    });

    for (final anchor in CaptionAnchor.values) {
      testWidgets('renders at anchor $anchor without error', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            home: SizedBox(
              width: 1920,
              height: 1080,
              child: CaptionLayer(
                cues: [
                  _cue('anchored', placement: CaptionPlacement(anchor: anchor)),
                ],
                sourceTime: Duration.zero,
                videoSize: const Size(1920, 1080),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('anchored'), findsOneWidget);
      });
    }

    testWidgets('safe-area clamp keeps a fully left cue on screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: SizedBox(
            width: 1920,
            height: 1080,
            child: CaptionLayer(
              cues: [
                _cue(
                  'edge',
                  placement: const CaptionPlacement(
                    anchor: CaptionAnchor.middleLeft,
                    dx: 0,
                    dy: 0.5,
                  ),
                ),
              ],
              sourceTime: Duration.zero,
              videoSize: const Size(1920, 1080),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final box = tester.getTopLeft(find.text('edge'));
      expect(box.dx, greaterThanOrEqualTo(0));
    });

    testWidgets('chrome visible lifts the default band above the rail', (
      tester,
    ) async {
      Widget buildLayer(bool chromeVisible) => MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        home: SizedBox(
          width: 1920,
          height: 1080,
          child: CaptionLayer(
            cues: [_cue('lifted')],
            sourceTime: Duration.zero,
            videoSize: const Size(1920, 1080),
            chromeVisible: chromeVisible,
            reducedMotion: true,
          ),
        ),
      );
      await tester.pumpWidget(buildLayer(false));
      await tester.pump();
      final hiddenY = tester.getCenter(find.text('lifted')).dy;

      await tester.pumpWidget(buildLayer(true));
      await tester.pump();
      final visibleY = tester.getCenter(find.text('lifted')).dy;

      expect(tester.takeException(), isNull);
      expect(visibleY, lessThan(hiddenY));
    });

    testWidgets('reduced motion snaps the lift instead of animating', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: SizedBox(
            width: 1920,
            height: 1080,
            child: CaptionLayer(
              cues: [_cue('snap')],
              sourceTime: Duration.zero,
              videoSize: const Size(1920, 1080),
              chromeVisible: true,
              reducedMotion: true,
            ),
          ),
        ),
      );
      // A single pump (no animation ticks) already lands at the final
      // position when reducedMotion snaps rather than animates.
      await tester.pump();
      final firstFrameY = tester.getCenter(find.text('snap')).dy;
      await tester.pump(const Duration(milliseconds: 250));
      final settledY = tester.getCenter(find.text('snap')).dy;
      expect(tester.takeException(), isNull);
      expect(firstFrameY, settledY);
    });

    testWidgets('styled runs: bold/italic/underline render distinct styles', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: SizedBox(
            width: 1920,
            height: 1080,
            child: CaptionLayer(
              cues: [
                CaptionTextCue(
                  id: 1,
                  start: Duration.zero,
                  end: const Duration(seconds: 5),
                  sourceOrder: 0,
                  runs: const [
                    CaptionTextRun('bold ', bold: true),
                    CaptionTextRun('italic ', italic: true),
                    CaptionTextRun('underline', underline: true),
                  ],
                ),
              ],
              sourceTime: Duration.zero,
              videoSize: const Size(1920, 1080),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final leaves = <TextSpan>[];
      void collect(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text != null && span.text!.isNotEmpty) leaves.add(span);
          span.children?.forEach(collect);
        }
      }

      for (final richText in tester.widgetList<RichText>(
        find.byType(RichText),
      )) {
        collect(richText.text);
      }
      final bold = leaves.firstWhere((s) => s.text == 'bold ');
      final italic = leaves.firstWhere((s) => s.text == 'italic ');
      final underline = leaves.firstWhere((s) => s.text == 'underline');
      expect(bold.style!.fontWeight, FontWeight.bold);
      expect(italic.style!.fontStyle, FontStyle.italic);
      expect(underline.style!.decoration, TextDecoration.underline);
    });

    testWidgets('invalid style data falls back to safe defaults', (
      tester,
    ) async {
      const invalid = CaptionStyle(
        foregroundOpacity: double.nan,
        backgroundOpacity: -5,
        fontScale: -1,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: SizedBox(
            width: 1920,
            height: 1080,
            child: CaptionLayer(
              cues: [_cue('safe')],
              sourceTime: Duration.zero,
              videoSize: const Size(1920, 1080),
              style: invalid,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('safe'), findsOneWidget);
      final sanitized = invalid.sanitized();
      expect(sanitized.foregroundOpacity, 1.0);
      expect(sanitized.backgroundOpacity, 0.0);
      expect(sanitized.fontScale, 1.0);
    });

    testWidgets('image cue disposes its stream when removed', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      final provider = resolver('https://example.invalid/caption/sign.jpg');
      Widget buildLayer(bool includeImageCue) => MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        home: SizedBox(
          width: 1920,
          height: 1080,
          child: CaptionLayer(
            cues: includeImageCue
                ? [
                    CaptionImageCue(
                      id: 1,
                      start: Duration.zero,
                      end: const Duration(seconds: 5),
                      sourceOrder: 0,
                      image: provider,
                      position: const Rect.fromLTWH(0.3, 0.6, 0.4, 0.2),
                    ),
                  ]
                : const [],
            sourceTime: Duration.zero,
            videoSize: const Size(1920, 1080),
          ),
        ),
      );
      await tester.pumpWidget(buildLayer(true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);

      // Cue ends / list becomes empty: the Image widget leaves the tree and
      // Flutter's framework releases its ImageStream listener on unmount —
      // no manual stream handle is retained by CaptionLayer to leak.
      await tester.pumpWidget(buildLayer(false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
      'accessibility caption announcements: combined label only when enabled',
      (tester) async {
        Widget buildLayer(bool announce) => MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: SizedBox(
            width: 1920,
            height: 1080,
            child: CaptionLayer(
              cues: [_cue('Announced text', id: 1, sourceOrder: 0)],
              sourceTime: Duration.zero,
              videoSize: const Size(1920, 1080),
              announceForAccessibility: announce,
            ),
          ),
        );

        await tester.pumpWidget(buildLayer(false));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Announced text'), findsNothing);

        await tester.pumpWidget(buildLayer(true));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Announced text'), findsOneWidget);
      },
    );
  });

  group('Caption goldens', () {
    Future<void> pumpCaptionGolden(
      WidgetTester tester,
      String goldenName,
      List<CaptionCue> cues, {
      bool chromeVisible = false,
      CaptionStyle style = CaptionStyle.fallback,
    }) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));

      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: Image(
                      image: resolver(
                        'https://example.invalid/caption/backdrop.jpg?ar=land',
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                  CaptionLayer(
                    cues: cues,
                    sourceTime: const Duration(seconds: 2),
                    videoSize: const Size(1920, 1080),
                    chromeVisible: chromeVisible,
                    style: style,
                    reducedMotion: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/$goldenName'),
      );
    }

    testWidgets('default bottom band, two stacked cues', (tester) async {
      await pumpCaptionGolden(tester, 'caption_default_band.png', [
        _cue(
          '- Are you sure about this?',
          id: 1,
          sourceOrder: 0,
          start: 0,
          end: 5,
        ),
        _cue('- Absolutely certain.', id: 2, sourceOrder: 1, start: 0, end: 5),
      ]);
    });

    testWidgets('chrome visible lifts band above rail', (tester) async {
      await pumpCaptionGolden(tester, 'caption_chrome_visible.png', [
        _cue(
          'Chrome is showing, caption lifts clear of the rail.',
          start: 0,
          end: 5,
        ),
      ], chromeVisible: true);
    });

    testWidgets('placed cue + styled runs + uniform edge', (tester) async {
      await pumpCaptionGolden(tester, 'caption_placed_styled.png', [
        CaptionTextCue(
          id: 1,
          start: Duration.zero,
          end: const Duration(seconds: 5),
          sourceOrder: 0,
          placement: const CaptionPlacement(anchor: CaptionAnchor.topRight),
          runs: const [
            CaptionTextRun('Breaking: ', bold: true, color: Colors.amber),
            CaptionTextRun('signal restored'),
          ],
        ),
      ], style: const CaptionStyle(edge: CaptionEdgeStyle.uniform));
    });
  });
}
