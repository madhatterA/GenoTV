import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

void main() {
  final rejected = AudioCapabilityModel(
    link: AudioLink.pcmOnly,
    deviceFormats: {},
  );
  const ac3 = Track(id: '1', type: TrackType.audio, codec: 'ac3');
  test('Android user enabled format cannot bypass sink rejection', () {
    final plan = planAudio(
      ac3,
      rejected,
      channels: 6,
      overrides: const AudioPlanOverrides(
        passthrough: 'Enabled',
        receiverFormats: {AudioFormat.ac3},
        restrictToSinkFormats: true,
        pcmChannelLimit: 8,
        layoutChannels: 2,
      ),
    );
    expect(plan.step, AudioPlanStep.stereo);
    expect(plan.audioSpdif, isEmpty);
  });
  test('Android requested PCM layout caps Kodi KnownChannels', () {
    final plan = planAudio(
      ac3,
      rejected,
      channels: 6,
      overrides: const AudioPlanOverrides(
        passthrough: 'Disabled',
        restrictToSinkFormats: true,
        pcmChannelLimit: 8,
        layoutChannels: 6,
      ),
    );
    expect(plan.step, AudioPlanStep.pcmMulti);
    expect(plan.channels, 6);
  });
  test('Android rejected AC3 encoder carrier cannot be opened', () {
    final plan = planAudio(
      ac3,
      rejected,
      channels: 6,
      overrides: const AudioPlanOverrides(
        passthrough: 'Enabled',
        ac3Transcoding: true,
        multichannelLpcm: false,
        restrictToSinkFormats: true,
        layoutChannels: 6,
      ),
    );
    expect(plan.step, AudioPlanStep.stereo);
    expect(plan.af, isEmpty);
  });
  test(
    'Android passthrough selection is independent of PCM speaker layout',
    () {
      final accepted = AudioCapabilityModel(
        link: AudioLink.hdmiEarc,
        deviceFormats: {AudioFormat.ac3},
      );
      final plan = planAudio(
        ac3,
        accepted,
        channels: 6,
        overrides: const AudioPlanOverrides(
          passthrough: 'Enabled',
          receiverFormats: {AudioFormat.ac3},
          restrictToSinkFormats: true,
          layoutChannels: 2,
        ),
      );
      expect(plan.step, AudioPlanStep.bitstream);
      expect(plan.audioSpdif, 'ac3');
    },
  );
  test(
    'iOS session maximum caps multichannel PCM; stereo route stays stereo',
    () {
      for (final (limit, step, channels) in [
        (6, AudioPlanStep.pcmMulti, 6),
        (2, AudioPlanStep.stereo, 2),
      ]) {
        final plan = planAudio(
          ac3,
          rejected,
          channels: 6,
          overrides: AudioPlanOverrides(
            passthrough: 'Disabled',
            pcmChannelLimit: limit,
            layoutChannels: 6,
          ),
        );
        expect(plan.step, step);
        expect(plan.channels, channels);
        expect(plan.outputCodec, 'pcm');
      }
    },
  );
}
