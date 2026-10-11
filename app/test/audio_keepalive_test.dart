import 'dart:async';
import 'dart:io';

import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/playback.dart';
// Same injected headless surface as the existing real-engine tests.
// ignore: implementation_imports
import 'package:playback/src/controller/media_kit_playback_controller.dart';
// ignore: implementation_imports
import 'package:playback/src/surface/surface_output.dart';
import 'package:video_player/audio_device_keep_alive.dart';

class _Controller extends FakePlaybackController {
  final disposed = Completer<void>();
  int pauses = 0;

  @override
  Future<void> pause() async {
    pauses++;
    await super.pause();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    disposed.complete();
  }
}

class _RetentionController extends FakePlaybackController {
  bool disposed = false;

  @override
  Future<void> pause() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('retention expires after Kodi one-minute idle interval', (
    tester,
  ) async {
    final values = SettingsValues(MemorySettingsStore());
    await values.write(settingById('audio.deviceKeepAlive'), true);
    final pool = AudioDeviceKeepAlive(
      settings: values,
      create: (_) => _RetentionController(),
      hdrPolicy: () => HdrPolicy.auto,
      logger: MemoryLogger(),
    );
    try {
      final first = pool.acquire() as _RetentionController;
      await pool.release(first);
      await tester.pump(const Duration(seconds: 59));
      expect(first.disposed, isFalse);
      expect(pool.acquire(), same(first));
      await pool.release(first);
      await tester.pump(const Duration(seconds: 59));
      expect(first.disposed, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(first.disposed, isTrue);
      final second = pool.acquire() as _RetentionController;
      expect(second, isNot(same(first)));
      await pool.release(second);
    } finally {
      unawaited(pool.dispose());
      values.dispose();
      await tester.pump();
    }
  });

  testWidgets('unfocused app has zero idle retention interval', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final values = SettingsValues(MemorySettingsStore());
    await values.write(settingById('audio.deviceKeepAlive'), true);
    final pool = AudioDeviceKeepAlive(
      settings: values,
      create: (_) => _RetentionController(),
      hdrPolicy: () => HdrPolicy.auto,
      logger: MemoryLogger(),
    );
    try {
      final first = pool.acquire() as _RetentionController;
      await pool.release(first);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(first.disposed, isTrue);
      final second = pool.acquire() as _RetentionController;
      await pool.release(second);
      expect(second.disposed, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final third = pool.acquire() as _RetentionController;
      await pool.release(third);
      expect(third.disposed, isFalse);
    } finally {
      unawaited(pool.dispose());
      values.dispose();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  test(
    'off disposes; on pauses/reuses; setting off releases retained engine',
    () async {
      final values = SettingsValues(MemorySettingsStore());
      await values.write(settingById('audio.deviceKeepAlive'), false);
      final pool = AudioDeviceKeepAlive(
        settings: values,
        create: (_) => _Controller(),
        hdrPolicy: () => HdrPolicy.auto,
        logger: MemoryLogger(),
      );
      final first = pool.acquire() as _Controller;
      await pool.release(first);
      expect(first.disposed.isCompleted, isTrue);
      await values.write(settingById('audio.deviceKeepAlive'), true);
      final second = pool.acquire() as _Controller;
      await pool.release(second);
      expect(second.pauses, 1);
      expect(second.disposed.isCompleted, isFalse);
      expect(pool.acquire(), same(second));
      await pool.release(second);
      await values.write(settingById('audio.deviceKeepAlive'), false);
      await second.disposed.future;
      await pool.dispose();
      values.dispose();
    },
  );

  test(
    'HDR policy change cannot reuse an incompatible surface; shutdown releases',
    () async {
      final values = SettingsValues(MemorySettingsStore());
      await values.write(settingById('audio.deviceKeepAlive'), true);
      var policy = HdrPolicy.auto;
      final pool = AudioDeviceKeepAlive(
        settings: values,
        create: (_) => _Controller(),
        hdrPolicy: () => policy,
        logger: MemoryLogger(),
      );
      final first = pool.acquire() as _Controller;
      await pool.release(first);
      policy = HdrPolicy.forceSdr;
      await values.write(settingById('video.hdr'), 'Force SDR');
      await first.disposed.future;
      final second = pool.acquire() as _Controller;
      expect(second, isNot(same(first)));
      await pool.release(second);
      await pool.dispose();
      expect(second.disposed.isCompleted, isTrue);
      values.dispose();
    },
  );

  test(
    'two 2s clips reuse real libmpv and keep CoreAudio open while paused',
    () async {
      final path = Platform.environment['PLAYBACK_LIBMPV'];
      if (path == null || !File(path).existsSync()) {
        throw StateError(
          'PLAYBACK_LIBMPV must name the repo-built mpv library',
        );
      }
      mk.MediaKit.ensureInitialized(libmpv: path);
      final dir = await Directory.systemTemp.createTemp('audio-keepalive-');
      final clip = File('${dir.path}/clip.wav');
      final result = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=48000',
        '-t',
        '2',
        '-y',
        clip.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final values = SettingsValues(MemorySettingsStore());
      await values.write(settingById('audio.deviceKeepAlive'), true);
      late mk.NativePlayer backend;
      final pool = AudioDeviceKeepAlive(
        settings: values,
        hdrPolicy: () => HdrPolicy.auto,
        logger: MemoryLogger(),
        create: (policy) {
          final player = mk.Player(
            configuration: const mk.PlayerConfiguration(vo: 'null'),
          );
          backend = player.platform as mk.NativePlayer;
          return MediaKitPlaybackController(
            logger: MemoryLogger(),
            player: player,
            hdrPolicy: policy,
            output: SurfaceOutput(
              attach: () async => throw UnsupportedError('headless'),
              texture: () async {},
              logger: MemoryLogger(),
              onError: (error, stack) =>
                  fail('Unexpected surface error: $error'),
            ),
          );
        },
      );
      try {
        final first = pool.acquire();
        final handle = await backend.handle;
        final opened = first.events.firstWhere((event) => event is MediaOpened);
        await first.open(
          clip.uri,
          engineOptions: {
            'ao': 'coreaudio',
            'gapless-audio': 'yes',
            'audio-stream-silence': 'yes',
            'keep-open': 'yes',
          },
        );
        await opened;
        expect(await backend.getProperty('current-ao'), 'coreaudio');
        await first.play();
        expect(await backend.getProperty('pause'), 'no');
        await pool.release(first);
        expect(await backend.getProperty('pause'), 'yes');
        expect(await backend.getProperty('current-ao'), 'coreaudio');
        final second = pool.acquire();
        expect(second, same(first));
        expect(await backend.handle, handle);
        final reopened = second.events.firstWhere(
          (event) => event is MediaOpened,
        );
        await second.open(clip.uri);
        await reopened;
        expect(await backend.getProperty('current-ao'), 'coreaudio');
        await pool.release(second);
      } finally {
        await pool.dispose();
        values.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
