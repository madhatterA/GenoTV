import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _PlanChannel implements PlatformChannel {
  @override
  Stream<Object?> get events => const Stream.empty();
  @override
  Future<Object?> invoke(String method, [Object? arguments]) async => null;
  @override
  Future<void> dispose() async {}
}

String result(AudioPlan p) => '${p.step.name}:${p.outputCodec}:${p.channels}';

void main() {
  test('bitstream and decoded PCM use independent output routes', () {
    final hdmi = AudioCapabilityModel(
      link: AudioLink.hdmiEarc,
      deviceFormats: {AudioFormat.ac3},
    );
    final speakers = AudioCapabilityModel(
      link: AudioLink.pcmOnly,
      deviceFormats: {},
    );
    const ac3 = Track(id: 'ac3', type: TrackType.audio, codec: 'ac3');
    const aac = Track(id: 'aac', type: TrackType.audio, codec: 'aac');
    expect(
      planAudio(ac3, hdmi, pcmModel: speakers, channels: 6).step,
      AudioPlanStep.bitstream,
    );
    expect(
      planAudio(ac3, speakers, pcmModel: hdmi, channels: 6).step,
      AudioPlanStep.pcmMulti,
    );
    expect(
      planAudio(
        aac,
        hdmi,
        pcmModel: speakers,
        channels: 6,
        overrides: const AudioPlanOverrides(ac3Transcoding: false),
      ).channels,
      2,
    );
    expect(planAudio(aac, speakers, pcmModel: hdmi, channels: 6).channels, 6);
  });
  final model = AudioCapabilityModel(
    link: AudioLink.hdmiEarc,
    deviceFormats: {AudioFormat.dts},
  );
  const sources = [
    ('AC3', 'ac3', 6),
    ('E-AC3', 'eac3', 6),
    ('DTS', 'dts', 6),
    ('DTS-HD MA', 'dts-hd', 8),
    ('TrueHD', 'truehd', 8),
    ('TrueHD+Atmos', 'truehd', 8),
    ('AAC 5.1', 'aac', 6),
    ('FLAC 7.1', 'flac', 8),
  ];
  final variants = <String, AudioPlanOverrides>{
    'Auto': const AudioPlanOverrides(),
    'Disabled': const AudioPlanOverrides(passthrough: 'Disabled'),
    'Enabled DD': const AudioPlanOverrides(
      passthrough: 'Enabled',
      receiverFormats: {AudioFormat.ac3},
    ),
    'Enabled DD+DD+TrueHD': const AudioPlanOverrides(
      passthrough: 'Enabled',
      receiverFormats: {AudioFormat.ac3, AudioFormat.eac3, AudioFormat.trueHd},
    ),
    'LPCM off': const AudioPlanOverrides(multichannelLpcm: false),
    'AC3 on': const AudioPlanOverrides(
      multichannelLpcm: false,
      ac3Transcoding: true,
    ),
    'Stereo': const AudioPlanOverrides(layoutChannels: 2),
  };
  const expected = [
    [
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'bitstream:ac3:6',
      'bitstream:ac3:6',
      'stereo:pcm:2',
      'ac3Encode:ac3:6',
      'stereo:pcm:2',
    ],
    [
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'bitstream:eac3:6',
      'stereo:pcm:2',
      'ac3Encode:ac3:6',
      'stereo:pcm:2',
    ],
    [
      'bitstream:dts:6',
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'bitstream:dts:6',
      'bitstream:dts:6',
      'stereo:pcm:2',
    ],
    [
      'dtsCore:dts:6',
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'dtsCore:dts:6',
      'dtsCore:dts:6',
      'stereo:pcm:2',
    ],
    [
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'bitstream:truehd:8',
      'stereo:pcm:2',
      'ac3Encode:ac3:6',
      'stereo:pcm:2',
    ],
    [
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'bitstream:truehd:8',
      'stereo:pcm:2',
      'ac3Encode:ac3:6',
      'stereo:pcm:2',
    ],
    [
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'pcmMulti:pcm:6',
      'stereo:pcm:2',
      'ac3Encode:ac3:6',
      'stereo:pcm:2',
    ],
    [
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'pcmMulti:pcm:8',
      'stereo:pcm:2',
      'ac3Encode:ac3:6',
      'stereo:pcm:2',
    ],
  ];
  final rows = <String>[
    '# Audio plan table',
    '',
    'Detected HDMI/eARC, DTS only, 8-channel LPCM. AC3 on row disables LPCM to exercise encoding.',
    '',
    '| Codec | Settings | Expected | Got | Result |',
    '| --- | --- | --- | --- | --- |',
  ];
  test('8 codecs × 7 settings: Auto unchanged and manual overrides', () {
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final track = Track(
        id: '1',
        type: TrackType.audio,
        title: source.$1,
        codec: source.$2,
      );
      var v = 0;
      for (final entry in variants.entries) {
        final plan = planAudio(
          track,
          model,
          channels: source.$3,
          overrides: entry.value,
        );
        final got = result(plan);
        final want = expected[i][v++];
        rows.add(
          '| ${source.$1} | ${entry.key} | $want | $got | ${want == got ? 'PASS' : 'FAIL'} |',
        );
        expect(got, want, reason: '${source.$1} ${entry.key}');
        if (entry.key == 'Auto') {
          final original = planAudio(track, model, channels: source.$3);
          expect(result(plan), result(original));
          expect(plan.audioSpdif, original.audioSpdif);
          expect(plan.audioChannels, original.audioChannels);
          expect(plan.af, original.af);
          expect(plan.lost, original.lost);
          expect(plan.reason, original.reason);
        }
      }
    }
    File('../../evidence/part-02/ch02-p02/audio_plan.md')
        .writeAsStringSync('${rows.join('\n')}\n');
  });
  test(
    'Auto ignores manual receiver boxes; Disabled never bitstreams or encodes',
    () {
      const track = Track(id: '1', type: TrackType.audio, codec: 'dts');
      expect(
        result(
          planAudio(
            track,
            model,
            overrides: const AudioPlanOverrides(
              receiverFormats: {AudioFormat.ac3},
            ),
          ),
        ),
        'bitstream:dts:6',
      );
      final p = planAudio(
        track,
        model,
        overrides: const AudioPlanOverrides(
          passthrough: 'Disabled',
          multichannelLpcm: false,
          ac3Transcoding: true,
        ),
      );
      expect(result(p), 'stereo:pcm:2');
      expect(p.audioSpdif, isEmpty);
    },
  );
  test(
    'concrete service reads current overrides through unchanged contract',
    () {
      var overrides = const AudioPlanOverrides();
      final service = AudioOutputServiceImpl(
        channel: _PlanChannel(),
        planOverrides: () => overrides,
      );
      final AudioOutputService contract = service;
      const track = Track(id: '1', type: TrackType.audio, codec: 'dts');
      expect(contract.plan(track, model).step, AudioPlanStep.bitstream);
      overrides = const AudioPlanOverrides(passthrough: 'Disabled');
      expect(contract.plan(track, model).step, AudioPlanStep.pcmMulti);
      service.dispose();
    },
  );
  test(
    'explicit AC3 off stops auto encoding and carrier off drops metadata',
    () {
      final optical = AudioCapabilityModel(
        link: AudioLink.optical,
        deviceFormats: {AudioFormat.ac3},
      );
      const source = Track(
        id: '1',
        type: TrackType.audio,
        codec: 'truehd',
        title: 'Atmos',
      );
      final p = planAudio(
        source,
        optical,
        overrides: const AudioPlanOverrides(ac3Transcoding: false),
      );
      expect(p.step, AudioPlanStep.stereo);
      expect(p.lost, contains('Atmos'));
      final enabled = planAudio(
        source,
        model,
        overrides: const AudioPlanOverrides(
          passthrough: 'Enabled',
          receiverAtmos: true,
        ),
      );
      expect(enabled.step, AudioPlanStep.pcmMulti);
      expect(enabled.lost, contains('Atmos'));
    },
  );
  test('Atmos and DTS:X checkboxes do not gate their carrier codec', () {
    final receiver = AudioCapabilityModel(
      link: AudioLink.hdmiEarc,
      deviceFormats: {},
    );
    for (final source in [('truehd', 'Atmos'), ('dts-hd', 'DTS:X')]) {
      final p = planAudio(
        Track(
          id: '1',
          type: TrackType.audio,
          codec: source.$1,
          title: source.$2,
        ),
        receiver,
        overrides: const AudioPlanOverrides(
          passthrough: 'Enabled',
          receiverFormats: {AudioFormat.trueHd, AudioFormat.dtsHd},
          receiverAtmos: false,
          receiverDtsX: false,
        ),
      );
      expect(p.step, AudioPlanStep.bitstream);
      expect(p.lost, [source.$2]);
    }
  });
}
