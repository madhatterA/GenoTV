import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

class _Service implements AudioOutputService {
  _Service(this.devs, this.ok);
  final List<AudioDevice> devs;
  final Set<String> ok;
  @override
  AudioPlan plan(
    Track track,
    AudioCapabilityModel model, {
    int? channels,
    Set<String>? decoders,
  }) => throw UnimplementedError();
  @override
  Future<List<AudioDevice>> devices() async => devs;
  @override
  Future<AudioNegotiation> negotiate(AudioStreamSpec s) async =>
      AudioNegotiation(
        passthrough: ok.contains(s.codec),
        requestedPassthrough: true,
        fallbackReason: ok.contains(s.codec) ? null : 'no ${s.codec}',
        deviceId: '1',
      );
}

AudioCapabilityModel m(AudioLink l) =>
    AudioCapabilityModel(link: l, deviceFormats: {...AudioFormat.values});

void main() {
  for (final selected in ['hdmi', 'speaker', 'missing', 'auto']) {
    test('detect selected $selected independently of default output', () async {
      final model = await detectAudioCapability(
        _Service([
          AudioDevice(id: 'hdmi', name: 'TV', kind: AudioDeviceKind.hdmi,
              isCurrent: selected == 'speaker'),
          AudioDevice(id: 'speaker', name: 'Speakers', kind: AudioDeviceKind.speaker,
              isCurrent: selected != 'speaker'),
        ], {'ac3'}),
        deviceId: selected,
      );
      expect(model.link, selected == 'hdmi' ? AudioLink.hdmiEarc : AudioLink.pcmOnly);
      expect(model.formats, selected == 'hdmi' ? {AudioFormat.ac3} : isEmpty);
    });
  }
  test(
    'link table: a receiver reporting everything is limited by the link',
    () {
      expect(m(AudioLink.hdmiEarc).formats, AudioFormat.values.toSet());
      expect(m(AudioLink.hdmiEarc).maxPcmChannels, 8);
      expect(m(AudioLink.arc).formats, {
        AudioFormat.ac3,
        AudioFormat.eac3,
        AudioFormat.dts,
      });
      expect(m(AudioLink.arc).maxPcmChannels, 2);
      expect(m(AudioLink.optical).formats, {AudioFormat.ac3, AudioFormat.dts});
      expect(m(AudioLink.optical).maxPcmChannels, 2);
      expect(m(AudioLink.pcmOnly).formats, isEmpty);
    },
  );

  test('device formats the receiver lacks are not allowed', () {
    final model = AudioCapabilityModel(
      link: AudioLink.hdmiEarc,
      deviceFormats: {AudioFormat.ac3},
    );
    expect(model.formats, {AudioFormat.ac3});
  });

  test('detect: HDMI current device with AC3/E-AC3 physical formats', () async {
    final model = await detectAudioCapability(
      _Service(
        [
          AudioDevice(
            id: '2',
            name: 'Speakers',
            kind: AudioDeviceKind.speaker,
          ),
          AudioDevice(
            id: '1',
            name: 'TV',
            kind: AudioDeviceKind.hdmi,
            isCurrent: true,
          ),
        ],
        {'ac3', 'eac3'},
      ),
    );
    expect(model.link, AudioLink.hdmiEarc);
    expect(model.formats, {AudioFormat.ac3, AudioFormat.eac3});
  });

  test('detect: non-HDMI, or no current device, is PCM only', () async {
    final speaker = await detectAudioCapability(
      _Service(
        [
          AudioDevice(
            id: '1',
            name: 'Speakers',
            kind: AudioDeviceKind.speaker,
            isCurrent: true,
          ),
        ],
        {'ac3'},
      ),
    );
    expect(speaker.link, AudioLink.pcmOnly);
    expect(speaker.formats, isEmpty);
    final none = await detectAudioCapability(_Service([], {'ac3'}));
    expect(none.link, AudioLink.pcmOnly);
  });
}
