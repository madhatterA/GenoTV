import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/player_settings.dart';
import 'package:video_player/ui_bindings.dart';

import 'package:platform_services/platform_services.dart' show planAudio;

CapabilityReport _report({bool passthrough = false}) => CapabilityReport(
  hardwareDecode: false,
  decoders: const [],
  hdrOutput: false,
  hdrFormats: const [],
  displayModeSwitching: false,
  audioPassthrough: passthrough,
  passthroughFormats: const [],
  diagnostics: const {'os': 'windows'},
);

void main() {
  late SettingsValues values;
  setUp(() => values = SettingsValues(MemorySettingsStore()));
  tearDown(() => values.dispose());

  test('Windows plan is limited to probed sink formats and probed PCM max', () {
    final o = audioPlanOverridesFor(values, os: 'windows', maxChannels: 6);
    expect(o.restrictToSinkFormats, isTrue);
    expect(o.pcmChannelLimit, 6);
    expect(audioPlanOverridesFor(values, os: 'windows').pcmChannelLimit, 2);
  });

  test('Windows opens through the wasapi AO with Kodi resampling', () {
    final o = audioEngineOptionsFor(values, os: 'windows');
    expect(o['ao'], 'wasapi');
    expect(o['audio-swresample-o'], 'filter_size=64,cutoff=0.985');
    expect(o['audio-exclusive'], 'no');
  });

  test('Windows offers device selection and exclusive mode; passthrough only with a device', () {
    final none = availableSettingCapabilities(_report(), os: 'windows');
    expect(none, contains(SettingCapability.audioDeviceSelection));
    expect(none, contains(SettingCapability.exclusiveAudio));
    expect(none, isNot(contains(SettingCapability.audioPassthrough)));
    expect(
      availableSettingCapabilities(_report(passthrough: true), os: 'windows'),
      contains(SettingCapability.audioPassthrough),
    );
  });

  test(
    'bitstream without an explicit device uses the probed passthrough device',
    () {
      final devices = [
        AudioDevice(id: 'wasapi/a', name: 'Speakers', isCurrent: true),
        AudioDevice(id: 'wasapi/b', name: 'HDMI', kind: AudioDeviceKind.hdmi),
      ];
      expect(
        selectedAudioDeviceId(
          values,
          devices,
          bitstream: true,
          passthroughDefault: 'wasapi/b',
        ),
        'wasapi/b',
      );
      expect(selectedAudioDeviceId(values, devices, bitstream: false), 'auto');
    },
  );

  test(
    'Windows never sends an unprobed spdif carrier before the plan exists',
    () async {
      await values.write(settingById('audio.passthrough'), 'Enabled');
      await values.write(settingById('audio.speakerLayout'), '5.1');
      await values.write(settingById('audio.receiver.dolbyDigital'), 'Enabled');
      expect(audioEngineOptionsFor(values, os: 'windows')['audio-spdif'], '');
      expect(audioEngineOptionsFor(values, os: 'macos')['audio-spdif'], 'ac3');
    },
  );

  test(
    'Windows Fixed always disables bitstream even with an accepting sink',
    () async {
      await values.write(settingById('audio.outputMode'), 'Fixed');
      await values.write(settingById('audio.passthrough'), 'Enabled');
      expect(
        audioPlanOverridesFor(values, os: 'windows').passthrough,
        'Disabled',
      );
      final bitstream = AudioPlan(
        step: AudioPlanStep.bitstream,
        outputCodec: 'ac3',
        channels: 6,
        audioSpdif: 'ac3',
        audioChannels: 'auto-safe',
      );
      expect(
        audioEngineOptionsFor(
          values,
          os: 'windows',
          plan: bitstream,
        )['audio-spdif'],
        '',
      );
    },
  );

  test('bitstream opens platform fallback when the requested passthrough device is PCM-only', () async {
    await values.write(settingById('audio.passthroughDevice'), 'wasapi/a');
    final devices = [
      AudioDevice(id: 'wasapi/a', name: 'Speakers', isCurrent: true),
      AudioDevice(id: 'wasapi/b', name: 'HDMI', kind: AudioDeviceKind.hdmi),
    ];
    expect(
      selectedAudioDeviceId(
        values,
        devices,
        bitstream: true,
        passthroughDefault: 'wasapi/b',
      ),
      'wasapi/b',
    );
  });

  test(
    'Windows pan output drives PCM layout and the AC3 encoder input',
    () async {
      await values.write(settingById('audio.stereoUpmix'), true);
      await values.write(settingById('audio.speakerLayout'), '5.1');
      final model = AudioCapabilityModel(
        link: AudioLink.hdmiEarc,
        deviceFormats: {AudioFormat.ac3},
      );
      expect(
        audioFilterOutputChannelsFor(
          values,
          os: 'windows',
          sourceChannels: 2,
          maxChannels: 6,
          model: model,
        ),
        6,
      );
      final pcmPlan = planAudio(
        Track(id: 'a', type: TrackType.audio, codec: 'aac'),
        model,
        channels: audioFilterOutputChannelsFor(
          values,
          os: 'windows',
          sourceChannels: 2,
          maxChannels: 6,
          model: model,
        ),
        overrides: audioPlanOverridesFor(values, os: 'windows', maxChannels: 6),
      );
      expect(pcmPlan.step, AudioPlanStep.pcmMulti);
      expect(pcmPlan.channels, 6);
      final pcm = audioEngineOptionsFor(
        values,
        os: 'windows',
        plan: pcmPlan,
        info: MediaInfo(audioChannels: 2),
      );
      expect(pcm['audio-channels'], '5.1');
      expect(pcm['af'], contains('pan=5.1'));
      expect(pcm['af'], isNot(contains('|SL=')));
      expect(
        audioFilterOutputChannelsFor(
          values,
          os: 'windows',
          sourceChannels: 2,
          maxChannels: 2,
          model: model,
        ),
        2,
      );
      final stereo = audioEngineOptionsFor(
        values,
        os: 'windows',
        plan: AudioPlan(
          step: AudioPlanStep.stereo,
          outputCodec: 'pcm',
          channels: 2,
          audioChannels: 'stereo',
          audioSpdif: '',
        ),
        info: MediaInfo(audioChannels: 2),
      );
      expect(stereo['af'], '');
      await values.write(settingById('audio.speakerLayout'), 'Stereo');
      await values.write(settingById('audio.passthrough'), 'Enabled');
      await values.write(settingById('audio.ac3Transcode'), 'Enabled');
      expect(
        audioFilterOutputChannelsFor(
          values,
          os: 'windows',
          sourceChannels: 2,
          maxChannels: 2,
          model: model,
        ),
        6,
      );
      final transcodePlan = planAudio(
        Track(id: 'a', type: TrackType.audio, codec: 'aac'),
        model,
        channels: audioFilterOutputChannelsFor(
          values,
          os: 'windows',
          sourceChannels: 2,
          maxChannels: 2,
          model: model,
        ),
        overrides: audioPlanOverridesFor(values, os: 'windows', maxChannels: 2),
      );
      expect(transcodePlan.step, AudioPlanStep.ac3Encode);
      expect(transcodePlan.channels, 6);
      final transcode = audioEngineOptionsFor(
        values,
        os: 'windows',
        plan: transcodePlan,
        info: MediaInfo(audioChannels: 2),
      );
      expect(transcode['af'], startsWith('lavfi=[pan=5.1'));
      expect(transcode['af'], endsWith('],lavcac3enc'));
      await values.write(settingById('audio.outputMode'), 'Fixed');
      expect(
        audioFilterOutputChannelsFor(
          values,
          os: 'windows',
          sourceChannels: 2,
          maxChannels: 2,
          model: model,
        ),
        2,
      );
    },
  );
}
