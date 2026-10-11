import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:video_player/player_settings.dart';
import 'package:playback/playback.dart';
// Same real-engine harness as player_settings_test.dart.
// ignore: implementation_imports
import 'package:playback/src/controller/media_kit_playback_controller.dart';
// ignore: implementation_imports
import 'package:playback/src/surface/surface_output.dart';

void main() {
  late Directory dir;
  late File clip;
  final rows = <String>[];
  setUpAll(() async {
    mk.MediaKit.ensureInitialized(
      libmpv: Platform.environment['PLAYBACK_LIBMPV'],
    );
    dir = await Directory.systemTemp.createTemp('audio-settings-');
    clip = File('${dir.path}/stereo.wav');
    final generated = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=44100',
      '-ac',
      '2',
      '-t',
      '2',
      '-y',
      clip.path,
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());
  });
  tearDownAll(() async {
    try {
      await File('${dir.path}/readback.md').writeAsString(
        '# Real libmpv audio readback, generated 2-second clip\n\n'
        '| Setting | Value | Property | Expected | Got | Result |\n'
        '| --- | --- | --- | --- | --- | --- |\n${rows.join('\n')}\n',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  SettingsValues values() => AppSettings(MemorySettingsStore()).values;
  (MediaKitPlaybackController, mk.NativePlayer) engine() {
    final p = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    return (
      MediaKitPlaybackController(
        logger: MemoryLogger(),
        player: p,
        output: SurfaceOutput(
          attach: () async => throw UnsupportedError('headless'),
          texture: () async {},
          logger: MemoryLogger(),
          onError: (error, stack) => fail('$error'),
        ),
      ),
      p.platform as mk.NativePlayer,
    );
  }

  bool same(String key, String expected, String got) {
    if (expected == got) return true;
    if (num.tryParse(expected) != null && num.tryParse(got) != null) {
      return num.parse(expected) == num.parse(got);
    }
    if (key == 'af') {
      if (expected.isEmpty) return got.isEmpty || got == '[]';
      return got ==
          expected.replaceAll('lavfi=[', 'lavfi=graph=').replaceAll(']', '');
    }
    if (key == 'audio-spdif' && expected.isEmpty) return got == '[]';
    if (key == 'audio-swresample-o') {
      if (expected.isEmpty) return got == '{}' || got == '[]';
      return got.contains(expected.split('=').last);
    }
    return false;
  }

  test('every mpv mapped audio choice reads back', () async {
    final (controller, backend) = engine();
    try {
      const mapped = {
        'audio.outputDevice': ['Auto'],
        'audio.speakerLayout': ['Auto', 'Stereo', '5.1', '7.1'],
        'audio.normalizeVolume': [true, false],
        'audio.outputMode': ['Best Match', 'Fixed', 'Optimized'],
        'audio.passthroughDevice': [''],
        'audio.stereoUpmix': [true, false],
        'audio.downmixDialogue': [0.0, 6.0, 12.0],
        'audio.resamplingQuality': ['Fast', 'Balanced', 'High'],
        'audio.sampleRate': [
          'Auto',
          '44100',
          '48000',
          '88200',
          '96000',
          '176400',
          '192000',
        ],
        'audio.exclusiveMode': [true, false],
        'audio.deviceKeepAlive': [true, false],
      };
      for (final item in mapped.entries) {
        for (final value in item.value) {
          final settings = values();
          await settings.write(settingById(item.key), value);
          if (item.key == 'audio.sampleRate') {
            await settings.write(settingById('audio.outputMode'), 'Fixed');
          }
          final options = audioEngineOptionsFor(settings);
          await controller.open(clip.uri, engineOptions: options);
          await controller.play();
          for (final entry in options.entries) {
            final got = await backend.getProperty(entry.key);
            final ok = same(entry.key, entry.value, got);
            rows.add(
              '| ${item.key} | $value | ${entry.key} | ${entry.value} | $got | ${ok ? 'PASS' : 'FAIL'} |',
            );
            expect(
              ok,
              isTrue,
              reason: '${item.key}=$value ${entry.key}: ${entry.value} != $got',
            );
          }
          settings.dispose();
        }
      }
    } finally {
      await controller.dispose();
    }
  });
  test(
    'optimized converts only an unsupported 44.1 family source rate',
    () async {
      final settings = values();
      await settings.write(settingById('audio.outputMode'), 'Optimized');
      String rate(List<int> rates, int source) => audioEngineOptionsFor(
        settings,
        info: MediaInfo(audioSampleRate: source),
        device: AudioDevice(id: 'x', name: 'X', supportedSampleRates: rates),
      )['audio-samplerate']!;
      expect(rate([48000], 44100), '48000');
      expect(rate([44100, 48000], 44100), '0');
      expect(rate([], 44100), '0');
      expect(rate([96000], 88200), '96000');
      expect(rate([48000], 32000), '0');
      settings.dispose();
    },
  );
  test('unknown saved device uses Auto and logs a warning', () async {
    final settings = values();
    await settings.write(
      settingById('audio.outputDevice'),
      'coreaudio/unplugged',
    );
    final logger = MemoryLogger();
    expect(selectedAudioDevice(settings, [], logger: logger), isNull);
    expect(selectedAudioDeviceId(settings, []), 'auto');
    expect(
      logger.records.any((e) => e.message.contains('unavailable')),
      isTrue,
    );
    await File('${dir.path}/device.txt').writeAsString(
      'Unknown saved output: coreaudio/unplugged\nPlayback device: auto\n'
      '${logger.records.map((e) => e.message).join('\n')}\nPASS\n',
    );
    settings.dispose();
  });
  test('Fixed layout wins over a source-following PCM plan', () async {
    final settings = values();
    await settings.write(settingById('audio.outputMode'), 'Fixed');
    for (final layout in {
      'Stereo': 'stereo',
      '5.1': '5.1',
      '7.1': '7.1',
    }.entries) {
      await settings.write(settingById('audio.speakerLayout'), layout.key);
      final options = audioEngineOptionsFor(
        settings,
        plan: AudioPlan(
          step: AudioPlanStep.stereo,
          outputCodec: 'pcm',
          channels: 2,
          audioSpdif: '',
          audioChannels: 'stereo',
        ),
      );
      expect(options['audio-channels'], layout.value);
    }
    settings.dispose();
  });
  test('Kodi stereo upmix and AC3 encoding coexist in real mpv filter chain', () async {
    final settings = values();
    await settings.write(settingById('audio.stereoUpmix'), true);
    final options = audioEngineOptionsFor(
      settings,
      info: const MediaInfo(audioChannels: 2),
      plan: AudioPlan(
        step: AudioPlanStep.ac3Encode,
        outputCodec: 'ac3',
        channels: 6,
        audioSpdif: 'ac3',
        audioChannels: '5.1',
        af: 'lavcac3enc',
      ),
    );
    expect(options['af'], '$kodiStereoUpmix,lavcac3enc');
    final (controller, backend) = engine();
    try {
      await controller.open(clip.uri, engineOptions: options);
      await controller.play();
      final got = await backend.getProperty('af');
      expect(got, contains('pan'));
      expect(got, contains('lavcac3enc'));
      rows.add(
        '| upmix + AC3 encode | Enabled | af | ${options['af']} | $got | PASS |',
      );
    } finally {
      await controller.dispose();
      settings.dispose();
    }
  });
  test('every audio planner def reaches an override input', () async {
    for (final def in audioSettingDefs.where((d) => d.target is PlatformCall)) {
      for (final value in def.choices) {
        final settings = values();
        await settings.write(def, value);
        final overrides = audioPlanOverridesFor(settings);
        final expected = value == 'Enabled'
            ? true
            : value == 'Disabled'
            ? false
            : null;
        switch (def.id) {
          case 'audio.passthrough':
            expect(overrides.passthrough, value);
          case 'audio.multichannelLpcm':
            expect(overrides.multichannelLpcm, expected);
          case 'audio.ac3Transcode':
            expect(overrides.ac3Transcoding, expected);
          case 'audio.receiver.atmos':
            expect(overrides.receiverAtmos, value == 'Enabled');
          case 'audio.receiver.dtsX':
            expect(overrides.receiverDtsX, value == 'Enabled');
          case 'audio.outputMode':
            final options = audioEngineOptionsFor(
              settings,
              info: const MediaInfo(audioSampleRate: 44100),
              device: AudioDevice(
                id: 'x',
                name: 'X',
                supportedSampleRates: [48000],
              ),
            );
            expect(
              options['audio-samplerate'],
              value == 'Optimized' ? '48000' : '0',
            );
          default:
            final codec = {
              'audio.receiver.dolbyDigital': AudioFormat.ac3,
              'audio.receiver.ddPlus': AudioFormat.eac3,
              'audio.receiver.dts': AudioFormat.dts,
              'audio.receiver.trueHd': AudioFormat.trueHd,
              'audio.receiver.dtsHd': AudioFormat.dtsHd,
            }[def.id];
            expect(
              codec,
              isNotNull,
              reason: 'Uncovered planner setting ${def.id}',
            );
            expect(
              overrides.receiverFormats.contains(codec),
              value == 'Enabled',
            );
        }
        settings.dispose();
      }
    }
  });
}
