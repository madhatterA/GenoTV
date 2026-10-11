import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

void main() {
  testWidgets('acceptance callbacks fire once through skip, retry, and next', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    final controller = FakePlaybackController()
      ..setDuration(const Duration(minutes: 2))
      ..advanceTo(const Duration(seconds: 5));
    var surfaces = 0;
    var replay = 0;
    var upNext = 0;
    var retries = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PlayerScreen(
          controller: controller,
          videoSurface: _Surface(() => surfaces++),
          formFactor: FormFactor.tv,
          markers: const <UiMarker>[
            UiMarker(
              id: 'intro',
              kind: UiMarkerKind.intro,
              start: Duration.zero,
              end: Duration(seconds: 10),
            ),
          ],
          onReplayLongPress: () => replay++,
          onUpNext: () => upNext++,
          onRetry: () => retries++,
          nextTitle: 'Next episode',
          onPlayNext: () => next++,
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await controller.play();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-box-subtitles')));
    await tester.pump();
    expect(find.byType(TrackPanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-player-overlay')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('player-box-subtitles')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rail-action-upNext')));
    await tester.pump();
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();
    expect(controller.recordedSeeks, <Duration>[const Duration(seconds: 10)]);
    controller.failWith(
      PlaybackFailure.openFailed(cause: StateError('fixture')),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(PlayerErrorOverlay), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('player-error-retry')));
    await tester.pump();
    controller.advanceTo(const Duration(minutes: 2));
    await tester.pump();
    await tester.tap(find.text('Play Next'));
    await tester.pump();
    expect((replay, upNext, retries, next), (1, 1, 1, 1));
    expect(surfaces, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
  });

  testWidgets('one surface survives completion and post-video dismissal', (
    tester,
  ) async {
    final controller = FakePlaybackController()
      ..setDuration(const Duration(minutes: 2));
    var surfaces = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PlayerScreen(
          controller: controller,
          videoSurface: _Surface(() => surfaces++),
          nextTitle: 'Next episode',
          onPlayNext: () => next++,
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    expect(surfaces, 1);
    controller.advanceTo(const Duration(minutes: 2));
    await tester.pump();
    expect(find.byType(PostVideoOverlay), findsOneWidget);
    expect(surfaces, 1);
    await tester.tap(find.text('Play Next'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(next, 1);
    expect(surfaces, 1);
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
  });

  testWidgets(
    'player uses one rail and routes double tap and keyboard shuttle',
    (tester) async {
      final controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 2))
        ..advanceTo(const Duration(seconds: 20));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: _Surface(() {}),
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      expect(find.byType(ProgressRail), findsOneWidget);
      await tester.tapAt(const Offset(20, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<PlayerGestureSurface>(find.byType(PlayerGestureSurface))
            .chromeVisible,
        isFalse,
      );
      await tester.tapAt(const Offset(20, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<PlayerGestureSurface>(find.byType(PlayerGestureSurface))
            .chromeVisible,
        isTrue,
      );
      await tester.tapAt(const Offset(20, 200));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(20, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.recordedSeeks, <Duration>[Duration.zero]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('▶ 2x'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.recordedSeeks, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );

  for (final size in <Size>[const Size(1920, 1080), const Size(844, 390)]) {
    testWidgets('post-video golden at ${size.width}', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, size);
      final controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 2));
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: PlayerScreen(
              controller: controller,
              videoSurface: _ArtworkSurface(),
              nextTitle: 'The next episode',
              nextArtwork: resolver('https://example.invalid/next?ar=land'),
              onPlayNext: () {},
              setSystemUiMode: (_) async {},
            ),
          ),
        ),
      );
      controller.advanceTo(const Duration(minutes: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(PlayerScreen),
        matchesGoldenFile(
          'goldens/player_post_video_${size.width.toInt()}.png',
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });
  }
}

class _Surface extends FakeVideoSurface {
  _Surface(this.onBuild);
  final VoidCallback onBuild;

  @override
  Widget build(
    BuildContext context,
    controller, {
    BoxFit fit = BoxFit.contain,
    Color background = Colors.black,
  }) {
    onBuild();
    return const ColoredBox(color: Colors.black);
  }
}

class _ArtworkSurface extends FakeVideoSurface {
  @override
  Widget build(
    BuildContext context,
    controller, {
    BoxFit fit = BoxFit.cover,
    Color background = Colors.black,
  }) {
    return Image(
      image: ArtworkResolverScope.of(context)(
        'https://example.invalid/player/backdrop.jpg?ar=land',
      ),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
