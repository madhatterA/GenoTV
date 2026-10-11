import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
// The headless engine wiring is the same the other real-engine tests use.
// ignore: implementation_imports
import 'package:playback/src/controller/media_kit_playback_controller.dart';
// ignore: implementation_imports
import 'package:playback/src/surface/surface_output.dart';
import 'package:video_player/playback_insight.dart';
import 'package:video_player/player_settings.dart';

final _readback = <String>[];
final _diag = <String>[];

Future<SettingsValues> _with(Map<String, Object> writes) async {
  final values = SettingsValues(MemorySettingsStore());
  for (final e in writes.entries) {
    await values.write(settingById(e.key), e.value);
  }
  return values;
}

(MediaKitPlaybackController, mk.NativePlayer) _headless() {
  final player = mk.Player(
    configuration: const mk.PlayerConfiguration(vo: 'null'),
  );
  final controller = MediaKitPlaybackController(
    logger: MemoryLogger(),
    player: player,
    output: SurfaceOutput(
      attach: () async => throw UnsupportedError('headless'),
      texture: () async {},
      logger: MemoryLogger(),
      onError: (error, stack) => fail('Unexpected surface error: $error'),
    ),
  );
  return (controller, player.platform as mk.NativePlayer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File clip;

  setUpAll(() async {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError('PLAYBACK_LIBMPV must name the repo-built mpv library');
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
    dir = await Directory.systemTemp.createTemp('perf-settings-');
    clip = File('${dir.path}/clip.mp4');
    final result = await Process.run('ffmpeg', [
      '-v', 'error', '-f', 'lavfi', '-i', 'color=size=64x64:rate=24', //
      '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '2',
      '-c:v', 'mpeg4', '-c:a', 'aac', '-y', clip.path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  tearDownAll(() async {
    try {
      final out = dir;
      File('${out.path}/readback.md').writeAsStringSync(
        '# Performance read-back, real libmpv, 2 s generated clip\n\n'
        '| setting | choice | options sent | mpv property | read-back | result |\n'
        '| --- | --- | --- | --- | --- | --- |\n${_readback.join('\n')}\n',
      );
      File('${out.path}/diagnostics.md').writeAsStringSync(
        '# Diagnostics, real libmpv, 2 s generated clip (video + audio)\n\n'
        'Bitrates, buffered seconds and buffered bytes are throttled live '
        'values: compared within a tolerance, all other rows exactly.\n\n'
        '| field | mpv property | value shown | value read directly from mpv | result |\n'
        '| --- | --- | --- | --- | --- |\n${_diag.join('\n')}\n',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('mapping', () {
    final mode = settingById('performance.mode');
    final gpu = settingById('performance.gpuQuality');

    test('defaults write only the Auto network timeout', () async {
      final values = await _with({});
      expect(changedEngineSettings(values), {
        settingById('playback.networkTimeout'),
      });
      // mpv's own 5 s gives up before a direct file's first bytes arrive
      // through the local range server; Auto must reach mpv at open.
      expect(
        engineOptionsFor(values, scope: changedEngineSettings(values)),
        containsPair('network-timeout', '30'),
      );
    });

    test('mode picks the level, GPU quality wins over it', () async {
      final battery = await _with({'performance.mode': 'Battery saver'});
      final fast = engineOptionsFor(battery, scope: {mode});
      expect(fast['scale'], 'bilinear');
      expect(fast['deband'], 'no');
      expect(fast['interpolation'], 'no');
      final quality = await _with({'performance.mode': 'Quality'});
      expect(engineOptionsFor(quality, scope: {mode})['scale'], 'spline36');
      expect(engineOptionsFor(quality, scope: {mode})['deband'], 'yes');
      await quality.write(gpu, 'Fast');
      expect(engineOptionsFor(quality, scope: {gpu})['scale'], 'bilinear');
    });

    test('explicit settings are re-applied after the level', () async {
      final values = await _with({
        'performance.gpuQuality': 'Fast',
        'video.scalingQuality': 'High',
      });
      final options = engineOptionsFor(values, scope: {gpu});
      expect(options['scale'], 'ewa_lanczossharp');
      expect(options['deband'], 'no');
    });

    test('threads map to vd-lavc-threads', () async {
      final values = await _with({'performance.decoderThreads': 4.0});
      expect(
        engineOptionsFor(
          values,
          scope: {settingById('performance.decoderThreads')},
        ),
        {'vd-lavc-threads': '4'},
      );
    });
  });

  group('real mpv', () {
    test('mode, GPU quality and threads read back', () async {
      final (controller, backend) = _headless();
      Future<void> check(
        String setting,
        Object choice,
        Map<String, Object> writes,
        Map<String, String> expectedProps,
      ) async {
        final values = await _with(writes);
        final options = engineOptionsFor(
          values,
          scope: changedEngineSettings(values),
        );
        await controller.open(clip.uri, engineOptions: options);
        for (final e in expectedProps.entries) {
          final actual = await backend.getProperty(e.key);
          final ok = actual == e.value;
          _readback.add(
            '| $setting | $choice | $options | ${e.key} | $actual | '
            '${ok ? 'PASS' : 'FAIL'} |',
          );
          expect(actual, e.value, reason: '$setting=$choice ${e.key}');
        }
      }

      try {
        // The profile's effect: fast -> bilinear scaler, gpu-hq -> spline36.
        await check(
          'performance.mode',
          'Battery saver',
          {'performance.mode': 'Battery saver'},
          {'scale': 'bilinear', 'deband': 'no', 'dither': 'no'},
        );
        await check(
          'performance.mode',
          'Quality',
          {'performance.mode': 'Quality'},
          {'scale': 'spline36', 'deband': 'yes'},
        );
        await check(
          'performance.gpuQuality',
          'Fast',
          {'performance.gpuQuality': 'Fast'},
          {'scale': 'bilinear'},
        );
        await check(
          'performance.gpuQuality',
          'High',
          {'performance.gpuQuality': 'High'},
          {'scale': 'spline36'},
        );
        await check(
          'performance.gpuQuality',
          'Fast beats Quality mode',
          {'performance.gpuQuality': 'Fast', 'performance.mode': 'Quality'},
          {'scale': 'bilinear'},
        );
        await check(
          'explicit user value beats profile',
          'Fast + High scaling',
          {'performance.gpuQuality': 'Fast', 'video.scalingQuality': 'High'},
          {'scale': 'ewa_lanczossharp', 'deband': 'no'},
        );
        for (final n in [1.0, 4.0, 32.0]) {
          await check(
            'performance.decoderThreads',
            n,
            {'performance.decoderThreads': n},
            {'vd-lavc-threads': n.round().toString()},
          );
        }

        // Live (running engine): GPU quality changes as plain options.
        final values = await _with({'performance.gpuQuality': 'High'});
        await controller.open(clip.uri, engineOptions: {'vid': 'auto'});
        for (final (choice, scale) in [
          ('High', 'spline36'),
          ('Fast', 'bilinear'),
        ]) {
          await values.write(settingById('performance.gpuQuality'), choice);
          await controller.setEngineOptions(
            engineOptionsFor(
              values,
              scope: {settingById('performance.gpuQuality')},
            ),
          );
          final actual = await backend.getProperty('scale');
          _readback.add(
            '| performance.gpuQuality (live) | $choice | live options | '
            'scale | $actual | ${actual == scale ? 'PASS' : 'FAIL'} |',
          );
          expect(actual, scale);
        }
        // Back to Auto returns to the default profile.
        await values.write(settingById('performance.gpuQuality'), 'Auto');
        await controller.setEngineOptions(
          engineOptionsFor(
            values,
            scope: {settingById('performance.gpuQuality')},
          ),
        );
        final auto = await backend.getProperty('scale');
        _readback.add(
          '| performance.gpuQuality (live) | Auto | live options (Auto) | '
          'scale | $auto | ${auto == 'bilinear' || auto == 'spline36' ? 'PASS' : 'FAIL'} |',
        );
      } finally {
        await controller.dispose();
      }
    });

    test('custom options: valid applied, invalid reported, playback opens', () async {
      final (controller, backend) = _headless();
      try {
        await controller.open(clip.uri, engineOptions: {'vid': 'auto'});
        final parsed = parseCustomMpvOptions(
          '# comment\nsharpen=0.5\nno-such-option=1\n--brightness = 10',
        );
        final rejected = await controller.applyUserOptions(parsed.options);
        expect(rejected.keys, ['no-such-option']);
        expect(rejected['no-such-option'], contains('(-8)'));
        expect(double.parse(await backend.getProperty('sharpen')), 0.5);
        expect(double.parse(await backend.getProperty('brightness')), 10);
        expect(controller.currentState.failure, isNull);
        await controller.play();
        expect(await backend.getProperty('idle-active'), 'no');
        _readback.add(
          '| advanced.customMpvOptions | sharpen=0.5 | applyUserOptions | '
          'sharpen | ${await backend.getProperty('sharpen')} | PASS |',
        );
        _readback.add(
          '| advanced.customMpvOptions | no-such-option=1 | applyUserOptions | '
          '- | rejected: ${rejected['no-such-option']} | PASS |',
        );
      } finally {
        await controller.dispose();
      }
    });

    test('diagnostics equal what mpv reports', () async {
      final (controller, backend) = _headless();
      Map<String, String> latest = const {};
      final sub = controller.diagnostics.listen((m) => latest = m);
      try {
        await controller.open(clip.uri, engineOptions: {'vid': 'auto'});
        await controller.play();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await controller.pause();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(latest, isNotEmpty);
        for (final property
            in MediaKitPlaybackController.diagnosticProperties) {
          String direct;
          try {
            direct = await backend.getProperty(property);
          } catch (_) {
            direct = '';
          }
          final label = diagnosticLabels[property]!;
          final shownRaw = latest[property];
          if (shownRaw == null) {
            final ok = direct.isEmpty;
            _diag.add(
              '| $label | $property | omitted (engine reports none) | '
              '${direct.isEmpty ? 'unavailable' : direct} | '
              '${ok ? 'PASS' : 'FAIL'} |',
            );
            expect(direct, isEmpty, reason: property);
            continue;
          }
          // Throttled live values tick between the observer and our read,
          // so those are compared within a tolerance, the rest exactly.
          final ok = switch (property) {
            'demuxer-cache-duration' =>
              (double.parse(shownRaw) - double.parse(direct)).abs() <= 1.0,
            'video-bitrate' || 'audio-bitrate' =>
              (int.parse(shownRaw) - int.parse(direct)).abs() <=
                  int.parse(direct) * 0.25,
            'demuxer-cache-state' =>
              (jsonDecode(shownRaw)['fw-bytes'] as num) > 0 &&
                  (jsonDecode(direct)['fw-bytes'] as num) > 0,
            _ => shownRaw == direct,
          };
          _diag.add(
            '| $label | $property | ${shownDiagnostic(property, shownRaw)} | '
            '$direct | ${ok ? 'PASS' : 'FAIL'} |',
          );
          expect(
            ok,
            isTrue,
            reason: '$property shown=$shownRaw direct=$direct',
          );
        }
        expect(latest['video-codec'], isNotEmpty);
        expect(latest['audio-codec'], isNotEmpty);
        expect(diagnosticRows(latest)['Video codec'], latest['video-codec']);
      } finally {
        await sub.cancel();
        await controller.dispose();
      }
    });
  });
}
