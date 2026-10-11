import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

AudioCapabilityModel _model(AudioLink l, [Set<AudioFormat>? device]) =>
    AudioCapabilityModel(
      link: l,
      deviceFormats: device ?? {...AudioFormat.values},
    );

const _decoders = {'ac3', 'eac3', 'dts', 'flac', 'pcm_s16le', 'aac'};

// codec, title, channels
const _tracks = <(String, String, int)>[
  ('truehd', 'TrueHD Atmos 7.1', 8),
  ('dts-hd', 'DTS-HD MA 7.1', 8),
  ('dts-hd', 'DTS:X 7.1', 8),
  ('eac3', 'E-AC3 5.1', 6),
  ('ac3', 'AC3 5.1', 6),
  ('pcm_s16le', 'PCM 7.1', 8),
  ('aac', 'AAC stereo', 2),
];

Track _t(String codec, String title) =>
    Track(id: '1', type: TrackType.audio, codec: codec, title: title);

AudioPlan _plan(String codec, String title, int ch, AudioCapabilityModel m) =>
    planAudio(_t(codec, title), m, channels: ch);

void main() {
  test('chain table over every track x link, written to the evidence file', () {
    final out = StringBuffer(
      '| track | link | step | out | ch | spdif | audio-channels | af | lost | reason |\n'
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n',
    );
    for (final (codec, title, ch) in _tracks) {
      for (final link in AudioLink.values) {
        final p = _plan(codec, title, ch, _model(link));
        out.writeln(
          '| $title | ${link.name} | ${p.step.name} | ${p.outputCodec} | ${p.channels} '
          '| ${p.audioSpdif} | ${p.audioChannels} | ${p.af} | ${p.lost.join(', ')} | ${p.reason ?? ''} |',
        );
      }
    }
    out.writeln(
      '\nEngine without a TrueHD decoder (decoders = ac3, eac3, dts, flac, pcm_s16le, aac):\n',
    );
    out.writeln('| track | link | step | reason |\n| --- | --- | --- | --- |');
    for (final link in AudioLink.values) {
      final p = planAudio(
        _t('truehd', 'TrueHD Atmos 7.1'),
        _model(link),
        channels: 8,
        decoders: _decoders,
      );
      out.writeln(
        '| TrueHD Atmos 7.1 | ${link.name} | ${p.step.name} | ${p.reason ?? ''} |',
      );
    }
    final dir = Directory('../../evidence/part-08/audio-ch01-p02')
      ..createSync(recursive: true);
    File('${dir.path}/chain_table.md').writeAsStringSync(out.toString());
  });

  test('HDMI/eARC: everything bitstreams, keeping Atmos and DTS:X', () {
    for (final (codec, title, ch) in _tracks.take(5)) {
      final p = _plan(codec, title, ch, _model(AudioLink.hdmiEarc));
      expect(p.step, AudioPlanStep.bitstream, reason: title);
      expect(p.lost, isEmpty);
    }
  });

  test('ARC: TrueHD Atmos has no multichannel PCM, so AC3 5.1 re-encode, Atmos lost', () {
    final p = _plan('truehd', 'TrueHD Atmos 7.1', 8, _model(AudioLink.arc));
    expect(p.step, AudioPlanStep.ac3Encode);
    expect(p.af, 'lavcac3enc');
    expect(p.audioChannels, '5.1');
    expect(p.lost, containsAll(['Atmos', 'channels 8->6']));
    expect(p.reason, isNotNull);
  });

  test('DTS-HD sends the DTS core when DTS-HD is not allowed; DTS:X lost', () {
    final p = _plan('dts-hd', 'DTS:X 7.1', 8, _model(AudioLink.arc));
    expect(p.step, AudioPlanStep.dtsCore);
    expect(p.audioSpdif, 'ac3,eac3,dts');
    expect(p.lost, containsAll(['DTS:X', 'lossless']));
  });

  test('E-AC3 on optical re-encodes to AC3, on ARC passes through', () {
    expect(
      _plan('eac3', 'E-AC3 5.1', 6, _model(AudioLink.arc)).step,
      AudioPlanStep.bitstream,
    );
    final p = _plan('eac3', 'E-AC3 5.1', 6, _model(AudioLink.optical));
    expect(p.step, AudioPlanStep.ac3Encode);
  });

  test(
    'multichannel PCM is capped at the link max and clamped to a layout',
    () {
      final p = _plan(
        'pcm_s16le',
        'PCM 7.1',
        8,
        _model(AudioLink.hdmiEarc, {}),
      );
      expect(p.step, AudioPlanStep.pcmMulti);
      expect(p.audioChannels, '7.1');
      expect(p.lost, isEmpty);
      expect(
        _plan('pcm_s16le', 'PCM 7.1', 8, _model(AudioLink.pcmOnly)).step,
        AudioPlanStep.stereo,
      );
    },
  );

  test('built-in speakers: stereo downmix with the loss named; stereo source loses nothing', () {
    final p = _plan('ac3', 'AC3 5.1', 6, _model(AudioLink.pcmOnly));
    expect(p.step, AudioPlanStep.stereo);
    expect(p.lost, ['channels 6->2']);
    expect(p.reason, isNotNull);
    final s = _plan('aac', 'AAC stereo', 2, _model(AudioLink.pcmOnly));
    expect(s.lost, isEmpty);
  });

  test(
    'every plan that loses anything has a reason, across the whole table',
    () {
      for (final (codec, title, ch) in _tracks) {
        for (final link in AudioLink.values) {
          final p = _plan(codec, title, ch, _model(link));
          if (p.lost.isNotEmpty) expect(p.reason, isNotNull);
        }
      }
    },
  );

  test(
    'TrueHD the engine cannot decode: bitstream on eARC, otherwise unplayable',
    () {
      final t = _t('truehd', 'TrueHD Atmos 7.1');
      expect(
        planAudio(
          t,
          _model(AudioLink.hdmiEarc),
          channels: 8,
          decoders: _decoders,
        ).step,
        AudioPlanStep.bitstream,
      );
      for (final link in [
        AudioLink.arc,
        AudioLink.optical,
        AudioLink.pcmOnly,
      ]) {
        final p = planAudio(t, _model(link), channels: 8, decoders: _decoders);
        expect(p.step, AudioPlanStep.unplayable, reason: link.name);
        expect(p.reason, "TrueHD can't be decoded on this player build");
        expect(p.lost, isNotEmpty);
      }
      // unknown decoder list keeps the old behaviour
      expect(
        planAudio(t, _model(AudioLink.arc), channels: 8).step,
        AudioPlanStep.ac3Encode,
      );
    },
  );

  test(
    'DTS-HD with a dts decoder still plays; decodable codecs are unaffected',
    () {
      expect(
        planAudio(
          _t('dts-hd', 'DTS-HD MA'),
          _model(AudioLink.pcmOnly),
          channels: 8,
          decoders: _decoders,
        ).step,
        AudioPlanStep.stereo,
      );
      expect(
        planAudio(
          _t('aac', 'AAC'),
          _model(AudioLink.arc),
          channels: 2,
          decoders: _decoders,
        ).step,
        AudioPlanStep.stereo,
      );
    },
  );
}
