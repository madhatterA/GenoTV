import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/src/controller/media_kit_playback_controller.dart';

import 'package:playback/src/surface/surface_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
  });

  test(
    'six live setters change real mpv properties on a two-second clip',
    () async {
      final directory = await Directory.systemTemp.createTemp('live-options-');
      final clip = File('${directory.path}/clip.mp4');
      final generated = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=size=64x64:rate=24',
        '-t',
        '2',
        '-c:v',
        'mpeg4',
        '-y',
        clip.path,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());
      final player = mk.Player(
        configuration: const mk.PlayerConfiguration(vo: 'null'),
      );
      final controller = MediaKitPlaybackController(
        logger: MemoryLogger(),
        player: player,
        // Only renderer setup is doubled; engine and open/readback remain real.
        output: SurfaceOutput(
          attach: () async => throw UnsupportedError('headless property test'),
          texture: () async {},
          logger: MemoryLogger(),
          onError: (error, stack) => fail('Unexpected surface error: $error'),
        ),
      );
      final backend = player.platform as mk.NativePlayer;
      try {
        await player.open(mk.Media(clip.path), play: false);
        final duration = player.state.duration > Duration.zero
            ? player.state.duration
            : await player.stream.duration
                  .firstWhere((value) => value > Duration.zero)
                  .timeout(const Duration(seconds: 2));
        expect(
          duration.inMicroseconds / Duration.microsecondsPerSecond,
          closeTo(2, 0.05),
        );
        Future<void> property(String name, double expected) async {
          expect(
            double.parse(await backend.getProperty(name)),
            closeTo(expected, 0.00001),
          );
        }

        for (final delay in [-10000, -100, 100, 10000, 0]) {
          await controller.setSubtitleDelay(Duration(milliseconds: delay));
          await property('sub-delay', delay / 1000);
        }
        for (final delay in [-5000, -50, 50, 5000, 0]) {
          await controller.setAudioDelay(Duration(milliseconds: delay));
          await property('audio-delay', delay / 1000);
        }
        for (final scale in [0.75, 1.0, 1.25, 1.5]) {
          await controller.setSubtitleScale(scale);
          await property('sub-scale', scale);
        }
        for (final percent in [0, 85, 100]) {
          await controller.setSubtitlePosition(percent);
          await property('sub-pos', percent.toDouble());
        }
        for (final entry in <String, double>{
          '16:9': 16 / 9,
          '4:3': 4 / 3,
          '21:9': 21 / 9,
          '2.39:1': 2.39,
        }.entries) {
          await controller.setAspectRatio(entry.key);
          await property('video-aspect-override', entry.value);
        }
        await controller.setAspectRatio(null);
        await property('video-aspect-override', -1);
        await controller.setFillScreen(true);
        await property('panscan', 1);
        await controller.setFillScreen(false);
        await property('panscan', 0);
        await Future.wait([
          controller.setSubtitleDelay(const Duration(milliseconds: 100)),
          controller.setSubtitleDelay(const Duration(milliseconds: 200)),
          controller.setSubtitleDelay(Duration.zero),
        ]);
        await property('sub-delay', 0);
        expect(controller.currentState.failure, isNull);
        await controller.setSubtitleDelay(const Duration(milliseconds: 500));
        await controller.setAudioDelay(const Duration(milliseconds: -250));
        await controller.setSubtitleScale(1.5);
        await controller.setSubtitlePosition(85);
        await controller.setAspectRatio('4:3');
        await controller.setFillScreen(true);
        await controller.open(clip.uri);
        for (final entry in <String, double>{
          'sub-delay': 0,
          'audio-delay': 0,
          'sub-scale': 1,
          'sub-pos': 100,
          'video-aspect-override': -1,
          'panscan': 0,
        }.entries) {
          await property(entry.key, entry.value);
        }
        expect(controller.currentState.failure, isNull);
      } finally {
        await controller.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('setAudioOutput applies a plan to real mpv and reads it back', () async {
    final directory = await Directory.systemTemp.createTemp('audio-output-');
    final clip = File('${directory.path}/clip.mkv');
    final generated = await Process.run('ffmpeg', [
      '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
      '-c:a', 'ac3', '-y', clip.path, //
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
    );
    final backend = player.platform as mk.NativePlayer;
    try {
      await player.open(mk.Media(clip.path), play: false);
      for (final (spdif, channels) in [
        ('ac3,dts', 'auto-safe'),
        ('', 'stereo'),
        ('ac3', 'auto'),
      ]) {
        await controller.setAudioOutput(
          AudioPlan(
            step: AudioPlanStep.bitstream,
            outputCodec: 'ac3',
            channels: 2,
            audioSpdif: spdif,
            audioChannels: channels,
          ),
        );
        expect(await backend.getProperty('audio-spdif'), spdif);
        expect(await backend.getProperty('audio-channels'), channels);
        expect(await backend.getProperty('af'), '');
      }
      expect(controller.currentState.failure, isNull);
      await expectLater(
        controller.setAudioOutput(
          AudioPlan(
            step: AudioPlanStep.stereo,
            outputCodec: 'pcm',
            channels: 2,
            audioSpdif: '',
            audioChannels: 'not-a-layout',
          ),
        ),
        throwsStateError,
      );
      expect(controller.currentState.failure?.code, 'playback.engine.crashed');
    } finally {
      await controller.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'invalid live options are rejected and disposal prevents all setters',
    () async {
      final controller = MediaKitPlaybackController(logger: MemoryLogger());
      for (final call in <Future<void> Function()>[
        () => controller.setSubtitleDelay(const Duration(milliseconds: -10001)),
        () => controller.setSubtitleDelay(const Duration(milliseconds: 10001)),
        () => controller.setAudioDelay(const Duration(milliseconds: -5001)),
        () => controller.setAudioDelay(const Duration(milliseconds: 5001)),
        () => controller.setSubtitleScale(double.nan),
        () => controller.setSubtitleScale(double.infinity),
        () => controller.setSubtitleScale(0),
        () => controller.setSubtitleScale(-1),
        () => controller.setSubtitleScale(101),
        () => controller.setSubtitlePosition(-1),
        () => controller.setSubtitlePosition(101),
        () => controller.setAspectRatio('not-a-ratio'),
        () => controller.setAspectRatio('1:0'),
      ]) {
        expect(call, throwsArgumentError);
      }
      expect(controller.currentState.failure, isNull);
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

  test('engine option failure surfaces in state and events', () async {
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
    );
    final failure = controller.events.first;
    await player.dispose();
    await expectLater(
      controller.setFillScreen(true),
      throwsA(isA<AssertionError>()),
    );
    expect(controller.currentState.failure?.code, 'playback.engine.crashed');
    expect(await failure, isA<PlaybackFailed>());
    await controller.dispose();
  });
}
