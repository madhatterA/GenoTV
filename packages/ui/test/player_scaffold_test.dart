import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 01 (planning/part-04-ui/chapter-03-player-ui/phase-01-player-scaffold.md)
// proof file. `PlayerChromeController` (mode/timeout tests, run as
// `testWidgets` per this repo's fake-time convention — TRAPS: "Timers in
// tests: fake time via testWidgets + tester.pump, never real clocks") is
// the pure state machine ported from research/Rivulet/Rivulet/Views/Player/
// UniversalPlayerViewModel.swift + PlayerContainerViewController.swift; see
// player_chrome_controller.dart's doc comments for line citations.
// `PlayerScreen` (widget tests) proves the surface is built exactly once
// per session and that the chrome/loading/compatibility/error/exit layers
// sit correctly around it.

class _CountingSurface extends FakeVideoSurface {
  int builds = 0;

  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.contain,
    Color background = const Color(0xFF000000),
  }) {
    builds++;
    return ColoredBox(
      key: const ValueKey<String>('surface-paint'),
      color: background,
    );
  }
}

/// A [PlaybackController] fake with a direct [emit], for the one test that
/// needs an exact [PlaybackState] (`isBuffering: true`) [FakePlaybackController]
/// has no setter for.
class _FakeController implements PlaybackController {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _current = PlaybackState.initial();

  void emit(PlaybackState state) {
    _current = state;
    _states.add(state);
  }

  @override
  Stream<PlaybackState> get state => _states.stream;
  @override
  PlaybackState get currentState => _current;
  @override
  Stream<MediaInfo> get mediaInfo => const Stream<MediaInfo>.empty();

  @override
  Stream<PlaybackEvent> get events => const Stream<PlaybackEvent>.empty();
  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}

  final recordedSubtitleDelays = <Duration>[];
  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    recordedSubtitleDelays.add(delay);
  }

  final recordedAudioDelays = <Duration>[];
  @override
  Future<void> setAudioDelay(Duration delay) async {
    recordedAudioDelays.add(delay);
  }

  final recordedSubtitleScales = <double>[];
  @override
  Future<void> setSubtitleScale(double scale) async {
    recordedSubtitleScales.add(scale);
  }

  final recordedSubtitlePositions = <int>[];
  @override
  Future<void> setSubtitlePosition(int percent) async {
    recordedSubtitlePositions.add(percent);
  }

  final recordedAspectRatios = <String?>[];
  @override
  Future<void> setAspectRatio(String? ratio) async {
    recordedAspectRatios.add(ratio);
  }

  final recordedAudioOutput = <AudioPlan>[];
  @override
  Future<void> setAudioOutput(AudioPlan plan) async {
    recordedAudioOutput.add(plan);
  }

  final recordedFillScreen = <bool>[];
  @override
  Future<void> setEngineOptions(Map<String, String> options) async {}

  @override
  Future<Map<String, String>> applyUserOptions(
    Map<String, String> options,
  ) async => const {};

  @override
  Stream<Map<String, String>> get diagnostics => const Stream.empty();

  @override
  Future<void> setFillScreen(bool enabled) async {
    recordedFillScreen.add(enabled);
  }

  @override
  Future<void> selectTrack(TrackSelection selection) async {}
  @override
  Future<void> addExternalSubtitle(Uri uri, {String? title}) async {}
  @override
  Future<void> dispose() => _states.close();
}

/// Paints fixture backdrop art full-bleed as the "video" frame for the
/// golden — never an empty grey tile (brief: "never empty grey tiles").
class _FixtureVideoSurface extends FakeVideoSurface {
  const _FixtureVideoSurface();

  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.cover,
    Color background = const Color(0xFF000000),
  }) {
    final resolver = ArtworkResolverScope.of(context);
    return ColoredBox(
      color: background,
      child: Image(
        image: resolver('https://example.invalid/player/backdrop.jpg?ar=land'),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

void main() {
  group('PlayerChromeController', () {
    testWidgets('tap toggles rail chrome without exiting', (tester) async {
      var exits = 0;
      final chrome = PlayerChromeController(onExit: () => exits++);
      chrome.toggle();
      expect(chrome.mode, ChromeMode.hidden);
      chrome.toggle();
      expect(chrome.mode, ChromeMode.rail);
      expect(exits, 0);
      chrome.dispose();
    });

    testWidgets('starts in rail mode, visible', (tester) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      expect(chrome.mode, ChromeMode.rail);
      expect(chrome.visible, isTrue);
      chrome.dispose();
    });

    testWidgets('hides 5s after the last handled activity while playing', (
      tester,
    ) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.setPlaying(true);
      chrome.reveal();
      await tester.pump(const Duration(seconds: 4));
      expect(chrome.mode, ChromeMode.rail);
      await tester.pump(const Duration(seconds: 1));
      expect(chrome.mode, ChromeMode.hidden);
      chrome.dispose();
    });

    testWidgets('does not hide while paused', (tester) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.setPlaying(false);
      chrome.reveal();
      await tester.pump(const Duration(seconds: 10));
      expect(chrome.mode, ChromeMode.rail);
      chrome.dispose();
    });

    testWidgets('paused chrome becomes ambient at 10s, deeply dimmed at 120s', (
      tester,
    ) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.setPlaying(false);
      chrome.reveal();
      expect(chrome.pausePresentation, PausePresentation.frame);
      await tester.pump(const Duration(seconds: 9));
      expect(chrome.pausePresentation, PausePresentation.frame);
      await tester.pump(const Duration(seconds: 1));
      expect(chrome.pausePresentation, PausePresentation.ambient);
      await tester.pump(const Duration(seconds: 109));
      expect(chrome.pausePresentation, PausePresentation.ambient);
      await tester.pump(const Duration(seconds: 1));
      expect(chrome.pausePresentation, PausePresentation.dimmed);
      chrome.dispose();
    });

    testWidgets('input recovers the dimmed paused chrome back to frame', (
      tester,
    ) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.reveal();
      await tester.pump(const Duration(seconds: 121));
      expect(chrome.pausePresentation, PausePresentation.dimmed);
      chrome.reveal();
      expect(chrome.pausePresentation, PausePresentation.frame);
      await tester.pump(const Duration(seconds: 9));
      expect(chrome.pausePresentation, PausePresentation.frame);
      chrome.dispose();
    });

    testWidgets(
      'hide timer does not fire while a panel is open, resumes after close',
      (tester) async {
        var exitCount = 0;
        final chrome = PlayerChromeController(onExit: () => exitCount++);
        chrome.setPlaying(true);
        chrome.reveal();
        chrome.openPanel();
        await tester.pump(const Duration(seconds: 10));
        expect(chrome.mode, ChromeMode.panel);
        chrome.closePanel();
        expect(chrome.mode, ChromeMode.rail);
        await tester.pump(const Duration(seconds: 5));
        expect(chrome.mode, ChromeMode.hidden);
        chrome.dispose();
      },
    );

    testWidgets('scrubbing and shuttle enter/exit back to rail', (
      tester,
    ) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.enterScrubbing();
      expect(chrome.mode, ChromeMode.scrubbing);
      chrome.exitScrubbing();
      expect(chrome.mode, ChromeMode.rail);

      chrome.enterShuttle();
      expect(chrome.mode, ChromeMode.shuttle);
      chrome.exitShuttle();
      expect(chrome.mode, ChromeMode.rail);
      chrome.dispose();
    });

    testWidgets('postVideo owns the mode and ignores reveal() while active', (
      tester,
    ) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.enterPostVideo();
      expect(chrome.mode, ChromeMode.postVideo);
      chrome.reveal();
      expect(chrome.mode, ChromeMode.postVideo);
      chrome.exitPostVideo();
      expect(chrome.mode, ChromeMode.rail);
      chrome.dispose();
    });

    testWidgets('error dismiss/retry is blocked for 300ms after entering', (
      tester,
    ) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.showError();
      expect(chrome.canDismissError, isFalse);
      chrome.dismissError();
      expect(chrome.mode, ChromeMode.error);
      await tester.pump(const Duration(milliseconds: 299));
      expect(chrome.canDismissError, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(chrome.canDismissError, isTrue);
      chrome.dismissError();
      expect(chrome.mode, ChromeMode.rail);
      chrome.dispose();
    });

    testWidgets(
      'Back closes a transient mode first, then exits from plain player',
      (tester) async {
        var exitCount = 0;
        final chrome = PlayerChromeController(onExit: () => exitCount++);
        chrome.openPanel();
        expect(chrome.handleBack(), isTrue);
        expect(chrome.mode, ChromeMode.rail);

        expect(chrome.handleBack(), isTrue);
        expect(chrome.mode, ChromeMode.exiting);
        expect(exitCount, 0);
        await tester.pump(const Duration(milliseconds: 399));
        expect(exitCount, 0);
        await tester.pump(const Duration(milliseconds: 1));
        expect(exitCount, 1);
        chrome.dispose();
      },
    );

    testWidgets(
      'exit fires the callback exactly once even if requested twice',
      (tester) async {
        var exitCount = 0;
        final chrome = PlayerChromeController(onExit: () => exitCount++);
        chrome.requestExit();
        chrome.requestExit();
        await tester.pump(const Duration(milliseconds: 400));
        expect(exitCount, 1);
        chrome.dispose();
      },
    );

    testWidgets('dispose cancels every pending timer', (tester) async {
      var exitCount = 0;
      final chrome = PlayerChromeController(onExit: () => exitCount++);
      chrome.setPlaying(true);
      chrome.reveal();
      chrome.dispose();
      await tester.pump(const Duration(seconds: 10));
      expect(exitCount, 0);
    });
  });

  group('PlayerScreen', () {
    testWidgets('surface stays stable across chrome, ticks, and overlay', (
      tester,
    ) async {
      final controller = FakePlaybackController();
      final surface = _CountingSurface();
      final modes = <SystemUiMode>[];
      final back = BackDispatcher();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: surface,
            backDispatcher: back,
            setSystemUiMode: (mode) async => modes.add(mode),
          ),
        ),
      );
      expect(surface.builds, 1);
      expect(modes, <SystemUiMode>[SystemUiMode.immersiveSticky]);

      for (var index = 0; index < 200; index++) {
        controller.advanceTo(Duration(seconds: index));
      }
      await tester.pump();
      expect(surface.builds, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('player-box-options')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('player-overlay')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('close-player-overlay')),
      );
      await tester.pump();
      expect(surface.builds, 1);

      controller.failWith(
        PlaybackFailure.openFailed(cause: StateError('fixture')),
      );
      await tester.pump();
      expect(modes.last, SystemUiMode.edgeToEdge);
      expect(surface.builds, 1);
      await controller.dispose();
    });

    testWidgets('loading skeleton shows before duration/position land', (
      tester,
    ) async {
      final controller = FakePlaybackController();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: _CountingSurface(),
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('player-loading-label')),
        findsOneWidget,
      );

      controller.setDuration(const Duration(minutes: 10));
      controller.advanceTo(const Duration(seconds: 1));
      await controller.play();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('player-loading-label')),
        findsNothing,
      );
      await controller.dispose();
    });

    testWidgets('buffering renders without ever removing the surface', (
      tester,
    ) async {
      final controller = _FakeController();
      final surface = _CountingSurface();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: surface,
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      controller.emit(
        PlaybackState.initial().copyWith(
          duration: const Duration(minutes: 5),
          position: const Duration(minutes: 1),
          isPlaying: true,
          isBuffering: true,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('player-buffering-indicator')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('video-surface')),
        findsOneWidget,
      );
      expect(surface.builds, 1);

      controller.emit(controller.currentState.copyWith(isBuffering: false));
      // Deliver the async broadcast event before painting its scheduled frame.
      await tester.idle();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('player-buffering-indicator')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('video-surface')),
        findsOneWidget,
      );
      expect(surface.builds, 1);
      await controller.dispose();
    });

    testWidgets('compatibility notice renders once media has loaded', (
      tester,
    ) async {
      final controller = FakePlaybackController();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: _CountingSurface(),
            compatibilityNotice: 'Playing in software decode mode',
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('player-compatibility-notice')),
        findsNothing,
      );
      controller.setDuration(const Duration(minutes: 10));
      controller.advanceTo(const Duration(seconds: 1));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('player-compatibility-notice')),
        findsOneWidget,
      );
      expect(find.text('Playing in software decode mode'), findsOneWidget);
      await controller.dispose();
    });

    testWidgets('error overlay retry/dismiss is blocked for 300ms then works', (
      tester,
    ) async {
      final controller = FakePlaybackController();
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: _CountingSurface(),
            setSystemUiMode: (_) async {},
            onRetry: () => retried = true,
          ),
        ),
      );
      controller.failWith(
        PlaybackFailure.openFailed(cause: StateError('fixture')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('player-error-overlay')),
        findsOneWidget,
      );

      final dismissButton = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('player-error-dismiss')),
      );
      expect(dismissButton.onActivate, isNull);

      await tester.pump(const Duration(milliseconds: 300));
      final retryButton = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('player-error-retry')),
      );
      expect(retryButton.onActivate, isNotNull);
      await tester.tap(
        find.byKey(const ValueKey<String>('player-error-retry')),
      );
      await tester.pump();
      expect(retried, isTrue);
      expect(
        find.byKey(const ValueKey<String>('player-error-overlay')),
        findsNothing,
      );
      await controller.dispose();
    });

    testWidgets('session replacement tears down the old session cleanly', (
      tester,
    ) async {
      final first = FakePlaybackController();
      final second = FakePlaybackController();
      final firstSurface = _CountingSurface();
      final secondSurface = _CountingSurface();
      PlaybackController activeController = first;
      VideoSurface activeSurface = firstSurface;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  TextButton(
                    key: const ValueKey<String>('swap-session'),
                    onPressed: () => setState(() {
                      activeController = second;
                      activeSurface = secondSurface;
                    }),
                    child: const Text('swap'),
                  ),
                  Expanded(
                    child: PlayerScreen(
                      controller: activeController,
                      videoSurface: activeSurface,
                      setSystemUiMode: (_) async {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(firstSurface.builds, 1);
      expect(secondSurface.builds, 0);

      await tester.tap(find.byKey(const ValueKey<String>('swap-session')));
      await tester.pump();
      expect(secondSurface.builds, 1);

      // A late event from the torn-down first controller must not throw or
      // reach the new session's chrome (pitfall: "A late controller event
      // after dispose must be ignored").
      first.advanceTo(const Duration(seconds: 42));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await first.dispose();
      await second.dispose();
    });

    testWidgets(
      'system back pops the player route once and does not re-enter the handler',
      (tester) async {
        final controller = FakePlaybackController();
        final surface = _CountingSurface();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey<String>('open-player-route'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerScreen(
                          controller: controller,
                          videoSurface: surface,
                          setSystemUiMode: (_) async {},
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('open-player-route')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('video-surface')),
          findsOneWidget,
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('video-surface')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('open-player-route')),
          findsOneWidget,
        );
        await controller.dispose();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets('system back closes an open overlay instead of exiting', (
      tester,
    ) async {
      final controller = FakePlaybackController();
      final surface = _CountingSurface();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey<String>('open-player-route'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        controller: controller,
                        videoSurface: surface,
                        setSystemUiMode: (_) async {},
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('open-player-route')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('player-box-options')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('player-overlay')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('player-overlay')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('video-surface')),
        findsOneWidget,
      );
      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('reduced motion renders without throwing through exit', (
      tester,
    ) async {
      final controller = FakePlaybackController();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: PlayerScreen(
              controller: controller,
              videoSurface: _CountingSurface(),
              setSystemUiMode: (_) async {},
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await controller.dispose();
    });

    testWidgets('player controls fit a narrow phone surface', (tester) async {
      await setLogicalSize(tester, const Size(402, 874));
      final controller = FakePlaybackController();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: _CountingSurface(),
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      controller.setDuration(const Duration(seconds: 8));
      await controller.play();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await controller.dispose();
    });
  });

  group('goldens', () {
    Future<void> pumpGolden(
      WidgetTester tester,
      Size size,
      String name, {
      required Future<void> Function(FakePlaybackController controller) arrange,
      Duration settle = Duration.zero,
    }) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, size);
      final controller = FakePlaybackController();
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: PlayerScreen(
              controller: controller,
              videoSurface: const _FixtureVideoSurface(),
              setSystemUiMode: (_) async {},
            ),
          ),
        ),
      );
      // Arranged AFTER mount, not before: `PlayerChromeController.setPlaying`
      // only reacts to a genuine edge (e.g. true→false), so a pre-mount
      // state mutation would be invisible to the chrome that binds at mount
      // — matching Rivulet's own gate on the mount-time paused flash
      // (`PlayerContainerViewController.swift:636-638`: "False until the
      // first `.playing` of the current load; gates the paused presentation
      // so a transient startup `.paused` never flashes").
      await arrange(controller);
      await tester.pump();
      if (settle > Duration.zero) {
        await tester.pump(settle);
        // A Timer-driven state change landing exactly at the end of a
        // large `pump(settle)` jump starts its implicit animation but
        // needs a further frame to actually tick it forward: `pump(duration)`
        // "does not schedule multiple frames even if the duration is longer
        // than a single frame" (Context7 /flutter/website,
        // cookbook/testing/widget/introduction.md) — flush one more.
        await tester.pump(const Duration(milliseconds: 300));
      }
      await expectLater(
        find.byType(PlayerScreen),
        matchesGoldenFile('goldens/$name'),
      );
      // A golden containing Flutter's red/yellow-striped error box (a
      // RenderFlex overflow, a failed layout assertion, ...) must never be
      // accepted as a pass: `matchesGoldenFile` only compares pixels, it
      // does not know an error box from real content. `takeException`
      // surfaces anything `FlutterError.onError` caught during the pumps
      // above so a broken layout fails the test instead of the review.
      expect(
        tester.takeException(),
        isNull,
        reason: 'no FlutterError/overflow while building $name',
      );
      await controller.dispose();
    }

    testWidgets('rail (chrome visible, playing) at 1920', (tester) async {
      await pumpGolden(
        tester,
        const Size(1920, 1080),
        'player_rail_1920.png',
        arrange: (controller) async {
          controller.setDuration(const Duration(hours: 1, minutes: 36));
          controller.advanceTo(const Duration(minutes: 22, seconds: 10));
          await controller.play();
        },
      );
    });

    testWidgets('paused ambient dim at 1920', (tester) async {
      await pumpGolden(
        tester,
        const Size(1920, 1080),
        'player_paused_ambient_1920.png',
        arrange: (controller) async {
          controller.setDuration(const Duration(hours: 1, minutes: 36));
          controller.advanceTo(const Duration(minutes: 22, seconds: 10));
          // A real true->false transition (play, then pause) — not the
          // mount-time default, which never arms the ambient timer (there
          // is no "was playing" edge to fire on).
          await controller.play();
          await controller.pause();
        },
        settle: const Duration(seconds: 10),
      );
    });

    testWidgets('loading skeleton at 1400', (tester) async {
      await pumpGolden(
        tester,
        const Size(1400, 900),
        'player_loading_1400.png',
        arrange: (_) async {},
      );
    });

    testWidgets('error overlay at 800', (tester) async {
      await pumpGolden(
        tester,
        const Size(800, 600),
        'player_error_800.png',
        arrange: (controller) async {
          controller.setDuration(const Duration(minutes: 96));
          controller.failWith(
            PlaybackFailure.openFailed(
              cause: StateError('fixture unreachable'),
            ),
          );
        },
      );
    });
  });
}
