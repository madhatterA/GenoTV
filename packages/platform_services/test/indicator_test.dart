import 'package:contracts/contracts.dart';
import 'package:platform_services/platform_services.dart';
import 'package:flutter_test/flutter_test.dart';

AudioCapabilityModel _m(AudioLink l) =>
    AudioCapabilityModel(link: l, deviceFormats: {...AudioFormat.values});

String _line(String codec, AudioLink link, {String? title}) {
  final t = Track(id: '1', type: TrackType.audio, codec: codec, title: title);
  return audioOutputLine(t, planAudio(t, _m(link)));
}

void main() {
  test(
    'manual metadata support reports carrier playback and decoding loss',
    () {
      final track = Track(
        id: '1',
        type: TrackType.audio,
        codec: 'truehd',
        title: 'Atmos',
      );
      final carrier = planAudio(
        track,
        _m(AudioLink.hdmiEarc),
        overrides: const AudioPlanOverrides(
          passthrough: 'Enabled',
          receiverFormats: {AudioFormat.trueHd},
          receiverAtmos: false,
        ),
      );
      expect(
        audioOutputLine(track, carrier),
        'Atmos not supported by receiver — plays as TrueHD 7.1 · Passthrough',
      );
      final decoded = planAudio(
        track,
        _m(AudioLink.hdmiEarc),
        overrides: const AudioPlanOverrides(passthrough: 'Disabled'),
      );
      expect(
        audioOutputLine(track, decoded),
        'TrueHD Atmos → PCM 7.1 · Lost Atmos',
      );
    },
  );

  test('chain table strings', () {
    expect(
      _line('truehd', AudioLink.hdmiEarc, title: 'TrueHD Atmos'),
      'TrueHD Atmos · Passthrough',
    );
    expect(_line('ac3', AudioLink.optical), 'AC3 5.1 · Passthrough');
    expect(_line('truehd', AudioLink.arc), 'TrueHD → Dolby Digital 5.1');
    expect(_line('dts-hd', AudioLink.arc), 'DTS-HD → DTS 5.1');
    expect(_line('truehd', AudioLink.pcmOnly), 'TrueHD → Stereo');
    expect(_line('aac', AudioLink.hdmiEarc), 'AAC → PCM 5.1');
  });

  test('unplayable', () {
    final t = Track(id: '1', type: TrackType.audio, codec: 'flac');
    final m = AudioCapabilityModel(
      link: AudioLink.optical,
      deviceFormats: {AudioFormat.ac3},
    );
    expect(
      audioOutputLine(t, planAudio(t, m, decoders: {'aac'})),
      "FLAC · Can't play on this device",
    );
  });
}
