import 'dart:async';
import 'dart:io';

import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:platform_services/platform_services.dart';
import 'package:playback/playback.dart';
// The headless engine wiring below is the same the playback package's own
// real-engine tests use.
// ignore: implementation_imports
import 'package:playback/src/controller/media_kit_playback_controller.dart';
// ignore: implementation_imports
import 'package:playback/src/surface/surface_output.dart';
import 'package:video_player/platform_policy.dart';
import 'package:video_player/player_settings.dart';
import 'package:video_player/playback_session.dart';

/// One non-default value of a setting and the mpv properties it must write.
typedef _Case = ({String id, Object value, Map<String, String> expected});

const List<_Case> _cases = [
  (id: 'playback.speed', value: 1.5, expected: {'speed': '1.5'}),
  (
    id: 'playback.syncToDisplay',
    value: true,
    expected: {'video-sync': 'display-resample'},
  ),
  (
    id: 'playback.avSyncCorrection',
    value: 0.5,
    expected: {'audio-delay': '0.5'},
  ),
  (
    id: 'playback.cachePreset',
    value: 'Low latency',
    expected: {
      'cache-secs': '10',
      'demuxer-max-bytes': '8388608',
      'demuxer-readahead-secs': '1',
    },
  ),
  (
    id: 'playback.demuxerCacheSize',
    value: 64.0,
    expected: {'demuxer-max-bytes': '67108864'},
  ),
  (
    id: 'streaming.bufferSize',
    value: 64.0,
    expected: {'demuxer-max-bytes': '67108864'},
  ),
  (
    id: 'streaming.prebuffer',
    value: 10.0,
    expected: {'cache-pause-wait': '10.0'},
  ),
  (
    id: 'playback.readAhead',
    value: 20.0,
    expected: {'demuxer-readahead-secs': '20.0'},
  ),
  (
    id: 'playback.networkTimeout',
    value: 30.0,
    expected: {'network-timeout': '30.0'},
  ),
  (id: 'video.hwdec', value: 'On', expected: {'hwdec': 'auto'}),
  (id: 'video.decoder', value: 'hardware', expected: {'hwdec': 'auto'}),
  (
    id: 'video.aspectRatio',
    value: 'Fill',
    expected: {'keepaspect': 'yes', 'panscan': '1.0'},
  ),
  (
    id: 'video.scalingQuality',
    value: 'High',
    expected: {
      'scale': 'ewa_lanczossharp',
      'cscale': 'ewa_lanczossharp',
      'dscale': 'mitchell',
    },
  ),
  (
    id: 'video.toneMapping',
    value: 'bt.2390',
    expected: {'tone-mapping': 'bt.2390'},
  ),
  (id: 'video.pixelFormat', value: 'nv12', expected: {'vf': 'format=nv12'}),
  (id: 'video.chroma', value: '4:2:2', expected: {'vf': 'format=yuv422p'}),
  (id: 'video.bitDepth', value: '10', expected: {'dither-depth': '10'}),
  (id: 'video.dithering', value: 'fruit', expected: {'dither': 'fruit'}),
  (id: 'video.interpolation', value: true, expected: {'interpolation': 'yes'}),
  (id: 'video.debanding', value: true, expected: {'deband': 'yes'}),
  (id: 'video.gpuRendering', value: 'opengl', expected: {'gpu-api': 'opengl'}),
  (
    id: 'display.calibration',
    value: '0.5,0.1,-0.1',
    expected: {
      'video-zoom': '0.5',
      'video-pan-x': '0.1',
      'video-pan-y': '-0.1',
    },
  ),
];

final _rows = <String>[];

/// Performance settings have their own read-back test.
final _p01Defs = engineSettingDefs.where((d) => !d.id.startsWith('performance.'));

/// mpv prints a video filter in its canonical form (`format=fmt=nv12`).
String _canonical(String value) => value.replaceAll('fmt=', '');

bool _same(String expected, String actual) {
  expected = _canonical(expected);
  actual = _canonical(actual);
  final e = double.tryParse(expected);
  final a = double.tryParse(actual);
  return e != null && a != null ? (e - a).abs() < 0.00001 : expected == actual;
}

SettingsValues _values() => SettingsValues(MemorySettingsStore());

Future<SettingsValues> _with(String id, Object value) async {
  final values = _values();
  await values.write(settingById(id), value);
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

final _timeout = settingById('playback.networkTimeout');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File clip;

  setUpAll(() async {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
    dir = await Directory.systemTemp.createTemp('player-settings-');
    clip = File('${dir.path}/clip.mp4');
    final result = await Process.run('ffmpeg', [
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
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  tearDownAll(() async {
    try {
      final out = File('${dir.path}/readback.md');
      await out.writeAsString(
        '# Read-back, real libmpv, 2 s generated clip\n\n'
        '| def id | value | property | expected | read-back | result |\n'
        '| --- | --- | --- | --- | --- | --- |\n${_rows.join('\n')}\n',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('mapping', () {
    test('every engine setting has a case below', () {
      expect(
        {for (final c in _cases) c.id},
        {for (final d in _p01Defs) d.id},
      );
    });

    for (final c in _cases) {
      test('${c.id} = ${c.value}', () async {
        final def = settingById(c.id);
        final values = await _with(c.id, c.value);
        expect(changedEngineSettings(values), {def, _timeout});
        expect(engineOptionsFor(values, scope: {def}), c.expected);
      });
    }

    test('defaults change only the Auto network timeout at open', () {
      expect(changedEngineSettings(_values()), {_timeout});
      expect(engineOptionsFor(_values(), scope: const {}), isEmpty);
    });

    test('the Advanced decoder choice overrides hardware decoding', () async {
      final values = await _with('video.hwdec', 'Off');
      expect(engineOptionsFor(values, scope: {settingById('video.hwdec')}), {
        'hwdec': 'no',
      });
      await values.write(settingById('video.decoder'), 'hardware');
      expect(engineOptionsFor(values, scope: {settingById('video.hwdec')}), {
        'hwdec': 'auto',
      });
      await values.write(settingById('video.decoder'), 'software');
      await values.write(settingById('video.hwdec'), 'On');
      expect(engineOptionsFor(values, scope: {settingById('video.hwdec')}), {
        'hwdec': 'no',
      });
    });

    test(
      'an Expert cache number overrides the preset, Auto does not',
      () async {
        final values = await _with('playback.cachePreset', 'Large');
        final preset = settingById('playback.cachePreset');
        expect(engineOptionsFor(values, scope: {preset}), {
          'cache-secs': '3600000',
          'demuxer-max-bytes': '134217728',
          'demuxer-readahead-secs': '60',
        });
        await values.write(settingById('playback.readAhead'), 10.0);
        await values.write(settingById('playback.demuxerCacheSize'), 16.0);
        expect(engineOptionsFor(values, scope: {preset}), {
          'cache-secs': '3600000',
          'demuxer-max-bytes': '16777216',
          'demuxer-readahead-secs': '10.0',
        });
      },
    );

    test('a pixel format wins over chroma for the video filter', () async {
      final values = await _with('video.chroma', '4:4:4');
      await values.write(settingById('video.pixelFormat'), 'nv12');
      expect(engineOptionsFor(values, scope: {settingById('video.chroma')}), {
        'vf': 'format=nv12',
      });
    });

    test('Stretch and Original map the aspect properties', () async {
      final def = settingById('video.aspectRatio');
      final values = await _with('video.aspectRatio', 'Stretch');
      expect(engineOptionsFor(values, scope: {def}), {
        'keepaspect': 'no',
        'panscan': '0.0',
      });
      await values.write(def, 'Fit');
      expect(engineOptionsFor(values, scope: {def}), {
        'keepaspect': 'yes',
        'panscan': '0.0',
      });
    });

    test('Fullscreen mode follows the setting', () async {
      expect(fullscreenOf(_values()), isFalse);
      expect(
        fullscreenOf(await _with('display.fullscreenMode', 'Fullscreen')),
        isTrue,
      );
    });

    test('HDR handling follows both HDR settings', () async {
      expect(hdrPolicyOf(_values()), HdrPolicy.auto);
      expect(
        hdrPolicyOf(await _with('video.hdr', 'Force SDR')),
        HdrPolicy.forceSdr,
      );
      expect(
        hdrPolicyOf(await _with('display.hdrOutputMode', 'SDR')),
        HdrPolicy.forceSdr,
      );
      expect(
        hdrPolicyOf(await _with('video.hdr', 'Passthrough HDR')),
        HdrPolicy.passthrough,
      );
      expect(
        hdrPolicyOf(await _with('display.hdrOutputMode', 'HDR10')),
        HdrPolicy.passthrough,
      );
    });

    test(
      'every player setting is a mapped engine, behaviour or platform one',
      () {
        final unmapped = playerSettingDefs.where(
          (d) => !engineSettingDefs.contains(d) && d.target is MpvProperty,
        );
        expect(unmapped.map((d) => d.id), isEmpty);
      },
    );
  });

  group('mpv read-back', () {
    // Every value the UI offers for a mapped setting must be accepted by the
    // bundled mpv, not only the one value `_cases` checks.
    test('every choice of every mapped def is accepted by real mpv', () async {
      final (controller, backend) = _headless();
      try {
        for (final def in _p01Defs) {
          final values = switch (def.kind) {
            SettingKind.choice => def.choices,
            SettingKind.toggle => [true, false],
            _ => const <Object>[],
          };
          for (final value in values) {
            final settings = await _with(def.id, value);
            final options = engineOptionsFor(settings, scope: {def});
            await controller.open(clip.uri, engineOptions: options);
            for (final entry in options.entries) {
              final actual = await backend.getProperty(entry.key);
              final ok = _same(entry.value, actual);
              _rows.add(
                '| ${def.id} (choice) | $value | ${entry.key} | '
                '${entry.value} | $actual | ${ok ? 'PASS' : 'FAIL'} |',
              );
              expect(
                actual,
                predicate<String>((a) => _same(entry.value, a)),
                reason: '${def.id}=$value ${entry.key}',
              );
            }
          }
        }
      } finally {
        await controller.dispose();
      }
    });

    for (final c in _cases) {
      test('${c.id}: open applies it', () async {
        final def = settingById(c.id);
        final values = await _with(c.id, c.value);
        final (controller, backend) = _headless();
        try {
          await controller.open(
            clip.uri,
            engineOptions: engineOptionsFor(
              values,
              scope: changedEngineSettings(values),
            ),
          );
          for (final MapEntry(:key, :value) in c.expected.entries) {
            final actual = await backend.getProperty(key);
            final ok = _same(value, actual);
            _rows.add(
              '| ${def.id} | ${c.value} | $key | $value | $actual | '
              '${ok ? 'PASS' : 'FAIL'} |',
            );
            expect(
              actual,
              predicate<String>((a) => _same(value, a)),
              reason: '$key after open',
            );
          }
        } finally {
          await controller.dispose();
        }
      });

      final def = settingById(c.id);
      if (def.apply == SettingApply.live) {
        test('${c.id}: changes live while open', () async {
          final (controller, backend) = _headless();
          try {
            await controller.open(clip.uri);
            await controller.play();
            expect(await backend.getProperty('pause'), 'no');
            final before = {
              for (final key in c.expected.keys)
                key: await backend.getProperty(key),
            };
            final values = await _with(c.id, c.value);
            await controller.setEngineOptions(
              engineOptionsFor(values, scope: {def}),
            );
            var changed = false;
            for (final MapEntry(:key, :value) in c.expected.entries) {
              final actual = await backend.getProperty(key);
              changed |= !_same(before[key]!, actual);
              final ok = _same(value, actual);
              _rows.add(
                '| ${def.id} (live) | ${c.value} | $key | $value | '
                '$actual (was ${before[key]}) | ${ok ? 'PASS' : 'FAIL'} |',
              );
              expect(actual, predicate<String>((a) => _same(value, a)));
            }
            expect(changed, isTrue, reason: '${c.id} must change a property');
          } finally {
            await controller.dispose();
          }
        });
      }
    }

    for (final c in _cases.where(
      (c) => settingById(c.id).apply == SettingApply.live,
    )) {
      test(
        '${c.id}: returning to the default restores the engine state',
        () async {
          final def = settingById(c.id);
          final values = await _with(c.id, c.value);
          final (controller, backend) = _headless();
          try {
            await controller.open(clip.uri);
            await controller.play();
            expect(await backend.getProperty('pause'), 'no');
            final before = {
              for (final key in c.expected.keys)
                key: await backend.getProperty(key),
            };
            await controller.setEngineOptions(
              engineOptionsFor(values, scope: {def}),
            );
            await values.reset(def);
            await controller.setEngineOptions(
              engineOptionsFor(values, scope: {def}),
            );
            for (final key in c.expected.keys) {
              expect(
                await backend.getProperty(key),
                predicate<String>((a) => _same(before[key]!, a)),
                reason: key,
              );
            }
          } finally {
            await controller.dispose();
          }
        },
      );
    }

    test(
      'GPU APIs absent from this build are rejected and not offered',
      () async {
        final (controller, _) = _headless();
        try {
          await controller.open(clip.uri);
          for (final value in ['vulkan', 'd3d11', 'metal']) {
            await expectLater(
              controller.setEngineOptions({'gpu-api': value}),
              throwsA(isA<StateError>()),
            );
            expect(
              settingById('video.gpuRendering').choices,
              isNot(contains(value)),
            );
            _rows.add(
              '| video.gpuRendering (unsupported) | $value | gpu-api | '
              'rejected, not offered | mpv rejected | PASS |',
            );
          }
        } finally {
          await controller.dispose();
        }
      },
    );

    test('defaults produce exactly the engine state of a plain open', () async {
      final properties = {
        for (final def in _p01Defs)
          ..._cases.where((c) => c.id == def.id).expand((c) => c.expected.keys),
      }..remove('network-timeout'); // Auto 30 s deliberately replaces mpv's 5 s
      Future<Map<String, String>> state(Map<String, String> options) async {
        final (controller, backend) = _headless();
        try {
          await controller.open(clip.uri, engineOptions: options);
          return {for (final p in properties) p: await backend.getProperty(p)};
        } finally {
          await controller.dispose();
        }
      }

      final values = _values();
      final plain = await state(const {});
      final withDefaults = await state(
        engineOptionsFor(values, scope: changedEngineSettings(values)),
      );
      expect(withDefaults, plain);
      expect(
        engineOptionsFor(values, scope: changedEngineSettings(values)),
        containsPair('network-timeout', '30'),
      );
      for (final p in properties) {
        _rows.add(
          '| defaults | - | $p | ${plain[p]} | ${withDefaults[p]} | '
          '${plain[p] == withDefaults[p] ? 'PASS' : 'FAIL'} |',
        );
      }
    });

    test('a rejected setting value fails the open and keeps the row', () async {
      final values = await _with('display.calibration', 'abc,0,0');
      final (controller, _) = _headless();
      try {
        await expectLater(
          controller.open(
            clip.uri,
            engineOptions: engineOptionsFor(
              values,
              scope: changedEngineSettings(values),
            ),
          ),
          throwsA(isA<StateError>()),
        );
        expect(controller.currentState.failure, isA<PlaybackFailure>());
        expect(
          values.read<String>(settingById('display.calibration')),
          'abc,0,0',
        );
        _rows.add(
          '| display.calibration | abc,0,0 | video-zoom | a number | '
          'mpv rejected, open failed | PASS |',
        );
      } finally {
        await controller.dispose();
      }
    });
  });

  group('behaviour on the session', () {
    late FakeProgressRepository progress;

    setUp(() => progress = FakeProgressRepository());

    Future<void> saveProgress({
      Duration position = const Duration(seconds: 200),
      Duration duration = const Duration(seconds: 1000),
    }) => progress.upsert(
      PlaybackProgress(
        mediaId: _media.id,
        position: position,
        duration: duration,
        updatedAt: DateTime.now().toUtc(),
        completed: false,
      ),
    );

    /// Every position the sessions below asked their engine to seek to.
    final seeks = <Duration>[];

    PlaybackSession realSession(
      AppSettings settings, {
      void Function(mk.NativePlayer)? onBackend,
      Future<bool> Function(Duration)? askResume,
    }) => PlaybackSession(
      media: _media,
      streamSource: _FileSource(clip.uri),
      source: SourceSpec(kind: SourceKind.httpUrl, uri: clip.uri),
      progress: progress,
      settings: settings,
      askResume: askResume,
      controllerFactory: () {
        final (controller, backend) = _headless();
        onBackend?.call(backend);
        controller.events.listen((event) {
          if (event is SeekRequested) seeks.add(event.to);
        });
        return controller;
      },
    );

    Future<Duration?> resumedAt(
      String resume, {
      Future<bool> Function(Duration)? ask,
    }) async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(settingById('playback.resume'), resume);
      await saveProgress();
      seeks.clear();
      final session = realSession(settings, askResume: ask);
      try {
        await session.start();
        return seeks.singleOrNull;
      } finally {
        await session.dispose();
      }
    }

    const saved = Duration(seconds: 200);
    // The 2 s test clip clamps the engine's seek.
    const clamped = Duration(seconds: 2);

    test('resume Always starts at the saved position', () async {
      expect(await resumedAt('Always'), clamped);
    });

    test(
      'resume ignores the first 180 s and the last 8 % (Kodi 6.1)',
      () async {
        for (final (position, duration) in [(100, 1000), (930, 1000)]) {
          final settings = AppSettings(MemorySettingsStore());
          await settings.values.write(settingById('playback.resume'), 'Always');
          await saveProgress(
            position: Duration(seconds: position),
            duration: Duration(seconds: duration),
          );
          seeks.clear();
          final session = realSession(settings);
          await session.start();
          expect(seeks, isEmpty, reason: '$position/$duration');
          await session.dispose();
        }
      },
    );

    test('resume Never starts at the beginning', () async {
      expect(await resumedAt('Never'), isNull);
    });

    test('resume Ask follows the prompt', () async {
      final asked = <Duration>[];
      expect(
        await resumedAt(
          'Ask',
          ask: (p) async {
            asked.add(p);
            return false;
          },
        ),
        isNull,
      );
      expect(await resumedAt('Ask', ask: (p) async => true), clamped);
      expect(asked, [saved]);
    });

    test('resume Ask without a prompt resumes', () async {
      expect(await resumedAt('Ask'), clamped);
    });

    test('remember position off neither restores nor saves', () async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(
        settingById('playback.rememberPosition'),
        false,
      );
      await saveProgress();
      seeks.clear();
      final session = realSession(settings);
      await session.start();
      expect(seeks, isEmpty);
      await session.controller!.seek(const Duration(milliseconds: 500));
      await session.dispose();
      expect((await progress.get(_media.id))!.position, saved);
    });

    test('remember position on saves when the session ends', () async {
      await progress.clear(_media.id);
      final session = realSession(AppSettings(MemorySettingsStore()));
      await session.start();
      await session.dispose();
      expect(await progress.get(_media.id), isNotNull);
    });

    test('speed applies at open and live while playing', () async {
      final settings = AppSettings(MemorySettingsStore());
      final speed = settingById('playback.speed');
      await settings.values.write(speed, 2.0);
      late mk.NativePlayer backend;
      final session = realSession(settings, onBackend: (b) => backend = b);
      await session.start();
      expect(double.parse(await backend.getProperty('speed')), 2);

      // Subscribed after the session's own listener, so by the time this
      // fires the session has already queued the engine change.
      final changed = settings.values.changes.first;
      await settings.values.write(speed, 0.5);
      await changed;
      await session.controller!.setEngineOptions(const {});
      expect(double.parse(await backend.getProperty('speed')), 0.5);
      await session.dispose();
    });

    test('a next-video setting is not applied to the open video', () async {
      final settings = AppSettings(MemorySettingsStore());
      final sync = settingById('playback.syncToDisplay');
      late mk.NativePlayer backend;
      final session = realSession(settings, onBackend: (b) => backend = b);
      await session.start();
      final changed = settings.values.changes.first;
      await settings.values.write(sync, true);
      await changed;
      await session.controller!.setEngineOptions(const {});
      expect(await backend.getProperty('video-sync'), 'audio');
      await session.dispose();
    });

    test(
      'a rejected value fails the open and the row keeps the value',
      () async {
        final settings = AppSettings(MemorySettingsStore());
        final api = settingById('display.calibration');
        await settings.values.write(api, 'abc,0,0');
        final session = realSession(settings, onBackend: (_) {});
        await expectLater(session.start(), throwsA(isA<StateError>()));
        expect(settings.values.read<String>(api), 'abc,0,0');
        await session.dispose();
      },
    );

    Future<({int opened, bool playedNext, String playing})> endWith({
      required bool autoPlay,
      required bool hasNext,
    }) async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(
        settingById('playback.autoPlayNext'),
        autoPlay,
      );
      final controllers = <FakePlaybackController>[];
      final second = Completer<FakePlaybackController>();
      final asked = Completer<void>();
      final session = PlaybackSession(
        media: _media,
        streamSource: FakeStreamSource(),
        source: SourceSpec(
          kind: SourceKind.httpUrl,
          uri: Uri.parse('http://x/1'),
        ),
        settings: settings,
        nextSource: (_, _) async {
          asked.complete();
          return hasNext
              ? (
                  media: _next,
                  source: SourceSpec(
                    kind: SourceKind.httpUrl,
                    uri: Uri.parse('http://x/2'),
                  ),
                )
              : null;
        },
        controllerFactory: () {
          final controller = FakePlaybackController();
          controllers.add(controller);
          if (controllers.length == 2) second.complete(controller);
          return controller;
        },
      );
      await session.start();
      controllers.single.emitEvent(PlaybackEnded());
      var playedNext = false;
      if (autoPlay) {
        await asked.future;
        if (hasNext) {
          final next = await second.future;
          await next.state.firstWhere((s) => s.isPlaying);
          playedNext = true;
        }
      }
      // Let the end handler finish before counting what it opened.
      await Future<void>.delayed(Duration.zero);
      final opened = controllers.length;
      final playing = session.media.id;
      await session.dispose();
      return (opened: opened, playedNext: playedNext, playing: playing);
    }

    test('auto-play next starts the next episode at the end', () async {
      final r = await endWith(autoPlay: true, hasNext: true);
      expect(r.opened, 2);
      expect(r.playedNext, isTrue);
      expect(r.playing, _next.id);
    });

    test('auto-play next off stays on the ended video', () async {
      final r = await endWith(autoPlay: false, hasNext: true);
      expect(r.opened, 1);
    });

    test('auto-play next with no next episode stays put', () async {
      final r = await endWith(autoPlay: true, hasNext: false);
      expect(r.opened, 1);
    });
  });

  group('display matching', () {
    final modes = [
      const DisplayMode(
        width: 1920,
        height: 1080,
        refreshHz: 60,
        isCurrent: true,
      ),
      const DisplayMode(
        width: 1920,
        height: 1080,
        refreshHz: 24,
        isCurrent: false,
      ),
      const DisplayMode(
        width: 1920,
        height: 1080,
        refreshHz: 23.976,
        isCurrent: false,
      ),
      const DisplayMode(
        width: 3840,
        height: 2160,
        refreshHz: 24,
        isCurrent: false,
      ),
    ];

    Future<_Harness> started({
      required SettingsValues values,
      double fps = 23.976,
    }) async {
      final harness = _Harness(modes, displayMatchingOf(values));
      await harness.policy.start(
        controller: FakePlaybackController(),
        contentFps: fps,
        width: 1920,
        height: 1080,
      );
      return harness;
    }

    test('Match frame rate Off never calls matchDisplay', () async {
      final h = await started(
        values: await _with('video.matchFrameRate', 'Off'),
      );
      expect(h.display.calls, isEmpty);
      expect(h.diagnostics.snapshot['displayMode'], 'disabled');
      await h.policy.stop();
    });

    test('On start-stop matches at start and restores at stop', () async {
      final h = await started(values: _values());
      expect(h.display.calls, [(23.976, 1920, 1080)]);
      expect(h.diagnostics.snapshot['displayMode'], 'leased');
      expect(h.display.leases.single.released, isFalse);
      await h.policy.stop();
      expect(h.display.leases.single.released, isTrue);
    });

    test('Always matches again when the content frame rate changes', () async {
      final h = await started(
        values: await _with('video.matchFrameRate', 'Always'),
      );
      await h.policy.matchDisplay(
        contentFps: 23.976,
        width: 1920,
        height: 1080,
      );
      expect(h.display.calls, hasLength(1));
      await h.policy.matchDisplay(contentFps: 25, width: 1920, height: 1080);
      expect(h.display.calls.last, (25.0, 1920, 1080));
      expect(h.display.leases.first.released, isTrue);
      await h.policy.stop();
      expect(h.display.leases.last.released, isTrue);
    });

    test('On start-stop keeps the first match for the session', () async {
      final h = await started(values: _values());
      await h.policy.matchDisplay(contentFps: 25, width: 1920, height: 1080);
      expect(h.display.calls, hasLength(1));
      await h.policy.stop();
    });

    test('Match resolution Off changes the refresh rate only', () async {
      final h = await started(
        values: await _with('video.matchResolution', 'Off'),
      );
      expect(h.display.calls, [(23.976, null, null)]);
      await h.policy.stop();
    });

    test('a forced refresh rate replaces the content frame rate', () async {
      final h = await started(values: await _with('display.refreshRate', '50'));
      expect(h.display.calls.single.$1, 50);
      await h.policy.stop();
    });

    test('a whitelist excluding the content mode picks none', () async {
      final h = await started(
        values: await _with('video.displayModeWhitelist', '1920x1080@60'),
      );
      expect(h.display.calls, isEmpty);
      expect(h.diagnostics.snapshot['displayMode'], 'unavailable');
      await h.policy.stop();
      expect(h.display.leases, isEmpty);
    });

    test('a whitelist allowing a mode picks exactly that mode', () async {
      final h = await started(
        values: await _with('video.displayModeWhitelist', '1920x1080@24'),
      );
      expect(h.display.calls, [(24.0, 1920, 1080)]);
      await h.policy.stop();
    });

    test('an invalid whitelist entry allows nothing and is recorded', () async {
      final h = await started(
        values: await _with('video.displayModeWhitelist', 'banana'),
      );
      expect(h.display.calls, isEmpty);
      expect(h.diagnostics.snapshot['whitelistInvalid'], 'banana');
      await h.policy.stop();
    });

    test('the real display service lists modes, the whitelist excludes, '
        'and nothing is switched', () async {
      final channel = _ModeChannel(modes);
      final service = DisplayModeServiceImpl(channel: channel);
      final listed = await service.availableModes();
      final whitelist = DisplayModeWhitelist.parse('1920x1080@60');
      final match = ModeMatcher.match(
        contentFps: 23.976,
        modes: whitelist.filter(listed),
        current: listed.where((m) => m.isCurrent).firstOrNull,
        width: 1920,
        height: 1080,
      );
      expect(listed, hasLength(4));
      expect(match, isNull);
      expect(channel.methods, [PlatformMethods.displayModes]);
    });
  });
}

const _next = MediaItem(
  id: 'next-episode',
  title: 'Next',
  kind: MediaKind.episode,
);
const _media = MediaItem(
  id: 'settings-media',
  title: 'Settings media',
  kind: MediaKind.movie,
);

final class _FileSource implements StreamSource {
  _FileSource(this.uri);
  final Uri uri;

  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async => _FileHandle(uri);

  @override
  Future<int> clearCache() async => 0;
}

final class _FileHandle extends FakeStreamHandle {
  _FileHandle(this.uri);
  final Uri uri;

  @override
  Uri get playbackUri => uri;
}

final class _Lease implements DisplayModeLease {
  bool released = false;

  @override
  Future<void> release() async => released = true;
}

final class _Display implements DisplayModeService {
  _Display(this.modes);
  final List<DisplayMode> modes;
  final calls = <(double, int?, int?)>[];
  final leases = <_Lease>[];

  @override
  Future<List<DisplayMode>> availableModes() async => modes;

  @override
  Future<DisplayModeLease?> matchFor({
    required double contentFps,
    int? width,
    int? height,
  }) async {
    calls.add((contentFps, width, height));
    return _Lease().also(leases.add);
  }
}

extension<T> on T {
  T also(void Function(T) action) {
    action(this);
    return this;
  }
}

final class _Harness {
  _Harness(
    List<DisplayMode> modes,
    ({bool enabled, DisplayMatchOptions options}) display,
  ) : display = _Display(modes),
      diagnostics = DiagnosticsCollector(os: 'test', appVersion: 'test') {
    policy = PlatformPolicy(
      capabilities: FakePlatformCapabilities(
        report: CapabilityReport(
          hardwareDecode: true,
          decoders: const ['h264'],
          hdrOutput: false,
          hdrFormats: const [],
          displayModeSwitching: true,
          audioPassthrough: false,
          passthroughFormats: const [],
          diagnostics: const {},
        ),
      ),
      displayModes: this.display,
      audio: FakeAudioOutputService(),
      events: const Stream<PlatformEvent>.empty(),
      mediaCommands: const Stream<MediaSessionCommand>.empty(),
      acquireKeepAwake: () async => () async {},
      clearMediaSession: () async {},
      diagnostics: diagnostics,
      displayModeMatchingEnabled: display.enabled,
      displayOptions: display.options,
    );
  }

  final _Display display;
  final DiagnosticsCollector diagnostics;
  late final PlatformPolicy policy;
}

final class _ModeChannel implements PlatformChannel {
  _ModeChannel(this.modes);
  final List<DisplayMode> modes;
  final methods = <String>[];

  @override
  Stream<Object?> get events => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    methods.add(method);
    return {
      'supported': true,
      'modes': [
        for (final m in modes)
          {
            'width': m.width,
            'height': m.height,
            'refreshHz': m.refreshHz,
            'isCurrent': m.isCurrent,
          },
      ],
    };
  }
}
