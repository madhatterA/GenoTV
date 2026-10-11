import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

import 'package:playback/src/controller/seek_coalescer.dart';
import 'package:playback/src/controller/state_mapper.dart';
import 'package:playback/src/controller/buffering_model.dart' as buffering;
import 'package:playback/src/controller/media_kit_playback_controller.dart';

void main() {
  test('surface reports pending mode before it binds a player', () async {
    final surface = createVideoSurface();
    final mode = await surface.mode.first;
    expect(mode.kind, SurfaceModeKind.texture);
    expect(mode.reason, 'video output not initialized');
  });

  test('seek coalescer always issues the newest target', () async {
    final issued = <Duration>[];
    final gates = <Completer<void>>[];
    final coalescer = SeekCoalescer(
      issue: (target) async {
        issued.add(target);
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
      },
    );

    final first = coalescer.request(const Duration(seconds: 1));
    final second = coalescer.request(const Duration(seconds: 2));
    final third = coalescer.request(const Duration(seconds: 50));
    expect(issued, [const Duration(seconds: 1)]);
    gates.single.complete();
    await Future<void>.delayed(Duration.zero);
    expect(issued, [const Duration(seconds: 1), const Duration(seconds: 50)]);
    gates[1].complete();
    await Future.wait([first, second, third]);
  });

  test('seek coalescer collapses a 50-target scrub burst', () async {
    final issued = <Duration>[];
    final gate = Completer<void>();
    final coalescer = SeekCoalescer(
      issue: (target) async {
        issued.add(target);
        await gate.future;
      },
      epsilon: Duration.zero,
    );
    final futures = [
      for (var i = 0; i < 50; i++)
        coalescer.request(Duration(milliseconds: i * 100)),
    ];
    expect(issued, [Duration.zero]);
    gate.complete();
    await Future.wait(futures);
    expect(issued.last, const Duration(milliseconds: 4900));
    expect(issued.length, lessThan(50));
  });

  test('buffered duration is clamped to remaining duration', () {
    final state = PlaybackState.initial().copyWith(
      position: const Duration(seconds: 9),
      duration: const Duration(seconds: 10),
    );
    expect(
      applyBuffered(state, const Duration(seconds: 20)).bufferedAhead,
      const Duration(seconds: 1),
    );
    expect(
      applyBuffered(state, const Duration(seconds: -1)).bufferedAhead,
      Duration.zero,
    );
  });

  test('buffer is an absolute cache position, then clamped to the end', () {
    final state = PlaybackState.initial().copyWith(
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 30),
    );
    expect(
      applyBuffered(state, const Duration(seconds: 18)).bufferedAhead,
      const Duration(seconds: 8),
    );
    expect(
      applyBuffered(state, const Duration(seconds: 4)).bufferedAhead,
      Duration.zero,
    );
  });

  test('buffering debounce enters quickly and exits slowly', () async {
    final values = <bool>[];
    final debounce = buffering.BufferingDebouncer(
      onChanged: values.add,
      enterDelay: const Duration(milliseconds: 1),
      exitDelay: const Duration(milliseconds: 5),
    );
    debounce.update(engineBuffering: true, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(values, [true]);
    debounce.update(engineBuffering: false, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(values, [true]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(values, [true, false]);
    debounce.dispose();
  });

  test('public volume is mapped to media_kit percentage scale', () {
    expect(mapVolumeToEngine(0), 0);
    expect(mapVolumeToEngine(0.5), 50);
    expect(mapVolumeToEngine(1), 100);
    expect(mapVolumeToEngine(2), 100);
    expect(mapVolumeToEngine(-1), 0);
  });

  test('media resources decode local file paths but preserve network URIs', () {
    final local = Uri.parse('file:///tmp/video%20clip.mp4');
    expect(mediaKitResourceFor(local), '/tmp/video clip.mp4');

    const network = 'https://example.test/video%20clip.mp4?token=a%2Fb';
    expect(mediaKitResourceFor(Uri.parse(network)), network);
  });

  test('seek targets clamp to media bounds', () {
    const duration = Duration(seconds: 10);
    expect(
      clampSeekTarget(const Duration(seconds: -1), duration: duration),
      Duration.zero,
    );
    expect(
      clampSeekTarget(const Duration(seconds: 11), duration: duration),
      duration,
    );
    expect(
      clampSeekTarget(const Duration(seconds: 10), duration: duration),
      duration,
    );
  });

  test('state mapping keeps pause distinct from buffering and handles EOF', () {
    final paused = PlaybackState.initial();
    expect(applyBuffering(paused, true).isBuffering, isFalse);
    final playing = paused.copyWith(isPlaying: true);
    expect(applyBuffering(playing, true).isBuffering, isTrue);
    final ended = applyCompleted(playing, true);
    expect(ended.isCompleted, isTrue);
    expect(ended.isPlaying, isFalse);
    expect(applyCompleted(ended, false).isCompleted, isFalse);
  });

  test('every declared playback failure leaf is constructible', () {
    final failures = <PlaybackFailure>[
      PlaybackFailure.openFailed(cause: StateError('open')),
      PlaybackFailure.decodeFailed(cause: StateError('decode')),
      PlaybackFailure.engineCrashed(cause: StateError('engine')),
      PlaybackFailure.sourceUnreachable(cause: StateError('source')),
      PlaybackFailure.unsupportedCodec(codec: 'test'),
    ];
    expect(
      failures.map((failure) => failure.code),
      containsAll(<String>[
        'playback.open.failed',
        'playback.decode.failed',
        'playback.engine.crashed',
        'playback.source.unreachable',
        'playback.unsupported.codec',
      ]),
    );
  });
}
