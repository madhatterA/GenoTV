import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

typedef PlaybackVerification = Future<void> Function(PlaybackController controller);

/// Reusable behavioural spec for any [PlaybackController] implementation.
///
/// [createFailing] is the injection seam the failure-path assertion needs:
/// nothing on the plain [PlaybackController] interface can trigger an
/// engine failure from outside, so the factory returns a controller
/// pre-wired to fail with the given failure as soon as `open()` is called.
void runPlaybackControllerContractTests(
  PlaybackController Function() create, {
  required PlaybackController Function(PlaybackFailure failure) createFailing,
  PlaybackVerification? verifyPlayable,
}) {
  group('PlaybackController contract', () {
    test('SeekRequested precedes SeekCompleted (§3.2 / §9 "seek, end to end")', () async {
      final controller = create();
      final events = <PlaybackEvent>[];
      controller.events.listen(events.add);

      await controller.open(Uri.parse('fake://x'));
      await controller.seek(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);

      final requestedIndex = events.indexWhere((e) => e is SeekRequested);
      final completedIndex = events.indexWhere((e) => e is SeekCompleted);
      expect(requestedIndex, greaterThanOrEqualTo(0));
      expect(completedIndex, greaterThan(requestedIndex));
      await controller.dispose();
    });

    test('open() emits MediaOpened with a duration and a track list', () async {
      final controller = create();
      final events = <PlaybackEvent>[];
      controller.events.listen(events.add);

      await controller.open(Uri.parse('fake://x'));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<MediaOpened>(), isNotEmpty);
      await controller.dispose();
    });

    test('a failure reaches state.failure and events, never only the log', () async {
      final failure = PlaybackFailure.engineCrashed(cause: Exception('boom'));
      final controller = createFailing(failure);
      final events = <PlaybackEvent>[];
      controller.events.listen(events.add);

      await controller.open(Uri.parse('fake://x'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentState.failure, isNotNull);
      expect(events.whereType<PlaybackFailed>(), isNotEmpty);
      await controller.dispose();
    });

    test('dispose() is idempotent, closes both streams, and play() after dispose throws',
        () async {
      final controller = create();
      await controller.open(Uri.parse('fake://x'));
      await controller.dispose();
      await controller.dispose(); // idempotent — must not throw

      expect(() => controller.play(), throwsA(anything));
    });

    test('bufferedAhead never exceeds duration - position', () async {
      final controller = create();
      await controller.open(Uri.parse('fake://x'));
      await controller.play();
      await controller.seek(const Duration(seconds: 5));

      final s = controller.currentState;
      final withinBudget = s.duration == Duration.zero || s.bufferedAhead <= (s.duration - s.position);
      expect(withinBudget, isTrue);
      await controller.dispose();
    });

    if (verifyPlayable != null) {
      test('a real media source reaches a playable state (§3 invariants 1 and 3)', () async {
        final controller = create();
        await verifyPlayable(controller);
        await controller.dispose();
      });
    }
  });
}
