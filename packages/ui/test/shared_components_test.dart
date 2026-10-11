import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

/// An [ImageProvider] whose completion the test controls directly, so
/// out-of-order arrival can be simulated deterministically (no real
/// network/timers). Two instances are never equal (each carries a distinct
/// [id]), so [ImageProvider.resolve] never coalesces two "different"
/// requests behind Flutter's image cache.
class _ControlledImageProvider extends ImageProvider<_ControlledImageProvider> {
  _ControlledImageProvider(this.id);

  final String id;
  final Completer<ImageInfo> _completer = Completer<ImageInfo>();

  void completeWithImage(ui.Image image) {
    if (!_completer.isCompleted) {
      _completer.complete(ImageInfo(image: image));
    }
  }

  void completeWithError() {
    if (!_completer.isCompleted) {
      _completer.completeError(StateError('load failed'));
    }
  }

  @override
  Future<_ControlledImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_ControlledImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_completer.future);

  // Deliberately no == / hashCode override: identity equality means every
  // instance is its own cache key, so two tests reusing the same `id`
  // string never alias each other's image through Flutter's global
  // `PaintingBinding.imageCache`.
}

/// A tiny solid-color [ui.Image], built with the real engine — must run
/// inside `tester.runAsync` per `theme_test.dart`'s documented reason
/// (`Picture.toImage` never completes inside testWidgets' fake-async zone).
Future<ui.Image> _solidImage(Color color) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  return recorder.endRecording().toImage(4, 4);
}

/// Decodes a real fixture photo (cropped from a Rivulet App Store
/// screenshot, `test/fixtures/`) into a [ui.Image] via the real engine
/// codec — must run inside `tester.runAsync` for the same reason
/// [_solidImage] does. Used only for the gallery golden, so the golden
/// shows actual artwork instead of a flat colour block.
Future<ui.Image> _decodeFixture(String fileName) async {
  final bytes = await File('${Directory.current.path}/test/fixtures/$fileName')
      .readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Flutter's `ImageCache`/`ImageInfo` machinery clones the decoded [ui.Image]
/// per listener for ref-counting, so two callers holding "the same" image
/// are never `identical` or `==`. Read the actual pixel back (a real engine
/// call — run inside `tester.runAsync`) to compare by content instead.
Future<Color> _firstPixel(ui.Image? image) async {
  final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
  final data = bytes!.buffer.asUint8List();
  return Color.fromARGB(data[3], data[0], data[1], data[2]);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  setUp(() => PaintingBinding.instance.imageCache.clear());

  group('ArtworkView', () {
    testWidgets(
      'shows a placeholder panel before the first decode, never transparent',
      (tester) async {
        final provider = _ControlledImageProvider('a');
        await _pump(
          tester,
          ArtworkView(
            requestId: 'a',
            provider: provider,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        final withinArtwork = find.descendant(
          of: find.byType(ArtworkView),
          matching: find.byType(ColoredBox),
        );
        expect(find.byType(RawImage), findsNothing);
        expect(withinArtwork, findsOneWidget);
        expect(find.byIcon(PhosphorIconsRegular.filmSlate), findsNothing);
      },
    );

    testWidgets(
      'a null provider is an immediate failure showing the media-kind icon',
      (tester) async {
        await _pump(
          tester,
          const ArtworkView(
            requestId: 'none',
            provider: null,
            aspect: 2 / 3,
            fallbackKind: MediaKind.episode,
          ),
        );
        expect(find.byIcon(PhosphorIconsRegular.television), findsOneWidget);
      },
    );

    testWidgets('a genuine load failure shows the movie-kind fallback icon', (
      tester,
    ) async {
      final provider = _ControlledImageProvider('fail');
      await _pump(
        tester,
        ArtworkView(
          requestId: 'fail',
          provider: provider,
          aspect: 2 / 3,
          fallbackKind: MediaKind.movie,
        ),
      );
      provider.completeWithError();
      await tester.pump();
      expect(find.byIcon(PhosphorIconsRegular.filmSlate), findsOneWidget);
    });

    testWidgets(
      'keeps the previous decoded frame visible while the next request loads',
      (tester) async {
        // Only the real engine call (Picture.toImage) needs runAsync — see
        // theme_test.dart's documented reason. Widget pumping stays outside
        // it, on the ordinary fake-async test zone.
        final imageA = await tester.runAsync(
          () => _solidImage(const Color(0xFFFF0000)),
        );
        final providerA = _ControlledImageProvider('a');
        await _pump(
          tester,
          ArtworkView(
            requestId: 'a',
            provider: providerA,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        providerA.completeWithImage(imageA!);
        await tester.pump();
        expect(find.byType(RawImage), findsOneWidget);
        var shown = tester.widget<RawImage>(find.byType(RawImage));
        expect(
          await tester.runAsync(() => _firstPixel(shown.image)),
          const Color(0xFFFF0000),
        );

        // Swap to a new, still-loading request: the old frame must remain
        // (no flash to placeholder/transparent).
        final providerB = _ControlledImageProvider('b');
        await _pump(
          tester,
          ArtworkView(
            requestId: 'b',
            provider: providerB,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        await tester.pump();
        shown = tester.widget<RawImage>(find.byType(RawImage));
        expect(
          await tester.runAsync(() => _firstPixel(shown.image)),
          const Color(0xFFFF0000),
          reason: 'old frame must ride until the new one decodes',
        );
      },
    );

    testWidgets(
      'out-of-order completions: the newest request wins regardless of arrival order',
      (tester) async {
        final imageA = await tester.runAsync(
          () => _solidImage(const Color(0xFFFF0000)),
        );
        final imageB = await tester.runAsync(
          () => _solidImage(const Color(0xFF00FF00)),
        );
        final providerA = _ControlledImageProvider('a');
        final providerB = _ControlledImageProvider('b');

        await _pump(
          tester,
          ArtworkView(
            requestId: 'a',
            provider: providerA,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        // Move on to request B before A resolves.
        await _pump(
          tester,
          ArtworkView(
            requestId: 'b',
            provider: providerB,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        // B (the current request) resolves first...
        providerB.completeWithImage(imageB!);
        await tester.pump();
        // ...then A (the stale, superseded request) arrives late.
        providerA.completeWithImage(imageA!);
        await tester.pump();

        final shown = tester.widget<RawImage>(find.byType(RawImage));
        expect(
          await tester.runAsync(() => _firstPixel(shown.image)),
          const Color(0xFF00FF00),
          reason: 'stale completion for A must be ignored',
        );
      },
    );

    testWidgets(
      'a stale error never replaces an already-displayed newer success',
      (tester) async {
        final imageB = await tester.runAsync(
          () => _solidImage(const Color(0xFF00FF00)),
        );
        final providerA = _ControlledImageProvider('a');
        final providerB = _ControlledImageProvider('b');

        await _pump(
          tester,
          ArtworkView(
            requestId: 'a',
            provider: providerA,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        await _pump(
          tester,
          ArtworkView(
            requestId: 'b',
            provider: providerB,
            aspect: 2 / 3,
            fallbackKind: MediaKind.movie,
          ),
        );
        providerB.completeWithImage(imageB!);
        await tester.pump();
        // ArtworkView already detached A's listener when it moved on to B
        // (the phase's own pitfall: "cancel listeners from the previous
        // ImageStream"), so this late error arrives on an orphaned stream —
        // Flutter reports that to the zone's error handler regardless of
        // whether anything is still listening. Swallow it for this
        // deliberately-provoked case only; it never reaches ArtworkView.
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (_) {};
        try {
          providerA.completeWithError();
          await tester.pump();
        } finally {
          FlutterError.onError = previousOnError;
        }

        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byIcon(PhosphorIconsRegular.filmSlate), findsNothing);
        final shown = tester.widget<RawImage>(find.byType(RawImage));
        expect(
          await tester.runAsync(() => _firstPixel(shown.image)),
          const Color(0xFF00FF00),
        );
      },
    );

    testWidgets('a picture that arrives late fades in over 180 ms', (
      tester,
    ) async {
      final image = await tester.runAsync(
        () => _solidImage(const Color(0xFFFF0000)),
      );
      final provider = _ControlledImageProvider('a');
      await _pump(
        tester,
        ArtworkView(
          requestId: 'a',
          provider: provider,
          aspect: 2 / 3,
          fallbackKind: MediaKind.movie,
        ),
      );
      provider.completeWithImage(image!);
      await tester.pump();
      final fade = find.descendant(
        of: find.byType(ArtworkView),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 90));
      final half = tester.widget<FadeTransition>(fade).opacity.value;
      expect(half, greaterThan(0));
      expect(half, lessThan(1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    });

    testWidgets('MediaQuery.disableAnimations shows a late picture at once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final image = await tester.runAsync(
        () => _solidImage(const Color(0xFFFF0000)),
      );
      final provider = _ControlledImageProvider('a');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ArtworkView(
                requestId: 'a',
                provider: provider,
                aspect: 2 / 3,
                fallbackKind: MediaKind.movie,
              ),
            ),
          ),
        ),
      );
      provider.completeWithImage(image!);
      await tester.pump();
      await tester.pump();
      final fade = find.descendant(
        of: find.byType(ArtworkView),
        matching: find.byType(FadeTransition),
      );
      expect(fade, findsNothing);
      expect(
        find.descendant(
          of: find.byType(ArtworkView),
          matching: find.byType(RawImage),
        ),
        findsOneWidget,
      );
    });
  });

  group('ProgressOverlay', () {
    testWidgets(
      'renders nothing with no progress, no watched flag, no unwatched count',
      (tester) async {
        await _pump(tester, const ProgressOverlay());
        expect(find.byType(Icon), findsNothing);
        expect(find.byType(Text), findsNothing);
      },
    );

    testWidgets('renders the progress capsule only for 0 < progress < 1', (
      tester,
    ) async {
      await _pump(tester, const ProgressOverlay(progress: 0.42));
      expect(find.byIcon(PhosphorIconsRegular.play), findsOneWidget);
      expect(find.bySemanticsLabel('Progress 42 percent'), findsOneWidget);
    });

    for (final malformed in <double>[0.0, 1.0, -0.5, 1.5, double.nan]) {
      testWidgets('clamps/rejects malformed progress $malformed to nothing', (
        tester,
      ) async {
        await _pump(tester, ProgressOverlay(progress: malformed));
        expect(find.byIcon(PhosphorIconsRegular.play), findsNothing);
      });
    }

    testWidgets('shows the watched glyph when watched is true', (tester) async {
      await _pump(tester, const ProgressOverlay(watched: true, progress: 0.5));
      expect(find.bySemanticsLabel('Watched'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.play), findsNothing);
    });

    testWidgets('an unwatched count takes priority over watched and progress', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressOverlay(watched: true, progress: 0.5, unwatchedCount: 3),
      );
      expect(find.bySemanticsLabel('3 unwatched episodes'), findsOneWidget);
      expect(find.bySemanticsLabel('Watched'), findsNothing);
      expect(find.byIcon(PhosphorIconsRegular.play), findsNothing);
    });

    testWidgets('a zero or negative unwatched count is treated as absent', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgressOverlay(watched: true, unwatchedCount: 0),
      );
      expect(find.bySemanticsLabel('Watched'), findsOneWidget);
    });
  });

  group('GlassSurface', () {
    testWidgets('blurs by default', (tester) async {
      await _pump(
        tester,
        const GlassSurface(child: SizedBox(width: 40, height: 40)),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets(
      'skips blur under MediaQuery.highContrast but keeps the border',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: MediaQuery(
              data: const MediaQueryData(highContrast: true),
              child: const Scaffold(
                body: GlassSurface(child: SizedBox(width: 40, height: 40)),
              ),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);
        final decorated = tester.widget<DecoratedBox>(
          find.byType(DecoratedBox).first,
        );
        final decoration = decorated.decoration as BoxDecoration;
        expect(decoration.border, isNotNull);
      },
    );

    testWidgets('draws no BackdropFilter on TV', (tester) async {
      await _pump(
        tester,
        const AdaptiveBehavior(
          capabilities: PlatformCapabilities.directionalPad(),
          child: GlassSurface(child: SizedBox(width: 40, height: 40)),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('FocusButton', () {
    testWidgets('forwards Select/Enter and tap activation identically', (
      tester,
    ) async {
      var activations = 0;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await _pump(
        tester,
        FocusButton(
          variant: FocusButtonVariant.pill,
          focusNode: focusNode,
          label: 'Play',
          icon: Icons.play_arrow,
          onActivate: () => activations++,
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activations, 1);

      await tester.tap(find.byType(FocusButton));
      await tester.pump();
      expect(activations, 2);
    });

    testWidgets(
      'layout size is fixed across normal, focused, and disabled states',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await _pump(
          tester,
          FocusButton(
            variant: FocusButtonVariant.circle,
            focusNode: focusNode,
            icon: Icons.pause,
            semanticLabel: 'Pause',
            onActivate: () {},
          ),
        );
        final normalSize = tester.getSize(find.byType(FocusButton));

        focusNode.requestFocus();
        await tester.pump();
        expect(tester.getSize(find.byType(FocusButton)), normalSize);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          tester.getSize(find.byType(FocusButton)),
          normalSize,
          reason: 'pressed state',
        );

        await _pump(
          tester,
          FocusButton(
            variant: FocusButtonVariant.circle,
            focusNode: focusNode,
            icon: Icons.pause,
            semanticLabel: 'Pause',
            enabled: false,
          ),
        );
        expect(
          tester.getSize(find.byType(FocusButton)),
          normalSize,
          reason: 'disabled state',
        );
      },
    );

    testWidgets(
      'a disabled button exposes disabled semantics and never activates',
      (tester) async {
        var activations = 0;
        await _pump(
          tester,
          FocusButton(
            variant: FocusButtonVariant.row,
            icon: Icons.settings,
            label: 'Settings',
            enabled: false,
            onActivate: () => activations++,
          ),
        );
        await tester.tap(find.byType(FocusButton));
        await tester.pump();
        expect(activations, 0);
        final semantics = tester.getSemantics(find.byType(FocusButton));
        expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
      },
    );

    testWidgets(
      'exposes button semantics with the given label for every variant',
      (tester) async {
        for (final variant in FocusButtonVariant.values) {
          await _pump(
            tester,
            FocusButton(
              variant: variant,
              icon: Icons.star,
              semanticLabel: 'Favorite',
              onActivate: () {},
            ),
          );
          final semantics = tester.getSemantics(find.byType(FocusButton));
          expect(semantics.flagsCollection.isButton, isTrue);
          expect(semantics.label, 'Favorite');
        }
      },
    );
  });

  group('component gallery goldens', () {
    // Deterministic "artwork": real fixture photos decoded once up front
    // (`test/fixtures/poster_sintel.jpg`, `backdrop_hero.jpg` — both cropped
    // from `research/Rivulet/Screenshots/AppStore/`, never a live network
    // image) so this golden shows what real poster/backdrop art looks like
    // — see the phase's step 6 and the visual-quality task's fixture
    // requirement.
    Widget buildGallery(ui.Image posterImage, ui.Image backdropImage) =>
        RepaintBoundary(
          key: const ValueKey<String>('component-gallery'),
          child: ColoredBox(
            color: const Color(0xFF121212),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 120,
                    child: ArtworkView(
                      requestId: 'gallery-poster',
                      provider: (_ControlledImageProvider('gallery-poster')
                        ..completeWithImage(posterImage)),
                      aspect: 2 / 3,
                      fallbackKind: MediaKind.movie,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: ArtworkView(
                      requestId: 'gallery-backdrop',
                      provider: (_ControlledImageProvider('gallery-backdrop')
                        ..completeWithImage(backdropImage)),
                      aspect: 16 / 9,
                      fallbackKind: MediaKind.movie,
                    ),
                  ),
                  const SizedBox(
                    width: 120,
                    height: 180,
                    child: Stack(
                      children: [
                        ColoredBox(color: Color(0xFF303030)),
                        ProgressOverlay(progress: 0.6),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 120,
                    height: 180,
                    child: Stack(
                      children: [
                        ColoredBox(color: Color(0xFF303030)),
                        ProgressOverlay(watched: true),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 120,
                    height: 180,
                    child: Stack(
                      children: [
                        ColoredBox(color: Color(0xFF303030)),
                        ProgressOverlay(unwatchedCount: 4),
                      ],
                    ),
                  ),
                  const GlassSurface(
                    child: SizedBox(
                      width: 120,
                      height: 60,
                      child: Center(child: Text('Glass')),
                    ),
                  ),
                  FocusButton(
                    variant: FocusButtonVariant.pill,
                    icon: Icons.play_arrow,
                    label: 'Play',
                    autofocus: true,
                    onActivate: () {},
                  ),
                  FocusButton(
                    variant: FocusButtonVariant.circle,
                    icon: Icons.pause,
                    onActivate: () {},
                  ),
                  FocusButton(
                    variant: FocusButtonVariant.icon,
                    icon: Icons.info_outline,
                    onActivate: () {},
                  ),
                  FocusButton(
                    variant: FocusButtonVariant.row,
                    icon: Icons.settings,
                    label: 'Settings row',
                    onActivate: () {},
                  ),
                ],
              ),
            ),
          ),
        );

    for (final size in const <Size>[Size(400, 800), Size(1920, 1080)]) {
      testWidgets(
        'shared component gallery golden and non-flat pixels at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final posterImage = await tester.runAsync(
            () => _decodeFixture('poster_sintel.jpg'),
          );
          final backdropImage = await tester.runAsync(
            () => _decodeFixture('backdrop_hero.jpg'),
          );
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: const [AppStrings.delegate],
              theme: AppTheme.dark(tv: false),
              home: Scaffold(body: buildGallery(posterImage!, backdropImage!)),
            ),
          );
          // Two pumps: the first flushes the poster image's completion
          // microtask and lets AnimatedSwitcher build the crossfade-in
          // entry (starting its controller at t=0 for this frame); only a
          // second pump actually advances the clock so that controller
          // ticks to completion.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          final gallery = find.byKey(
            const ValueKey<String>('component-gallery'),
          );
          await expectLater(
            gallery,
            matchesGoldenFile(
              'goldens/shared_components_${size.width.toInt()}.png',
            ),
          );

          final boundary = tester.renderObject<RenderRepaintBoundary>(gallery);
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
