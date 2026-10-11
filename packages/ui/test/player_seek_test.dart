import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

/// Records every call so tests can assert the exact controller-call list,
/// per this phase's confirmation criteria. Mirrors the `_Controller` fake
/// already used in `scrubber_test.dart`/`player_scaffold_test.dart`.
class _FakeController implements PlaybackController {
  @override
  PlaybackState currentState = PlaybackState.initial();

  final List<Duration> seeks = <Duration>[];
  int plays = 0;
  int pauses = 0;

  @override
  Stream<PlaybackState> get state => const Stream<PlaybackState>.empty();
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
  Future<void> play() async {
    plays++;
    currentState = currentState.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    currentState = currentState.copyWith(isPlaying: false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    currentState = currentState.copyWith(position: position);
  }

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
  Future<void> dispose() async {}
}

UiCommand _cmd(
  UiCommandType type, {
  CommandSource source = CommandSource.keyboard,
  Duration timestamp = Duration.zero,
  int repeatCount = 1,
}) => UiCommand(
  type,
  source: source,
  timestamp: timestamp,
  repeatCount: repeatCount,
);

void main() {
  group('SeekController tap step — allowed sizes', () {
    for (final seconds in kAllowedTapSeekSeconds) {
      testWidgets('$seconds s forward, then flush at the 50ms coalesce', (
        tester,
      ) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 1),
            duration: const Duration(minutes: 10),
          );
        final seek = SeekController(controller: fake, tapSeekSeconds: seconds);
        seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
        await tester.pump(const Duration(milliseconds: 60));
        expect(fake.seeks, [
          const Duration(minutes: 1) + Duration(seconds: seconds),
        ]);
        seek.dispose();
      });
    }

    testWidgets('backward step is negative', (tester) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 10),
        );
      final seek = SeekController(controller: fake);
      seek.handleCommand(_cmd(UiCommandType.stepSeekBackward));
      await tester.pump(const Duration(milliseconds: 60));
      expect(fake.seeks, [const Duration(seconds: 30)]);
      seek.dispose();
    });

    test('constructing with a disallowed step size asserts', () {
      final fake = _FakeController();
      expect(
        () => SeekController(controller: fake, tapSeekSeconds: 7),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SeekController bounds', () {
    testWidgets('clamps to zero at the start of the timeline', (tester) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(seconds: 10),
          duration: const Duration(minutes: 10),
        );
      final seek = SeekController(controller: fake);
      seek.handleCommand(_cmd(UiCommandType.stepSeekBackward));
      await tester.pump(const Duration(milliseconds: 60));
      expect(fake.seeks, [Duration.zero]);
      seek.dispose();
    });

    testWidgets('clamps to duration at the end of the timeline', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 10) - const Duration(seconds: 5),
          duration: const Duration(minutes: 10),
        );
      final seek = SeekController(controller: fake);
      seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
      await tester.pump(const Duration(milliseconds: 60));
      expect(fake.seeks, [const Duration(minutes: 10)]);
      seek.dispose();
    });
  });

  group('SeekController 50ms burst coalesce boundary', () {
    testWidgets('two presses 49ms apart coalesce into one summed seek', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          duration: const Duration(minutes: 10),
        );
      final seek = SeekController(controller: fake);
      seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
      await tester.pump(const Duration(milliseconds: 49));
      seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
      await tester.pump(const Duration(milliseconds: 60));
      expect(fake.seeks, [const Duration(seconds: 60)]);
      seek.dispose();
    });

    testWidgets('a press 50ms after the first flushes separately (two seeks)', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          duration: const Duration(minutes: 10),
        );
      final seek = SeekController(controller: fake);
      seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
      await tester.pump(const Duration(milliseconds: 50));
      seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
      await tester.pump(const Duration(milliseconds: 60));
      expect(fake.seeks, [
        const Duration(seconds: 30),
        const Duration(seconds: 60),
      ]);
      seek.dispose();
    });
  });

  group('SeekController chapter jump', () {
    test(
      'pure chapterTarget: forward picks the first boundary after "from"',
      () {
        final starts = [
          Duration.zero,
          const Duration(minutes: 5),
          const Duration(minutes: 12),
        ];
        expect(
          SeekController.chapterTarget(
            from: const Duration(minutes: 6),
            chapterStarts: starts,
            forward: true,
          ),
          const Duration(minutes: 12),
        );
      },
    );

    test('pure chapterTarget: backward excludes a boundary within 2s', () {
      final starts = [
        Duration.zero,
        const Duration(minutes: 5),
        const Duration(minutes: 12),
      ];
      // 1s past the 5-minute boundary: still excluded, snaps to zero.
      expect(
        SeekController.chapterTarget(
          from: const Duration(minutes: 5) + const Duration(seconds: 1),
          chapterStarts: starts,
          forward: false,
        ),
        Duration.zero,
      );
    });

    test(
      'pure chapterTarget: backward exactly at the 2s boundary still excludes',
      () {
        final starts = [Duration.zero, const Duration(minutes: 5)];
        expect(
          SeekController.chapterTarget(
            from: const Duration(minutes: 5) + const Duration(seconds: 2),
            chapterStarts: starts,
            forward: false,
          ),
          Duration.zero,
        );
      },
    );

    test('pure chapterTarget: backward past 2s selects the boundary', () {
      final starts = [Duration.zero, const Duration(minutes: 5)];
      expect(
        SeekController.chapterTarget(
          from: const Duration(minutes: 5) + const Duration(seconds: 3),
          chapterStarts: starts,
          forward: false,
        ),
        const Duration(minutes: 5),
      );
    });

    test(
      'pure chapterTarget: forward with no further boundary returns null',
      () {
        final starts = [Duration.zero, const Duration(minutes: 5)];
        expect(
          SeekController.chapterTarget(
            from: const Duration(minutes: 6),
            chapterStarts: starts,
            forward: true,
          ),
          isNull,
        );
      },
    );

    testWidgets('jumpSeekForward snaps to the next chapter', (tester) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 20),
          chapters: const [
            Chapter(start: Duration.zero),
            Chapter(start: Duration(minutes: 5)),
            Chapter(start: Duration(minutes: 12)),
          ],
        );
      final seek = SeekController(controller: fake);
      await seek.chapterJump(forward: true);
      expect(fake.seeks, [const Duration(minutes: 5)]);
      seek.dispose();
    });

    testWidgets(
      'jumpSeekBackward with no chapters falls back to a fixed 30s jump',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 1),
            duration: const Duration(minutes: 20),
          );
        final seek = SeekController(controller: fake);
        await seek.chapterJump(forward: false);
        expect(fake.seeks, [const Duration(seconds: 30)]);
        seek.dispose();
      },
    );

    testWidgets(
      'a chapter jump flushes and discards any pending tap-step coalesce',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 1),
            duration: const Duration(minutes: 20),
            chapters: const [Chapter(start: Duration(minutes: 5))],
          );
        final seek = SeekController(controller: fake);
        seek.handleCommand(_cmd(UiCommandType.stepSeekForward));
        await seek.chapterJump(forward: true);
        // Only the chapter jump lands; the pending tap step never flushes.
        expect(fake.seeks, [const Duration(minutes: 5)]);
        await tester.pump(const Duration(milliseconds: 60));
        expect(fake.seeks, [const Duration(minutes: 5)]);
        seek.dispose();
      },
    );
  });

  group('ShuttleGrammar transition matrix', () {
    test('0 -> forward -> 1 -> 2 -> 3 -> 3 (capped)', () {
      var level = 0;
      level = ShuttleGrammar.step(current: level, clickForward: true);
      expect(level, 1);
      level = ShuttleGrammar.step(current: level, clickForward: true);
      expect(level, 2);
      level = ShuttleGrammar.step(current: level, clickForward: true);
      expect(level, 3);
      level = ShuttleGrammar.step(current: level, clickForward: true);
      expect(level, 3, reason: 'capped at maxLevel');
    });

    test(
      '3 -> opposite -> 2 -> 1 -> crosses to -1 -> -2 -> -3 -> -3 (capped)',
      () {
        var level = 3;
        level = ShuttleGrammar.step(current: level, clickForward: false);
        expect(level, 2);
        level = ShuttleGrammar.step(current: level, clickForward: false);
        expect(level, 1);
        level = ShuttleGrammar.step(current: level, clickForward: false);
        expect(
          level,
          -1,
          reason:
              'crosses through zero into the opposite direction, not cancel',
        );
        level = ShuttleGrammar.step(current: level, clickForward: false);
        expect(level, -2);
        level = ShuttleGrammar.step(current: level, clickForward: false);
        expect(level, -3);
        level = ShuttleGrammar.step(current: level, clickForward: false);
        expect(level, -3, reason: 'capped at -maxLevel');
      },
    );

    test('0 -> backward -> -1', () {
      expect(ShuttleGrammar.step(current: 0, clickForward: false), -1);
    });

    test(
      'badges: 1/2/3 -> 2x/4x/6x, mirrored for reverse, zero has no badge',
      () {
        expect(ShuttleGrammar.badge(1), '▶ 2x');
        expect(ShuttleGrammar.badge(2), '▶ 4x');
        expect(ShuttleGrammar.badge(3), '▶ 6x');
        expect(ShuttleGrammar.badge(-1), '◀ 2x');
        expect(ShuttleGrammar.badge(-2), '◀ 4x');
        expect(ShuttleGrammar.badge(-3), '◀ 6x');
        expect(ShuttleGrammar.badge(0), isNull);
      },
    );

    test('rates: 15/60/240 content-seconds per real second', () {
      expect(ShuttleGrammar.rate(1), 15);
      expect(ShuttleGrammar.rate(2), 60);
      expect(ShuttleGrammar.rate(3), 240);
      expect(ShuttleGrammar.rate(-1), 15);
      expect(ShuttleGrammar.rate(-3), 240);
    });
  });

  group('ShuttleController', () {
    testWidgets('first nudge enters shuttle at level 1, pauses playback', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 20),
          isPlaying: true,
        );
      final shuttle = ShuttleController(controller: fake);
      shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward));
      expect(shuttle.level, 1);
      expect(shuttle.isActive, isTrue);
      expect(fake.pauses, 1);
      await shuttle.cancel();
      shuttle.dispose();
    });

    testWidgets(
      'preview advances every 100ms at the level-1 rate (15 content-sec/real-sec)',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 2),
            duration: const Duration(minutes: 20),
          );
        final shuttle = ShuttleController(controller: fake);
        shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward));
        await tester.pump(const Duration(milliseconds: 100));
        // 15 sec/real-sec * 0.1s = 1.5s per tick.
        expect(
          shuttle.previewPosition,
          const Duration(minutes: 2) + const Duration(milliseconds: 1500),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          shuttle.previewPosition,
          const Duration(minutes: 2) + const Duration(milliseconds: 3000),
        );
        // No controller.seek yet — preview only.
        expect(fake.seeks, isEmpty);
        await shuttle.cancel();
        shuttle.dispose();
      },
    );

    testWidgets(
      'commit seeks to the preview position and resumes play if it was playing',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 2),
            duration: const Duration(minutes: 20),
            isPlaying: true,
          );
        final shuttle = ShuttleController(controller: fake);
        shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward));
        await tester.pump(const Duration(milliseconds: 200));
        final previewed = shuttle.previewPosition;
        shuttle.handleCommand(_cmd(UiCommandType.selectDown));
        await tester.pump();
        expect(fake.seeks, [previewed]);
        expect(
          fake.plays,
          1,
          reason: 'was playing at invocation, so resumes after commit',
        );
        expect(shuttle.isActive, isFalse);
        shuttle.dispose();
      },
    );

    testWidgets('commit does not resume play when paused at invocation', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 20),
          isPlaying: false,
        );
      final shuttle = ShuttleController(controller: fake);
      shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward));
      await tester.pump(const Duration(milliseconds: 100));
      shuttle.handleCommand(_cmd(UiCommandType.selectDown));
      await tester.pump();
      expect(fake.seeks, hasLength(1));
      expect(fake.plays, 0);
      shuttle.dispose();
    });

    testWidgets(
      'cancel (Back) never seeks and restores play state, ticker stops',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 2),
            duration: const Duration(minutes: 20),
            isPlaying: true,
          );
        final shuttle = ShuttleController(controller: fake);
        shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward));
        await tester.pump(const Duration(milliseconds: 100));
        shuttle.handleCommand(_cmd(UiCommandType.menuBack));
        await tester.pump();
        expect(fake.seeks, isEmpty);
        expect(fake.plays, 1);
        expect(shuttle.isActive, isFalse);
        // Ticker is really stopped — no further preview movement or duplicate calls.
        await tester.pump(const Duration(milliseconds: 300));
        expect(fake.seeks, isEmpty);
        expect(fake.plays, 1);
        shuttle.dispose();
      },
    );

    testWidgets('directionDown also cancels', (tester) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          duration: const Duration(minutes: 20),
        );
      final shuttle = ShuttleController(controller: fake);
      shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward));
      shuttle.handleCommand(_cmd(UiCommandType.directionDown));
      await tester.pump();
      expect(shuttle.isActive, isFalse);
      expect(fake.seeks, isEmpty);
      shuttle.dispose();
    });

    testWidgets(
      'repeated commits/cancels while inactive are no-ops (no duplicate controller calls)',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            duration: const Duration(minutes: 20),
          );
        final shuttle = ShuttleController(controller: fake);
        await shuttle.commit();
        await shuttle.cancel();
        expect(fake.seeks, isEmpty);
        expect(fake.plays, 0);
        expect(fake.pauses, 0);
        shuttle.dispose();
      },
    );

    testWidgets(
      'opposite-direction click crosses through zero without cancelling the mode',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 5),
            duration: const Duration(minutes: 20),
          );
        final shuttle = ShuttleController(controller: fake);
        shuttle.handleCommand(_cmd(UiCommandType.scrubNudgeForward)); // 1
        shuttle.handleCommand(
          _cmd(UiCommandType.scrubNudgeBackward),
        ); // -1, still active
        expect(shuttle.level, -1);
        expect(shuttle.isActive, isTrue);
        expect(fake.pauses, 1, reason: 'only paused once, on entry');
        await shuttle.cancel();
        shuttle.dispose();
      },
    );
  });

  group('WheelGesture', () {
    testWidgets('a sample inside the .2 deadzone is ignored', (tester) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          duration: const Duration(minutes: 20),
        );
      final wheel = WheelGesture(controller: fake);
      wheel.addSample(0.1, 0.1); // radius ~0.14 < 0.2
      expect(wheel.isActive, isFalse);
      expect(fake.pauses, 0);
      wheel.dispose();
    });

    testWidgets('a sample between .2 and .7 resets tracking without seeking', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          duration: const Duration(minutes: 20),
        );
      final wheel = WheelGesture(controller: fake);
      wheel.addSample(0.9, 0); // anchor on the ring
      wheel.addSample(0.4, 0); // radius 0.4: past deadzone, short of ring
      expect(wheel.isActive, isFalse);
      wheel.dispose();
    });

    testWidgets(
      'rotation past the .3 rad threshold applies 10 s/radian and enters scrub',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 3),
            duration: const Duration(minutes: 20),
            isPlaying: true,
          );
        final wheel = WheelGesture(controller: fake);
        // Anchor at angle 0 on the outer ring (radius 1.0).
        wheel.addSample(1.0, 0.0);
        // Rotate by 0.35 rad (> 0.3 threshold): angle = 0.35.
        wheel.addSample(math.cos(0.35), math.sin(0.35));
        expect(
          wheel.isActive,
          isTrue,
          reason: 'crossing the threshold starts the scrub session',
        );
        expect(fake.pauses, 1);
        // 0.35 rad * 10 s/rad = 3.5s forward.
        expect(
          wheel.previewPosition,
          const Duration(minutes: 3) + const Duration(milliseconds: 3500),
        );
        await wheel.cancel();
        wheel.dispose();
      },
    );

    testWidgets(
      'sub-threshold rotation accumulates but does not move the preview yet',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            position: const Duration(minutes: 3),
            duration: const Duration(minutes: 20),
          );
        final wheel = WheelGesture(controller: fake);
        wheel.addSample(1.0, 0.0);
        wheel.addSample(
          math.cos(0.1),
          math.sin(0.1),
        ); // 0.1 rad < 0.3 threshold
        expect(wheel.isActive, isFalse);
        wheel.dispose();
      },
    );

    testWidgets('idle for 800ms auto-commits the preview', (tester) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 3),
          duration: const Duration(minutes: 20),
        );
      final wheel = WheelGesture(controller: fake);
      wheel.addSample(1.0, 0.0);
      wheel.addSample(math.cos(0.35), math.sin(0.35));
      final previewed = wheel.previewPosition;
      await tester.pump(const Duration(milliseconds: 799));
      expect(fake.seeks, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(fake.seeks, [previewed]);
      expect(wheel.isActive, isFalse);
      wheel.dispose();
    });

    testWidgets('Select commits immediately without waiting for idle', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 3),
          duration: const Duration(minutes: 20),
        );
      final wheel = WheelGesture(controller: fake);
      wheel.addSample(1.0, 0.0);
      wheel.addSample(math.cos(0.35), math.sin(0.35));
      wheel.handleCommand(_cmd(UiCommandType.selectDown));
      await tester.pump();
      expect(fake.seeks, hasLength(1));
      wheel.dispose();
    });

    testWidgets('Down/Back cancels to the invocation position, no seek', (
      tester,
    ) async {
      final fake = _FakeController()
        ..currentState = PlaybackState.initial().copyWith(
          position: const Duration(minutes: 3),
          duration: const Duration(minutes: 20),
          isPlaying: true,
        );
      final wheel = WheelGesture(controller: fake);
      wheel.addSample(1.0, 0.0);
      wheel.addSample(math.cos(0.35), math.sin(0.35));
      wheel.handleCommand(_cmd(UiCommandType.menuBack));
      await tester.pump();
      expect(fake.seeks, isEmpty);
      expect(fake.plays, 1, reason: 'resumes the pre-wheel playing state');
      expect(wheel.isActive, isFalse);
      // No stray idle-commit fires afterward.
      await tester.pump(const Duration(milliseconds: 900));
      expect(fake.seeks, isEmpty);
      wheel.dispose();
    });
  });

  group('Cross-source and transport dedupe boundaries (InputRouter, feeding these controllers)', () {
    testWidgets(
      'two scrub-nudge holds 249ms apart from different sources still count as one bump',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            duration: const Duration(minutes: 20),
          );
        final shuttle = ShuttleController(controller: fake);
        final router = InputRouter(onCommand: shuttle.handleCommand);
        router.emit(
          UiCommandType.scrubNudgeForward,
          source: CommandSource.gamepad,
          timestamp: Duration.zero,
        );
        router.emit(
          UiCommandType.scrubNudgeForward,
          source: CommandSource.keyboard,
          timestamp: const Duration(milliseconds: 249),
        );
        expect(
          shuttle.level,
          1,
          reason: 'the 249ms cross-source repeat was deduped by the router',
        );
        await shuttle.cancel();
        shuttle.dispose();
        router.dispose();
      },
    );

    testWidgets(
      'the same hold 251ms apart from a different source is a deliberate second bump',
      (tester) async {
        final fake = _FakeController()
          ..currentState = PlaybackState.initial().copyWith(
            duration: const Duration(minutes: 20),
          );
        final shuttle = ShuttleController(controller: fake);
        final router = InputRouter(onCommand: shuttle.handleCommand);
        router.emit(
          UiCommandType.scrubNudgeForward,
          source: CommandSource.gamepad,
          timestamp: Duration.zero,
        );
        router.emit(
          UiCommandType.scrubNudgeForward,
          source: CommandSource.keyboard,
          timestamp: const Duration(milliseconds: 251),
        );
        expect(shuttle.level, 2);
        await shuttle.cancel();
        shuttle.dispose();
        router.dispose();
      },
    );

    testWidgets(
      'playPause repeats within 349ms are deduped by the router (transport window)',
      (tester) async {
        final received = <UiCommand>[];
        final router = InputRouter(onCommand: received.add);
        router.emit(
          UiCommandType.playPause,
          source: CommandSource.remote,
          timestamp: Duration.zero,
        );
        router.emit(
          UiCommandType.playPause,
          source: CommandSource.remote,
          timestamp: const Duration(milliseconds: 349),
        );
        expect(received, hasLength(1));
        router.dispose();
      },
    );

    testWidgets('playPause 351ms apart is a legitimate second press', (
      tester,
    ) async {
      final received = <UiCommand>[];
      final router = InputRouter(onCommand: received.add);
      router.emit(
        UiCommandType.playPause,
        source: CommandSource.remote,
        timestamp: Duration.zero,
      );
      router.emit(
        UiCommandType.playPause,
        source: CommandSource.remote,
        timestamp: const Duration(milliseconds: 351),
      );
      expect(received, hasLength(2));
      router.dispose();
    });
  });
}
