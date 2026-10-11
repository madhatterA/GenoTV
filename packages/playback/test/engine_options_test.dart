// Inject native events to test error/frame ordering without a runtime test seam.
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/playback.dart';
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/surface/surface_output.dart';

late Directory _dir;
late File _clip;

Future<File> _generate(String name, List<String> args) async {
  final file = File('${_dir.path}/$name');
  final result = await Process.run('ffmpeg', [
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=size=64x64:rate=24',
    '-t',
    '2',
    ...args,
    '-y',
    file.path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return file;
}

/// A controller on a real libmpv, headless: only renderer setup is doubled.
(MediaKitPlaybackController, mk.NativePlayer) _headless() {
  final player = mk.Player(
    configuration: const mk.PlayerConfiguration(vo: 'null'),
  );
  final controller = MediaKitPlaybackController(
    logger: MemoryLogger(),
    player: player,
    output: SurfaceOutput(
      attach: () async => throw UnsupportedError('headless property test'),
      texture: () async {},
      logger: MemoryLogger(),
      onError: (error, stack) => fail('Unexpected surface error: $error'),
    ),
  );
  return (controller, player.platform as mk.NativePlayer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
    _dir = await Directory.systemTemp.createTemp('engine-options-');
    _clip = await _generate('clip.mp4', ['-c:v', 'mpeg4']);
  });

  test('open applies engine options before load and keeps them', () async {
    final (controller, backend) = _headless();
    try {
      await controller.open(
        _clip.uri,
        engineOptions: {
          'speed': '1.5',
          'audio-delay': '0.25',
          'panscan': '1.0',
          'video-sync': 'display-resample',
        },
      );
      expect(double.parse(await backend.getProperty('speed')), 1.5);
      expect(double.parse(await backend.getProperty('audio-delay')), 0.25);
      expect(double.parse(await backend.getProperty('panscan')), 1);
      expect(await backend.getProperty('video-sync'), 'display-resample');
      expect(controller.currentState.failure, isNull);
    } finally {
      await controller.dispose();
    }
  });

  test('without engine options open leaves the per-video defaults', () async {
    final (controller, backend) = _headless();
    try {
      await controller.open(_clip.uri);
      expect(double.parse(await backend.getProperty('speed')), 1);
      expect(double.parse(await backend.getProperty('audio-delay')), 0);
      expect(double.parse(await backend.getProperty('panscan')), 0);
    } finally {
      await controller.dispose();
    }
  });

  test('setEngineOptions changes properties while open, no reopen', () async {
    final (controller, backend) = _headless();
    try {
      await controller.open(_clip.uri);
      await controller.setEngineOptions({'speed': '2.0', 'deband': 'yes'});
      expect(double.parse(await backend.getProperty('speed')), 2);
      expect(await backend.getProperty('deband'), 'yes');
      await controller.setEngineOptions({'speed': '1.0', 'deband': 'no'});
      expect(double.parse(await backend.getProperty('speed')), 1);
      expect(await backend.getProperty('deband'), 'no');
      expect(controller.currentState.failure, isNull);
    } finally {
      await controller.dispose();
    }
  });

  test('a value mpv rejects fails loudly and changes nothing', () async {
    final (controller, backend) = _headless();
    try {
      await controller.open(_clip.uri);
      await expectLater(
        controller.setEngineOptions({'speed': 'not-a-number'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('mpv rejected speed=not-a-number'),
          ),
        ),
      );
      expect(controller.currentState.failure, isA<PlaybackFailure>());
      expect(double.parse(await backend.getProperty('speed')), 1);
      await expectLater(
        controller.setEngineOptions({'no-such-property': '1'}),
        throwsA(isA<StateError>()),
      );
    } finally {
      await controller.dispose();
    }
  });

  test('an option mpv rejects at open fails the open', () async {
    final (controller, _) = _headless();
    try {
      await expectLater(
        controller.open(_clip.uri, engineOptions: {'speed': 'fast'}),
        throwsA(isA<StateError>()),
      );
      expect(controller.currentState.failure, isA<PlaybackFailure>());
    } finally {
      await controller.dispose();
    }
  });

  test('open retains a terminal decoder error delivered during preparation', () async {
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    final backend = player.platform as mk.NativePlayer;
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless property test'),
        texture: () async {
          backend.errorController.add(
            "Failed to initialize a decoder for codec 'truehd'.",
          );
          await Future<void>.delayed(Duration.zero);
        },
        logger: MemoryLogger(),
        onError: (error, stack) => fail('Unexpected surface error: $error'),
      ),
    );
    try {
      await controller.open(_clip.uri);
      expect(controller.currentState.failure.toString(), contains('truehd'));
      // The retained controller must start the next open without that failure.
      await controller.open(_clip.uri);
      expect(controller.currentState.failure, isNull);
    } finally {
      await controller.dispose();
    }
  });

  group('video decoder recovery', () {
    late MediaKitPlaybackController controller;
    late mk.NativePlayer backend;
    setUp(() {
      (controller, backend) = _headless();
    });
    tearDown(() => controller.dispose());

    void codecError(String prefix) {
      backend.logController.add(
        mk.PlayerLog(
          prefix: prefix,
          level: 'error',
          text: 'Could not open codec.',
        ),
      );
      backend.errorController.add('Could not open codec.');
    }

    test(
      'a rejected video decoder waits for a decoded fallback frame',
      () async {
        final failures = <PlaybackFailure>[];
        final states = controller.state.listen((state) {
          if (state.failure case final failure?) failures.add(failure);
        });
        addTearDown(states.cancel);
        codecError('vd');
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentState.failure, isNull);
        backend.videoParamsController.add(
          const mk.VideoParams(pixelformat: 'yuv420p', w: 64, h: 64),
        );
        await Future<void>.delayed(Duration.zero);
        backend.completedController.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(failures, isEmpty);
      },
    );

    test(
      'decoded parameters before the error callback still confirm recovery',
      () async {
        backend.logController.add(
          mk.PlayerLog(
            prefix: 'vd',
            level: 'error',
            text: 'Could not open codec.',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        backend.videoParamsController.add(
          const mk.VideoParams(pixelformat: 'yuv420p', w: 64, h: 64),
        );
        await Future<void>.delayed(Duration.zero);
        backend.errorController.add('Could not open codec.');
        await Future<void>.delayed(Duration.zero);
        backend.completedController.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentState.failure, isNull);
      },
    );

    test('completion before the error callback emits one failure', () async {
      final failures = <PlaybackFailure>[];
      final states = controller.state.listen((state) {
        if (state.failure case final failure?) failures.add(failure);
      });
      addTearDown(states.cancel);
      backend.logController.add(
        mk.PlayerLog(
          prefix: 'vd',
          level: 'error',
          text: 'Could not open codec.',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      backend.completedController.add(true);
      await Future<void>.delayed(Duration.zero);
      final count = failures.length;
      expect(count, greaterThan(0));
      backend.errorController.add('Could not open codec.');
      await Future<void>.delayed(Duration.zero);
      expect(failures.length, count);
      expect(controller.currentState.failure, isA<PlaybackFailure>());
    });

    test(
      'interleaved identical audio and video messages preserve audio failure',
      () async {
        codecError('vd');
        codecError('ad');
        backend.videoParamsController.add(
          const mk.VideoParams(pixelformat: 'yuv420p', w: 64, h: 64),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentState.failure, isA<PlaybackFailure>());
      },
    );

    test('terminal failure survives later video parameters', () async {
      codecError('vd');
      backend.errorController.add(
        "Failed to initialize a decoder for codec 'h264'.",
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentState.failure, isA<PlaybackFailure>());
      backend.videoParamsController.add(
        const mk.VideoParams(pixelformat: 'yuv420p', w: 64, h: 64),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentState.failure, isA<PlaybackFailure>());
    });

    test('completion without a decoded fallback frame fails', () async {
      codecError('vd');
      await Future<void>.delayed(Duration.zero);
      backend.videoParamsController.add(const mk.VideoParams());
      backend.completedController.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentState.failure, isA<PlaybackFailure>());
    });

    test(
      'same initialization message from an audio decoder still fails',
      () async {
        codecError('ad');
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentState.failure, isA<PlaybackFailure>());
      },
    );

    test('ordinary source failures remain immediate', () async {
      backend.errorController.add(
        'Failed to open https://example.test/clip.mp4',
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentState.failure, isA<PlaybackFailure>());
    });
  });

  group('HDR policy', () {
    test('only auto and passthrough report an HDR transfer as HDR', () {
      for (final gamma in ['pq', 'hlg']) {
        expect(HdrPolicy.auto.reportsHdr(gamma), isTrue);
        expect(HdrPolicy.passthrough.reportsHdr(gamma), isTrue);
        expect(HdrPolicy.forceSdr.reportsHdr(gamma), isFalse);
      }
      for (final policy in HdrPolicy.values) {
        expect(policy.reportsHdr('bt.1886'), isFalse);
        expect(policy.reportsHdr(null), isFalse);
      }
    });

    // Headless mpv exposes no decoded video params, so the decoded source's
    // report is covered by the table above; this proves the controller feeds
    // its policy into the native surface it creates.
    test('the controller creates its native surface from the policy', () async {
      final reports = <bool>[];
      final reported = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('video_surface'), (
        call,
      ) async {
        switch (call.method) {
          case 'create':
            return {'id': 1, 'headroom': 2.0};
          case 'source':
            reports.add((call.arguments as Map)['hdr'] as bool);
            if (!reported.isCompleted) reported.complete();
        }
        return null;
      });
      final controller = MediaKitPlaybackController(
        logger: MemoryLogger(),
        hdrPolicy: HdrPolicy.forceSdr,
        player: mk.Player(
          configuration: const mk.PlayerConfiguration(vo: 'null'),
        ),
      );
      try {
        await controller.open(_clip.uri);
        await reported.future;
        expect(reports, everyElement(isFalse));
      } finally {
        await controller.dispose();
        messenger.setMockMethodCallHandler(
          const MethodChannel('video_surface'),
          null,
        );
      }
    });
  });
}
