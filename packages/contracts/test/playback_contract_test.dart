import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compiling this function is the test: a `switch` over every [PlaybackEvent]
/// subtype with no default arm only compiles if the sealed hierarchy is
/// exhaustive and every subtype is reachable from outside the package.
String describe(PlaybackEvent event) => switch (event) {
  SeekRequested(:final to) => 'seek requested to $to',
  SeekCompleted(:final at) => 'seek completed at $at',
  MediaOpened(:final duration) => 'opened, duration $duration',
  PlaybackEnded() => 'ended',
  PlaybackFailed(:final failure) => 'failed: ${failure.code}',
};

void main() {
  test(
    'live option setters record values in order and reject use after dispose',
    () async {
      final fake = FakePlaybackController();
      final PlaybackController controller = fake;
      await controller.setSubtitleDelay(const Duration(milliseconds: -100));
      await controller.setSubtitleDelay(Duration.zero);
      await controller.setAudioDelay(const Duration(milliseconds: 50));
      await controller.setAudioDelay(Duration.zero);
      await controller.setSubtitleScale(1.5);
      await controller.setSubtitlePosition(85);
      await controller.setAspectRatio('16:9');
      await controller.setAspectRatio(null);
      await controller.setFillScreen(true);
      await controller.setFillScreen(false);
      final plan = AudioPlan(
        step: AudioPlanStep.bitstream,
        outputCodec: 'ac3',
        channels: 6,
        audioSpdif: 'ac3',
        audioChannels: 'auto-safe',
      );
      await controller.setAudioOutput(plan);
      expect(fake.recordedAudioOutput, [plan]);
      expect(fake.recordedSubtitleDelays, [
        const Duration(milliseconds: -100),
        Duration.zero,
      ]);
      expect(fake.recordedAudioDelays, [
        const Duration(milliseconds: 50),
        Duration.zero,
      ]);
      expect(fake.recordedSubtitleScales, [1.5]);
      expect(fake.recordedSubtitlePositions, [85]);
      expect(fake.recordedAspectRatios, ['16:9', null]);
      expect(fake.recordedFillScreen, [true, false]);
      await controller.dispose();
      for (final call in <Future<void> Function()>[
        () => controller.setSubtitleDelay(Duration.zero),
        () => controller.setAudioDelay(Duration.zero),
        () => controller.setSubtitleScale(1),
        () => controller.setSubtitlePosition(100),
        () => controller.setAspectRatio(null),
        () => controller.setFillScreen(false),
        () => controller.setAudioOutput(
          AudioPlan(
            step: AudioPlanStep.stereo,
            outputCodec: 'pcm',
            channels: 2,
            audioSpdif: '',
            audioChannels: 'stereo',
          ),
        ),
      ]) {
        await expectLater(call(), throwsStateError);
      }
    },
  );

  test(
    'mediaInfo is broadcast, delivers emitted facts, closes on dispose',
    () async {
      final fake = FakePlaybackController();
      final first = <MediaInfo>[];
      final second = <MediaInfo>[];
      fake.mediaInfo.listen(first.add);
      fake.mediaInfo.listen(second.add);
      const info = MediaInfo(videoCodec: 'h264', width: 64, height: 64);
      fake.emitMediaInfo(info);
      await Future<void>.delayed(Duration.zero);
      expect(first, [info]);
      expect(second, [info]);
      expect(info.audioCodec, isNull);
      await fake.dispose();
      expect(await fake.mediaInfo.isEmpty, isTrue);
    },
  );

  test('surface modes carry the output kind and diagnostic reason', () {
    const modes = <SurfaceMode>[
      SurfaceMode(SurfaceModeKind.hdrNative, 'HDR source on HDR display'),
      SurfaceMode(SurfaceModeKind.sdrNative, 'SDR source on native surface'),
      SurfaceMode(SurfaceModeKind.texture, 'HDR output unavailable'),
    ];
    expect(modes.map((mode) => mode.kind), SurfaceModeKind.values);
    expect(modes.map((mode) => mode.reason), [
      'HDR source on HDR display',
      'SDR source on native surface',
      'HDR output unavailable',
    ]);
  });

  test('fake surface reports texture mode to each observer', () async {
    const VideoSurface surface = FakeVideoSurface();
    for (var observer = 0; observer < 2; observer++) {
      final mode = await surface.mode.first;
      expect(mode.kind, SurfaceModeKind.texture);
      expect(mode.reason, 'Fake video surface (no native rendering)');
    }
  });

  group('PlaybackState.initial', () {
    test('is a valid zero state', () {
      final state = PlaybackState.initial();

      expect(state.position, Duration.zero);
      expect(state.duration, Duration.zero);
      expect(state.bufferedAhead, Duration.zero);
      expect(state.isPlaying, isFalse);
      expect(state.isBuffering, isFalse);
      expect(state.isCompleted, isFalse);
      expect(state.rate, 1.0);
      expect(state.tracks.video, isEmpty);
      expect(state.selected.subtitle, const TrackChoice.off());
      expect(state.chapters, isEmpty);
      expect(state.failure, isNull);
    });
  });

  group('PlaybackState.copyWith', () {
    test('preserves untouched fields', () {
      final original = PlaybackState.initial().copyWith(
        position: const Duration(seconds: 10),
        rate: 1.5,
      );

      final updated = original.copyWith(isPlaying: true);

      expect(updated.position, const Duration(seconds: 10));
      expect(updated.rate, 1.5);
      expect(updated.isPlaying, isTrue);
    });
  });

  group('TrackChoice', () {
    test('off is distinguishable from auto (not yet chosen)', () {
      const off = TrackChoice.off();
      const auto = TrackChoice.auto();

      expect(off, isNot(auto));
      expect(off.mode, TrackSelectionMode.off);
      expect(auto.mode, TrackSelectionMode.auto);
      expect(off.id, isNull);
      expect(auto.id, isNull);
    });

    test('specific carries the chosen track id', () {
      const choice = TrackChoice.specific('sub-2');
      expect(choice.mode, TrackSelectionMode.specific);
      expect(choice.id, 'sub-2');
    });
  });

  group('PlaybackEvent', () {
    test('every subtype is reachable via an exhaustive switch', () {
      expect(
        describe(const SeekRequested(Duration(seconds: 1))),
        contains('seek requested'),
      );
      expect(
        describe(const SeekCompleted(Duration(seconds: 1))),
        contains('seek completed'),
      );
      expect(
        describe(
          const MediaOpened(
            duration: Duration(minutes: 90),
            tracks: TrackList(),
          ),
        ),
        contains('opened'),
      );
      expect(describe(const PlaybackEnded()), 'ended');
      expect(
        describe(
          PlaybackFailed(
            PlaybackFailure.engineCrashed(cause: Exception('boom')),
          ),
        ),
        contains('playback.engine.crashed'),
      );
    });
  });

  group('PlaybackFailure', () {
    test('track selection failure has a stable typed code', () {
      final failure = PlaybackFailure.trackSelectionFailed(
        trackId: 'audio-2',
        cause: StateError('rejected'),
      );

      expect(failure.code, 'playback.track.selection_failed');
      expect(failure.cause, isA<StateError>());
    });

    test('subtitle load failure includes the URI and cause', () {
      final uri = Uri.parse('file:///tmp/missing.srt');
      final failure = PlaybackFailure.subtitleLoadFailed(
        uri: uri,
        cause: StateError('missing'),
      );

      expect(failure.code, 'playback.subtitle.load_failed');
      expect(failure.message, contains(uri.toString()));
      expect(failure.cause, isA<StateError>());
    });
  });
}
