import 'package:contracts/contracts.dart';

const _formatOf = {
  'ac3': AudioFormat.ac3,
  'eac3': AudioFormat.eac3,
  'dts': AudioFormat.dts,
  'truehd': AudioFormat.trueHd,
  'dts-hd': AudioFormat.dtsHd,
  'dtshd': AudioFormat.dtsHd,
};

const _spdifName = {
  AudioFormat.ac3: 'ac3',
  AudioFormat.eac3: 'eac3',
  AudioFormat.dts: 'dts',
  AudioFormat.trueHd: 'truehd',
  AudioFormat.dtsHd: 'dts-hd',
};

String _layout(int channels) =>
    channels >= 8 ? '7.1' : (channels >= 6 ? '5.1' : 'stereo');

int _layoutChannels(int channels) =>
    channels >= 8 ? 8 : (channels >= 6 ? 6 : 2);

/// SOURCE_2026-09-30 §3 chain: bitstream, DTS core, multichannel PCM up to
/// the link max, AC3 5.1 re-encode, stereo. [channels] null means the
/// codec's usual layout (8 for TrueHD / DTS-HD, otherwise 6).
///
/// [decoders] are the codec names the engine can decode (mpv `decoder-list`);
/// a codec that is neither bitstreamable nor in it is
/// [AudioPlanStep.unplayable]. Null means unknown and plans as before.
/// Manual settings feed the existing fallback chain; null preserves detection.
final class AudioPlanOverrides {
  const AudioPlanOverrides({
    this.passthrough = 'Auto',
    this.receiverFormats = const {},
    this.multichannelLpcm,
    this.ac3Transcoding,
    this.layoutChannels,
    this.receiverAtmos = true,
    this.receiverDtsX = true,
    this.restrictToSinkFormats = false,
    this.pcmChannelLimit,
  });

  final String passthrough;
  final Set<AudioFormat> receiverFormats;
  final bool? multichannelLpcm;
  final bool? ac3Transcoding;
  final int? layoutChannels;
  final bool receiverAtmos;
  final bool receiverDtsX;

  /// AudioTrack capabilities are trial results, never overridden by user ticks.
  final bool restrictToSinkFormats;

  /// Kodi AudioTrack KnownChannels; the sink resolves mask support at open.
  final int? pcmChannelLimit;
}

AudioPlan planAudio(
  Track track,
  AudioCapabilityModel model, {
  int? channels,
  Set<String>? decoders,
  AudioPlanOverrides overrides = const AudioPlanOverrides(),
  AudioCapabilityModel? pcmModel,
}) {
  final formats = overrides.passthrough == 'Disabled'
      ? <AudioFormat>{}
      : overrides.passthrough == 'Enabled'
      ? (overrides.restrictToSinkFormats
            ? overrides.receiverFormats.intersection(model.formats)
            : overrides.receiverFormats)
      : overrides.restrictToSinkFormats
      ? model.formats.intersection(overrides.receiverFormats)
      : model.formats;
  final layout = overrides.layoutChannels;
  final allowBitstream =
      overrides.restrictToSinkFormats || layout == null || layout > 2;
  final codec = (track.codec ?? '').toLowerCase();
  final format = _formatOf[codec];
  final title = (track.title ?? '').toLowerCase();
  final src =
      channels ??
      (format == AudioFormat.trueHd || format == AudioFormat.dtsHd ? 8 : 6);
  final extras = <String>[
    if (title.contains('atmos')) 'Atmos',
    if (title.contains('dts:x') || title.contains('dts-x')) 'DTS:X',
  ];
  final spdif = ([
    if (allowBitstream) ...formats,
  ]..sort((a, b) => a.index - b.index)).map((f) => _spdifName[f]!).join(',');
  final label = format == null ? codec : _spdifName[format]!;

  AudioPlan plan(
    AudioPlanStep step,
    String out,
    int ch,
    List<String> lost,
    String? reason, {
    String af = '',
  }) => AudioPlan(
    step: step,
    outputCodec: out,
    channels: ch,
    lost: lost,
    reason: reason,
    audioSpdif: spdif,
    audioChannels: _layout(ch),
    af: af,
  );

  if (allowBitstream && format != null && formats.contains(format)) {
    return AudioPlan(
      step: AudioPlanStep.bitstream,
      outputCodec: _spdifName[format]!,
      channels: src,
      audioSpdif: spdif,
      audioChannels: 'auto-safe',
      reason:
          overrides.passthrough == 'Enabled' &&
              ((!overrides.receiverAtmos && extras.contains('Atmos')) ||
                  (!overrides.receiverDtsX && extras.contains('DTS:X')))
          ? 'receiver does not support object metadata'
          : null,
      lost: [
        if (overrides.passthrough == 'Enabled' &&
            !overrides.receiverAtmos &&
            extras.contains('Atmos'))
          'Atmos',
        if (overrides.passthrough == 'Enabled' &&
            !overrides.receiverDtsX &&
            extras.contains('DTS:X'))
          'DTS:X',
      ],
    );
  }
  final why = format == null
      ? null
      : '$label not accepted by the ${model.link.name} output';
  if (allowBitstream &&
      format == AudioFormat.dtsHd &&
      formats.contains(AudioFormat.dts)) {
    return plan(AudioPlanStep.dtsCore, 'dts', 6, [...extras, 'lossless'], why);
  }
  final decodeName = (codec == 'dts-hd' || codec == 'dtshd') ? 'dts' : codec;
  if (decoders != null && !decoders.contains(decodeName)) {
    return AudioPlan(
      step: AudioPlanStep.unplayable,
      outputCodec: '',
      channels: 0,
      lost: const ['playback'],
      reason:
          "${format == AudioFormat.trueHd ? 'TrueHD' : label} can't be decoded on this player build",
      audioSpdif: spdif,
      audioChannels: 'auto-safe',
    );
  }
  final pcmMax =
      overrides.pcmChannelLimit ?? (pcmModel ?? model).maxPcmChannels;
  final max = overrides.multichannelLpcm == false
      ? 2
      : layout != null && layout < pcmMax
      ? layout
      : pcmMax;
  if (max > 2 && src > 2) {
    final ch = _layoutChannels(src < max ? src : max);
    final lost = [...extras, if (src > ch) 'channels $src->$ch'];
    return plan(
      AudioPlanStep.pcmMulti,
      'pcm',
      ch,
      lost,
      why ?? (lost.isEmpty ? null : 'output limits channels to $max'),
    );
  }
  if (allowBitstream &&
      overrides.passthrough != 'Disabled' &&
      src > 2 &&
      (!overrides.restrictToSinkFormats || formats.contains(AudioFormat.ac3)) &&
      (overrides.ac3Transcoding ?? formats.contains(AudioFormat.ac3))) {
    return plan(
      AudioPlanStep.ac3Encode,
      'ac3',
      6,
      [...extras, 'lossless', if (src > 6) 'channels $src->6'],
      why ?? 'output cannot take $src channels',
      af: 'lavcac3enc',
    );
  }
  return plan(AudioPlanStep.stereo, 'pcm', 2, [
    ...extras,
    if (src > 2) 'channels $src->2',
  ], src > 2 ? (why ?? 'output is stereo only') : why);
}
