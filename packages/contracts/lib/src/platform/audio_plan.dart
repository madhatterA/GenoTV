/// Physical link carrying audio to the sink.
enum AudioLink { hdmiEarc, arc, optical, pcmOnly }

/// Bitstream codec families. Atmos / DTS:X are not codecs: they ride inside
/// [trueHd] / [eac3] and [dtsHd] and are covered by those entries.
enum AudioFormat { ac3, eac3, dts, trueHd, dtsHd }

/// What a link can carry (SOURCE_2026-09-30 §3).
const Map<AudioLink, ({Set<AudioFormat> formats, int maxPcmChannels})>
linkRules = {
  AudioLink.hdmiEarc: (formats: {...AudioFormat.values}, maxPcmChannels: 8),
  AudioLink.arc: (
    formats: {AudioFormat.ac3, AudioFormat.eac3, AudioFormat.dts},
    maxPcmChannels: 2,
  ),
  AudioLink.optical: (
    formats: {AudioFormat.ac3, AudioFormat.dts},
    maxPcmChannels: 2,
  ),
  AudioLink.pcmOnly: (formats: <AudioFormat>{}, maxPcmChannels: 2),
};

/// What the current output can take: the link's limits intersected with the
/// formats the device reports it accepts. Filled automatically from the
/// detected device; never edited by the viewer.
final class AudioCapabilityModel {
  AudioCapabilityModel({
    required this.link,
    required Set<AudioFormat> deviceFormats,
  }) : formats = Set.unmodifiable(
         deviceFormats.intersection(linkRules[link]!.formats),
       );

  final AudioLink link;
  final Set<AudioFormat> formats;
  int get maxPcmChannels => linkRules[link]!.maxPcmChannels;
}

/// Which step of the §3 fallback chain a stream plays at. [unplayable]: the
/// track's codec can neither be sent as a bitstream nor decoded by the engine;
/// [AudioPlan.reason] says why and the caller should pick another track.
enum AudioPlanStep { bitstream, dtsCore, pcmMulti, ac3Encode, stereo, unplayable }

/// How one audio track will be output, and what that costs. The mpv option
/// values are ready to apply as-is.
///
/// A silent loss is impossible to represent: [lost] non-empty requires
/// [reason] (constructor-enforced), same idea as `AudioNegotiation`.
class AudioPlan {
  AudioPlan({
    required this.step,
    required this.outputCodec,
    required this.channels,
    this.lost = const <String>[],
    this.reason,
    required this.audioSpdif,
    required this.audioChannels,
    this.af = '',
  }) : assert(
         lost.isEmpty || reason != null,
         'reason must be set when anything is lost',
       );

  final AudioPlanStep step;

  /// Codec leaving the app: the bitstream codec, or `pcm` / `ac3`.
  final String outputCodec;
  final int channels;

  /// e.g. `Atmos`, `DTS:X`, `lossless`, `channels 8->2`.
  final List<String> lost;

  /// Non-null whenever [step] is not [AudioPlanStep.bitstream] and something was lost.
  final String? reason;

  /// mpv `audio-spdif` (comma-separated codecs, may be empty).
  final String audioSpdif;

  /// mpv `audio-channels`.
  final String audioChannels;

  /// mpv `af` (may be empty).
  final String af;
}
