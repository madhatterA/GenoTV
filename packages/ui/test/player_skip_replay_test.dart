import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 07 (planning/part-04-ui/chapter-03-player-ui/phase-07-skip-replay.md)
// proof file: SkipMarkerButton (skip-intro/credits/commercial pill: marker
// lifecycle, auto-fill countdown, Select consumption, hidden-chrome
// directional reveal) and SubtitleReplayController / ReplayWindow ("what
// did they say?" replay: seek back 15s, temporary subtitle, seek-landed
// gate, restoration, extension, manual override, failure/session cleanup).

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

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: Center(child: child)),
);

FakePlaybackController _controllerAt(Duration position, Duration duration) =>
    FakePlaybackController()
      ..setDuration(duration)
      ..advanceTo(position);

const UiMarker _introMarker = UiMarker(
  id: 'intro',
  kind: UiMarkerKind.intro,
  start: Duration(seconds: 5),
  end: Duration(seconds: 90),
);

const UiMarker _creditsMarker = UiMarker(
  id: 'credits',
  kind: UiMarkerKind.credits,
  start: Duration(minutes: 40),
  end: Duration(minutes: 42),
);

void main() {
  group('skipLabelFor / activeMarkerAt', () {
    test('label per marker kind', () {
      expect(skipLabelFor(UiMarkerKind.intro), 'Skip Intro');
      expect(skipLabelFor(UiMarkerKind.credits), 'Skip Credits');
      expect(skipLabelFor(UiMarkerKind.commercial), 'Skip');
    });

    test('marker enter/leave: active only within [start, end)', () {
      expect(
        activeMarkerAt(const [_introMarker], const Duration(seconds: 4)),
        isNull,
      );
      expect(
        activeMarkerAt(const [_introMarker], const Duration(seconds: 5)),
        _introMarker,
      );
      expect(
        activeMarkerAt(const [_introMarker], const Duration(seconds: 89)),
        _introMarker,
      );
      expect(
        activeMarkerAt(const [_introMarker], const Duration(seconds: 90)),
        isNull,
      );
    });
  });

  group('SkipMarkerButton widget', () {
    testWidgets('renders the marker-kind label', (tester) async {
      await tester.pumpWidget(
        _wrap(SkipMarkerButton(marker: _introMarker, onSkip: () {})),
      );
      expect(find.text('Skip Intro'), findsOneWidget);
    });

    testWidgets('tap fires onSkip exactly once', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        _wrap(SkipMarkerButton(marker: _introMarker, onSkip: () => count++)),
      );
      await tester.tap(find.byType(SkipMarkerButton));
      expect(count, 1);
    });

    testWidgets(
      'Select down does nothing; Select up fires onSkip once (full consumption)',
      (tester) async {
        var count = 0;
        final node = FocusNode();
        addTearDown(node.dispose);
        await tester.pumpWidget(
          _wrap(
            SkipMarkerButton(
              marker: _introMarker,
              onSkip: () => count++,
              focusNode: node,
              autofocus: true,
            ),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(count, 0, reason: 'Select down must not fire the skip');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(count, 1, reason: 'Select up fires the skip exactly once');
      },
    );

    testWidgets(
      'directional input while chrome hidden reveals controls, does not activate',
      (tester) async {
        var skipCount = 0;
        var directionalCalls = <LogicalKeyboardKey>[];
        final node = FocusNode();
        addTearDown(node.dispose);
        await tester.pumpWidget(
          _wrap(
            SkipMarkerButton(
              marker: _introMarker,
              onSkip: () => skipCount++,
              focusNode: node,
              autofocus: true,
              onDirectionalPress: (key) {
                directionalCalls.add(key);
                return true; // chrome hidden: consumed, surfaces controls.
              },
            ),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(directionalCalls, [LogicalKeyboardKey.arrowDown]);
        expect(skipCount, 0);
      },
    );

    testWidgets(
      'directional input with chrome visible lets focus move (not consumed)',
      (tester) async {
        final node = FocusNode();
        addTearDown(node.dispose);
        await tester.pumpWidget(
          _wrap(
            SkipMarkerButton(
              marker: _introMarker,
              onSkip: () {},
              focusNode: node,
              autofocus: true,
              onDirectionalPress: (_) => false, // chrome visible: not consumed.
            ),
          ),
        );
        await tester.pump();
        final handled = node.onKeyEvent!(
          node,
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.arrowDown,
            logicalKey: LogicalKeyboardKey.arrowDown,
            timeStamp: Duration.zero,
          ),
        );
        expect(handled, KeyEventResult.ignored);
      },
    );

    testWidgets('auto-fill fires onSkip exactly once at completion', (
      tester,
    ) async {
      var count = 0;
      await tester.pumpWidget(
        _wrap(
          SkipMarkerButton(
            marker: _introMarker,
            onSkip: () => count++,
            autoSkipDuration: const Duration(seconds: 5),
          ),
        ),
      );
      await tester.pump();
      // An AnimationController reports `completed` on the first tick strictly
      // past its duration, hence the extra frame's worth of time.
      await tester.pump(const Duration(seconds: 5, milliseconds: 16));
      expect(count, 1);
      // Completion must not re-fire on further pumps.
      await tester.pump(const Duration(seconds: 5));
      expect(count, 1);
    });

    testWidgets(
      'unmounting mid-countdown cancels the fill (pause/cancel, never fires)',
      (tester) async {
        var count = 0;
        await tester.pumpWidget(
          _wrap(
            SkipMarkerButton(
              marker: _introMarker,
              onSkip: () => count++,
              autoSkipDuration: const Duration(seconds: 5),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(_wrap(const SizedBox()));
        await tester.pump(const Duration(seconds: 5));
        expect(count, 0);
      },
    );

    testWidgets(
      'replacing the marker mid-countdown restarts the fill for the new marker',
      (tester) async {
        var introCount = 0;
        var creditsCount = 0;
        await tester.pumpWidget(
          _wrap(
            SkipMarkerButton(
              marker: _introMarker,
              onSkip: () => introCount++,
              autoSkipDuration: const Duration(seconds: 5),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(
          _wrap(
            SkipMarkerButton(
              marker: _creditsMarker,
              onSkip: () => creditsCount++,
              autoSkipDuration: const Duration(seconds: 5),
            ),
          ),
        );
        await tester.pump();
        // Old marker's countdown must have been cancelled, not fired.
        await tester.pump(const Duration(seconds: 2));
        expect(introCount, 0);
        expect(creditsCount, 0);
        await tester.pump(const Duration(seconds: 3, milliseconds: 16));
        expect(creditsCount, 1);
      },
    );
  });

  test('forced captions are replaced and restored after replay', () async {
    final controller = _TracingController()
      ..setDuration(const Duration(minutes: 5))
      ..setTracks(
        const TrackList(
          subtitle: [
            Track(id: 'forced', type: TrackType.subtitle, title: 'Forced'),
            Track(id: 'normal', type: TrackType.subtitle, title: 'English'),
          ],
        ),
      )
      ..advanceTo(const Duration(seconds: 100));
    addTearDown(controller.dispose);
    await controller.selectTrack(
      const TrackSelection(subtitle: TrackChoice.specific('forced')),
    );
    controller.trace.clear();
    final replay = SubtitleReplayController(controller: controller);
    addTearDown(replay.dispose);
    await replay.invoke();
    await pumpEventQueue();
    expect(
      controller.currentState.selected.subtitle,
      const TrackChoice.specific('normal'),
    );
    controller.advanceTo(const Duration(seconds: 101));
    await pumpEventQueue();
    expect(controller.trace, [
      'seek(0:01:25.000000)',
      'selectTrack(subtitle: TrackChoice.specific(normal))',
      'selectTrack(subtitle: TrackChoice.specific(forced))',
    ]);
  });

  testWidgets('auto-fill pauses and resumes without losing progress', (
    tester,
  ) async {
    var count = 0;
    Widget pill(bool paused) => _wrap(
      SkipMarkerButton(
        marker: _introMarker,
        onSkip: () => count++,
        autoSkipDuration: const Duration(seconds: 5),
        isPaused: paused,
      ),
    );
    await tester.pumpWidget(pill(false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(pill(true));
    await tester.pump(const Duration(seconds: 10));
    expect(count, 0);
    await tester.pumpWidget(pill(false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3, milliseconds: 16));
    expect(count, 1);
    await tester.tap(find.byType(SkipMarkerButton));
    expect(
      count,
      1,
      reason: 'manual and automatic skip share a fire-once gate',
    );
  });

  testWidgets('Select release stays consumed if pill disappears while held', (
    tester,
  ) async {
    var releases = 0;
    var skips = 0;
    Widget host(bool showPill) => _wrap(
      Focus(
        autofocus: !showPill,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) releases++;
          return KeyEventResult.ignored;
        },
        child: showPill
            ? SkipMarkerButton(
                marker: _introMarker,
                onSkip: () => skips++,
                autofocus: true,
              )
            : const SizedBox(),
      ),
    );
    await tester.pumpWidget(host(true));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpWidget(host(false));
    await tester.pump();
    final handled = await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(handled, isTrue);
    expect(releases, 0);
    expect(skips, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(releases, 1, reason: 'release guard removes itself after one cycle');
  });

  test('position ticks during pending selection retain restoration', () async {
    final controller = _DeferredSelectController()
      ..setDuration(const Duration(minutes: 5))
      ..setTracks(
        const TrackList(
          subtitle: [Track(id: 'normal', type: TrackType.subtitle)],
        ),
      )
      ..advanceTo(const Duration(seconds: 100));
    addTearDown(controller.dispose);
    final pending = Completer<void>();
    controller.nextSelection = pending;
    final replay = SubtitleReplayController(controller: controller);
    addTearDown(replay.dispose);
    final invocation = replay.invoke();
    await pumpEventQueue();
    controller.advanceTo(const Duration(seconds: 86));
    await pumpEventQueue();
    expect(replay.activeWindow, isNotNull);
    pending.complete();
    await invocation;
    await pumpEventQueue();
    controller.advanceTo(const Duration(seconds: 101));
    await pumpEventQueue();
    expect(controller.currentState.selected.subtitle, const TrackChoice.off());
  });

  test(
    're-invocation waits for pending restoration and preserves original off',
    () async {
      final controller = _DeferredSelectController()
        ..setDuration(const Duration(minutes: 5))
        ..setTracks(
          const TrackList(
            subtitle: [Track(id: 'normal', type: TrackType.subtitle)],
          ),
        )
        ..advanceTo(const Duration(seconds: 100));
      addTearDown(controller.dispose);
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue();
      final restoration = Completer<void>();
      controller.nextSelection = restoration;
      controller.advanceTo(const Duration(seconds: 101));
      await pumpEventQueue();
      expect(replay.activeWindow, isNull);
      final nextInvocation = replay.invoke();
      restoration.complete();
      await nextInvocation;
      await pumpEventQueue();
      expect(replay.activeWindow?.priorSelection, const TrackChoice.off());
      controller.advanceTo(const Duration(seconds: 102));
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.off(),
      );
    },
  );

  testWidgets('rail replay failure is presented without uncaught async error', (
    tester,
  ) async {
    final controller = _FailingSelectController()
      ..setDuration(const Duration(minutes: 5))
      ..setTracks(
        const TrackList(
          subtitle: [Track(id: 'normal', type: TrackType.subtitle)],
        ),
      )
      ..advanceTo(const Duration(seconds: 100));
    addTearDown(controller.dispose);
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PlayerScreen(
          controller: controller,
          videoSurface: const _PlainSurface(),
          formFactor: FormFactor.tv,
          onSubtitles: () {},
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('player-box-subtitles')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('player-error-overlay')),
      findsOneWidget,
    );
    expect(
      find.text('Failed to select playback track: Replay captions'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'manual choice during pending restoration remains authoritative',
    () async {
      final controller = _DeferredSelectController()
        ..setDuration(const Duration(minutes: 5))
        ..setTracks(
          const TrackList(
            subtitle: [
              Track(id: 'normal', type: TrackType.subtitle),
              Track(id: 'manual', type: TrackType.subtitle),
            ],
          ),
        )
        ..advanceTo(const Duration(seconds: 100));
      addTearDown(controller.dispose);
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue();
      final restoration = Completer<void>();
      controller.nextSelection = restoration;
      controller.advanceTo(const Duration(seconds: 101));
      await pumpEventQueue();
      await controller.selectTrack(
        const TrackSelection(subtitle: TrackChoice.specific('manual')),
      );
      await pumpEventQueue();
      restoration.complete();
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('manual'),
      );
    },
  );

  test(
    'repeat waiting on failed selection uses the failure callback',
    () async {
      final controller = _DeferredSelectController()
        ..setDuration(const Duration(minutes: 5))
        ..setTracks(
          const TrackList(
            subtitle: [Track(id: 'normal', type: TrackType.subtitle)],
          ),
        )
        ..advanceTo(const Duration(seconds: 100));
      addTearDown(controller.dispose);
      var failures = 0;
      final replay = SubtitleReplayController(
        controller: controller,
        onFailure: (_, _) => failures++,
      );
      addTearDown(replay.dispose);
      final selection = Completer<void>();
      controller.nextSelection = selection;
      final first = replay.invoke();
      await pumpEventQueue();
      final repeated = replay.invoke();
      selection.completeError(StateError('selection failed'));
      await Future.wait([first, repeated]);
      expect(replay.activeWindow, isNull);
      expect(failures, 1);
    },
  );

  test(
    'manual choice during initial pending selection remains authoritative',
    () async {
      final controller = _DeferredSelectController()
        ..setDuration(const Duration(minutes: 5))
        ..setTracks(
          const TrackList(
            subtitle: [
              Track(id: 'normal', type: TrackType.subtitle),
              Track(id: 'manual', type: TrackType.subtitle),
            ],
          ),
        )
        ..advanceTo(const Duration(seconds: 100));
      addTearDown(controller.dispose);
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      final pending = Completer<void>();
      controller.nextSelection = pending;
      final invocation = replay.invoke();
      await pumpEventQueue();
      await controller.selectTrack(
        const TrackSelection(subtitle: TrackChoice.specific('manual')),
      );
      await pumpEventQueue();
      pending.complete();
      await invocation;
      await pumpEventQueue();
      controller.advanceTo(const Duration(seconds: 101));
      await pumpEventQueue();
      expect(replay.activeWindow, isNull);
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('manual'),
      );
    },
  );

  test('replay at zero restores captions on first advancing tick', () async {
    final controller = FakePlaybackController()
      ..setDuration(const Duration(seconds: 8))
      ..setTracks(
        const TrackList(
          subtitle: [Track(id: 'normal', type: TrackType.subtitle)],
        ),
      );
    addTearDown(controller.dispose);
    final replay = SubtitleReplayController(controller: controller);
    addTearDown(replay.dispose);
    await replay.invoke();
    await pumpEventQueue();
    controller.advanceTo(const Duration(seconds: 1));
    await pumpEventQueue();
    expect(controller.recordedSeeks, [Duration.zero]);
    expect(controller.currentState.selected.subtitle, const TrackChoice.off());
  });

  for (final cancelKind in ['media', 'manual', 'dispose', 'failure']) {
    test('pending replay seek respects $cancelKind cancellation', () async {
      final controller = _DeferredSeekController()
        ..setDuration(const Duration(minutes: 5))
        ..setTracks(
          const TrackList(
            subtitle: [Track(id: 'normal', type: TrackType.subtitle)],
          ),
        )
        ..advanceTo(const Duration(seconds: 100));
      addTearDown(controller.dispose);
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      final invocation = replay.invoke();
      if (cancelKind == 'media') {
        controller.emitEvent(
          const MediaOpened(
            duration: Duration(minutes: 5),
            tracks: TrackList(),
          ),
        );
      } else if (cancelKind == 'manual') {
        await controller.selectTrack(
          const TrackSelection(subtitle: TrackChoice.auto()),
        );
      } else if (cancelKind == 'dispose') {
        replay.dispose();
      }
      await pumpEventQueue();
      if (cancelKind == 'failure') {
        final failure = expectLater(invocation, throwsStateError);
        controller.seekResult.completeError(StateError('seek failed'));
        await failure;
      } else {
        controller.seekResult.complete();
        await invocation;
      }
      expect(replay.activeWindow, isNull);
      expect(
        controller.currentState.selected.subtitle,
        cancelKind == 'manual'
            ? const TrackChoice.auto()
            : const TrackChoice.off(),
      );
    });
  }

  group('ReplayWindow (pure logic, ported from ReplayWindowTests.swift)', () {
    test('reverts when passing the invocation point', () {
      var window = const ReplayWindow(
        invokedAt: Duration(seconds: 100),
        priorSelection: TrackChoice.off(),
      );
      window = window.observing(const Duration(seconds: 90));
      expect(window.shouldRevert(const Duration(seconds: 90)), isFalse);
      expect(window.shouldRevert(const Duration(milliseconds: 100500)), isTrue);
    });

    test('extends the window without shrinking it', () {
      var window = const ReplayWindow(
        invokedAt: Duration(seconds: 100),
        priorSelection: TrackChoice.off(),
      );
      window = window.observing(const Duration(seconds: 90));
      window = window.extended(const Duration(seconds: 130));
      expect(window.shouldRevert(const Duration(seconds: 110)), isFalse);
      expect(window.shouldRevert(const Duration(milliseconds: 130100)), isTrue);
    });

    test('does not revert before armed (seek-landed gate)', () {
      var window = const ReplayWindow(
        invokedAt: Duration(seconds: 100),
        priorSelection: TrackChoice.off(),
      );
      expect(
        window.shouldRevert(const Duration(milliseconds: 100500)),
        isFalse,
      );
      window = window.observing(const Duration(seconds: 90));
      expect(window.shouldRevert(const Duration(milliseconds: 100500)), isTrue);
    });

    test('re-invoking inside the window never shrinks it', () {
      var window = const ReplayWindow(
        invokedAt: Duration(seconds: 100),
        priorSelection: TrackChoice.off(),
      );
      window = window.observing(const Duration(seconds: 90));
      window = window.extended(const Duration(seconds: 95));
      expect(window.shouldRevert(const Duration(seconds: 96)), isFalse);
      expect(window.shouldRevert(const Duration(milliseconds: 100500)), isTrue);
    });
  });

  group('SubtitleReplayController', () {
    late FakePlaybackController controller;

    setUp(() {
      controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 30))
        ..setTracks(
          const TrackList(
            subtitle: [
              Track(
                id: 'sub-en',
                type: TrackType.subtitle,
                title: 'English',
                language: 'en',
              ),
              Track(
                id: 'sub-forced',
                type: TrackType.subtitle,
                title: 'English (Forced)',
              ),
            ],
          ),
        );
    });

    tearDown(() => controller.dispose());

    test('seeks back 15s and clamps to zero near the start', () async {
      controller.advanceTo(const Duration(seconds: 10));
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue();
      expect(controller.recordedSeeks, [Duration.zero]);
    });

    test(
      'selects the preferred non-forced subtitle when subtitles were off',
      () async {
        controller.advanceTo(const Duration(seconds: 100));
        final replay = SubtitleReplayController(controller: controller);
        addTearDown(replay.dispose);
        expect(
          controller.currentState.selected.subtitle,
          const TrackChoice.off(),
        );
        await replay.invoke();
        await pumpEventQueue();
        expect(
          controller.currentState.selected.subtitle,
          const TrackChoice.specific('sub-en'),
          reason:
              'must skip the forced track when a normal preferred track exists',
        );
        expect(controller.recordedSeeks, [const Duration(seconds: 85)]);
      },
    );

    test('seek-landed gate: only reverts after an observed position below invokedAt', () async {
      controller.advanceTo(const Duration(seconds: 100));
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue(); // seek lands at 85s, subtitle selected.
      expect(controller.currentState.position, const Duration(seconds: 85));
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('sub-en'),
      );

      // A stale tick at/after invokedAt before arming must not revert.
      // (Already unreachable here since the fake's seek landed first, but
      // directly exercises the controller's own state handler again with a
      // position that has not yet passed invokedAt.)
      controller.advanceTo(const Duration(seconds: 99));
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('sub-en'),
      );

      controller.advanceTo(const Duration(seconds: 101));
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.off(),
        reason: 'restores prior (off) selection only after passing the invocation position',
      );
    });

    test('repeated invocation extends the window and preserves the original prior track', () async {
      controller.advanceTo(const Duration(seconds: 100));
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue();
      expect(controller.currentState.position, const Duration(seconds: 85));

      // Re-invoke from further along, before the window would have reverted.
      controller.advanceTo(const Duration(seconds: 120));
      await replay.invoke();
      await pumpEventQueue();
      expect(controller.recordedSeeks.last, const Duration(seconds: 105));

      // Passing the FIRST invocation point (100) must not revert yet.
      controller.advanceTo(const Duration(seconds: 110));
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('sub-en'),
      );

      // Only passing the extended point (120) reverts, to the pre-FIRST-
      // invocation track (off), not anything set in between.
      controller.advanceTo(const Duration(seconds: 121));
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.off(),
      );
    });

    test(
      'if subtitles were already on, replay only seeks and never reverts them',
      () async {
        await controller.selectTrack(
          const TrackSelection(subtitle: TrackChoice.specific('sub-en')),
        );
        controller.advanceTo(const Duration(seconds: 100));
        final replay = SubtitleReplayController(controller: controller);
        addTearDown(replay.dispose);
        await replay.invoke();
        await pumpEventQueue();
        controller.advanceTo(const Duration(seconds: 200));
        await pumpEventQueue();
        expect(
          controller.currentState.selected.subtitle,
          const TrackChoice.specific('sub-en'),
        );
      },
    );

    test('manual subtitle change mid-window is authoritative and is not later overwritten', () async {
      controller.advanceTo(const Duration(seconds: 100));
      final replay = SubtitleReplayController(controller: controller);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('sub-en'),
      );

      // The user picks a different subtitle manually (e.g. via the track
      // panel) — not something the controller itself requested.
      await controller.selectTrack(
        const TrackSelection(subtitle: TrackChoice.specific('sub-forced')),
      );
      await pumpEventQueue();

      // Passing the invocation point must NOT revert the manual choice.
      controller.advanceTo(const Duration(seconds: 101));
      await pumpEventQueue();
      expect(
        controller.currentState.selected.subtitle,
        const TrackChoice.specific('sub-forced'),
      );
    });

    test(
      'selection failure cleans up instead of leaving a stuck window',
      () async {
        final failing = _FailingSelectController()
          ..setDuration(const Duration(minutes: 30))
          ..setTracks(
            const TrackList(
              subtitle: [
                Track(id: 'sub-en', type: TrackType.subtitle, language: 'en'),
              ],
            ),
          )
          ..advanceTo(const Duration(seconds: 100));
        final replay = SubtitleReplayController(controller: failing);
        addTearDown(replay.dispose);
        await expectLater(replay.invoke(), throwsStateError);
        await pumpEventQueue();
        expect(
          replay.activeWindow,
          isNull,
          reason: 'a failed selection must clear the window',
        );
        // No lingering revert attempt on a later tick.
        failing.advanceTo(const Duration(seconds: 200));
        await pumpEventQueue();
        expect(failing.currentState.selected.subtitle, const TrackChoice.off());
      },
    );

    test(
      'dispose (session/media change) cancels the window without reverting',
      () async {
        controller.advanceTo(const Duration(seconds: 100));
        final replay = SubtitleReplayController(controller: controller);
        await replay.invoke();
        await pumpEventQueue();
        expect(
          controller.currentState.selected.subtitle,
          const TrackChoice.specific('sub-en'),
        );
        replay.dispose();
        controller.advanceTo(const Duration(seconds: 200));
        await pumpEventQueue();
        expect(
          controller.currentState.selected.subtitle,
          const TrackChoice.specific('sub-en'),
          reason: 'disposed controller must not act on later ticks',
        );
      },
    );

    test('controller call trace: seek, select, then restore after passing invocation', () async {
      final traced = _TracingController()
        ..setDuration(const Duration(minutes: 30))
        ..setTracks(
          const TrackList(
            subtitle: [
              Track(
                id: 'sub-forced',
                type: TrackType.subtitle,
                title: 'Forced',
              ),
              Track(id: 'sub-en', type: TrackType.subtitle, language: 'en'),
            ],
          ),
        )
        ..advanceTo(const Duration(seconds: 100));
      addTearDown(traced.dispose);
      final replay = SubtitleReplayController(controller: traced);
      addTearDown(replay.dispose);
      await replay.invoke();
      await pumpEventQueue();
      traced.advanceTo(const Duration(seconds: 99));
      await pumpEventQueue();
      traced.advanceTo(const Duration(seconds: 101));
      await pumpEventQueue();
      expect(traced.trace, [
        'seek(0:01:25.000000)',
        'selectTrack(subtitle: TrackChoice.specific(sub-en))',
        'selectTrack(subtitle: TrackChoice.off())',
      ]);
      const tracePath = String.fromEnvironment('REPLAY_TRACE_PATH');
      if (tracePath.isNotEmpty) {
        await File(tracePath).writeAsString('${traced.trace.join('\n')}\n');
      }
    });

    test(
      'invoke() before duration is known (still loading) is a no-op',
      () async {
        final fresh = FakePlaybackController();
        addTearDown(fresh.dispose);
        final replay = SubtitleReplayController(controller: fresh);
        addTearDown(replay.dispose);
        await replay.invoke();
        await pumpEventQueue();
        expect(fresh.recordedSeeks, isEmpty);
      },
    );
  });

  group(
    'SubtitleReplayController wired into PlayerScreen (no external override)',
    () {
      testWidgets('long-pressing the subtitles rail button invokes replay', (
        tester,
      ) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        final controller = _controllerAt(
          const Duration(minutes: 2),
          const Duration(hours: 1),
        );
        controller.setTracks(
          const TrackList(
            subtitle: [
              Track(id: 'sub-en', type: TrackType.subtitle, language: 'en'),
            ],
          ),
        );
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
                formFactor: FormFactor.tv,
                title: 'Iron Man 3',
                onSubtitles: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(
            find.byKey(const ValueKey<String>('player-box-subtitles')),
          ),
        );
        // Past TransportControlButton.longPressThreshold (600 ms).
        await tester.pump(const Duration(milliseconds: 700));
        await gesture.up();
        await tester.pump();
        expect(controller.recordedSeeks, [const Duration(seconds: 105)]);
        expect(
          controller.currentState.selected.subtitle,
          const TrackChoice.specific('sub-en'),
        );
        addTearDown(controller.dispose);
      });
    },
  );

  group('goldens', () {
    Future<FakePlaybackController> pumpGolden(
      WidgetTester tester,
      String name, {
      required bool chromeVisible,
    }) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1920, 1080));
      final controller = _controllerAt(
        const Duration(seconds: 30),
        const Duration(hours: 1),
      );
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
              formFactor: FormFactor.tv,
              title: 'Iron Man 3',
              rating: 'PG-13',
              runtimeLabel: '2h 10m',
              audioLabel: 'Atmos',
              markers: const [_introMarker],
              onSubtitles: () {},
              onAudioTrack: () {},
              onInfo: () {},
              onUpNext: () {},
            ),
          ),
        ),
      );
      await controller.play();
      await tester.pump();
      await tester.pump(); // post-frame rail measurement → pill placed.
      if (!chromeVisible) {
        // Chrome auto-hides after 5s of playback (PlayerChromeController.hideDelay),
        // then fades out over 180 ms.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 300));
      }
      // Pill bottom = rail top + offset (PlayerContainerViewController.swift:315-320,650-653).
      final railTop = tester
          .getTopLeft(find.byKey(const ValueKey<String>('player-control-rail')))
          .dy;
      final pillBottom = tester.getBottomLeft(find.byType(SkipMarkerButton)).dy;
      final offset = chromeVisible
          ? SkipMarkerButton.skipPillRaisedOffset
          : SkipMarkerButton.skipPillLoweredOffset;
      expect(pillBottom, closeTo(railTop + offset, 1.0));
      expect(find.text('Skip Intro'), findsOneWidget);
      await expectLater(
        find.byType(PlayerScreen),
        matchesGoldenFile('goldens/$name'),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'no FlutterError/overflow while building $name',
      );
      return controller;
    }

    testWidgets('skip pill, chrome visible (raised) at 1920x1080', (
      tester,
    ) async {
      final controller = await pumpGolden(
        tester,
        'skip_pill_chrome_visible.png',
        chromeVisible: true,
      );
      addTearDown(controller.dispose);
    });

    testWidgets('skip pill, chrome hidden (lowered) at 1920x1080', (
      tester,
    ) async {
      final controller = await pumpGolden(
        tester,
        'skip_pill_chrome_hidden.png',
        chromeVisible: false,
      );
      addTearDown(controller.dispose);
    });
  });
}

/// A [PlaybackController] whose [selectTrack] always fails, to exercise
/// `SubtitleReplayController`'s selection-failure cleanup path.
class _FailingSelectController extends FakePlaybackController {
  @override
  Future<void> selectTrack(TrackSelection selection) =>
      Future.error(StateError('selection failed'));
}

class _DeferredSeekController extends FakePlaybackController {
  final seekResult = Completer<void>();
  @override
  Future<void> seek(Duration position) => seekResult.future;
}

class _DeferredSelectController extends FakePlaybackController {
  Completer<void>? nextSelection;
  @override
  Future<void> selectTrack(TrackSelection selection) async {
    final pending = nextSelection;
    nextSelection = null;
    if (pending != null) await pending.future;
    await super.selectTrack(selection);
  }
}

class _PlainSurface extends FakeVideoSurface {
  const _PlainSurface();
  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.cover,
    Color background = Colors.black,
  }) => ColoredBox(color: background);
}

/// Records the seek/selectTrack call sequence for the trace confirmation.
class _TracingController extends FakePlaybackController {
  final List<String> trace = <String>[];

  @override
  Future<void> seek(Duration position) {
    trace.add('seek($position)');
    return super.seek(position);
  }

  @override
  Future<void> selectTrack(TrackSelection selection) {
    trace.add('selectTrack(subtitle: ${selection.subtitle})');
    return super.selectTrack(selection);
  }
}
