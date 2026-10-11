import 'package:contracts/contracts.dart';

const _names = {
  'truehd': 'TrueHD',
  'dts-hd': 'DTS-HD',
  'dtshd': 'DTS-HD',
  'eac3': 'E-AC3',
};

String _layout(int channels) =>
    channels >= 8 ? '7.1' : (channels >= 6 ? '5.1' : 'Stereo');

/// One short plain line for the player's Info tab, e.g. `AC3 5.1 · Passthrough`,
/// `TrueHD → PCM 5.1`, `TrueHD · Can't play on this device`.
String audioOutputLine(Track track, AudioPlan plan) {
  final codec = (track.codec ?? '').toLowerCase();
  final title = (track.title ?? '').toLowerCase();
  final source = [
    _names[codec] ?? codec.toUpperCase(),
    if (title.contains('atmos')) 'Atmos',
    if (title.contains('dts:x') || title.contains('dts-x')) 'DTS:X',
  ].join(' ');
  final lossless = codec == 'truehd' || codec.startsWith('dts-hd');
  final metadata = plan.lost
      .where((loss) => loss == 'Atmos' || loss == 'DTS:X')
      .toList();
  if (plan.step == AudioPlanStep.bitstream && metadata.isNotEmpty) {
    return '${metadata.join(', ')} not supported by receiver — plays as '
        '${_names[codec] ?? codec.toUpperCase()} ${_layout(plan.channels)} · Passthrough';
  }
  final line = switch (plan.step) {
    AudioPlanStep.unplayable => "$source · Can't play on this device",
    AudioPlanStep.bitstream =>
      '${lossless ? source : '$source ${_layout(plan.channels)}'} · Passthrough',
    AudioPlanStep.stereo => '$source → Stereo',
    AudioPlanStep.pcmMulti => '$source → PCM ${_layout(plan.channels)}',
    AudioPlanStep.ac3Encode =>
      '$source → Dolby Digital ${_layout(plan.channels)}',
    AudioPlanStep.dtsCore => '$source → DTS ${_layout(plan.channels)}',
  };
  return metadata.isEmpty ? line : '$line · Lost ${metadata.join(', ')}';
}
