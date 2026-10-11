import 'package:contracts/contracts.dart';

import 'audio_output_service_impl.dart';

const _codecName = {
  AudioFormat.ac3: 'ac3',
  AudioFormat.eac3: 'eac3',
  AudioFormat.dts: 'dts',
  AudioFormat.trueHd: 'truehd',
  AudioFormat.dtsHd: 'dts-hd',
};

/// macOS cannot tell eARC from ARC: an HDMI/DisplayPort device is taken as
/// [AudioLink.hdmiEarc] and the device's own format list does the limiting.
/// Every other kind is PCM only.
AudioLink audioLinkFor(AudioDeviceKind kind) =>
    kind == AudioDeviceKind.hdmi ? AudioLink.hdmiEarc : AudioLink.pcmOnly;

/// Reads the current output device and probes each codec through
/// [AudioOutputService.negotiate]. Failures stay visible as a PCM-only model.
Future<AudioCapabilityModel> detectAudioCapability(
  AudioOutputService service, {
  String? deviceId,
}) async {
  final devices = await service.devices();
  final selected = devices.where((d) => d.id == deviceId);
  final current = deviceId != null && deviceId != 'auto' && selected.isNotEmpty
      ? selected
      : devices.where((d) => d.isCurrent);
  final link = current.isEmpty
      ? AudioLink.pcmOnly
      : audioLinkFor(current.first.kind);
  final found = <AudioFormat>{};
  final audioTrack =
      service is AudioOutputServiceImpl && service.probesSink;
  if (audioTrack || link != AudioLink.pcmOnly) {
    for (final format in AudioFormat.values) {
      final spec = AudioStreamSpec(
        codec: _codecName[format]!,
        channels: 6,
        sampleRate: 48000,
        bitDepth: 16,
        requestedPassthrough: true,
      );
      final n = service is AudioOutputServiceImpl
          ? await service.negotiate(spec, deviceId: deviceId)
          : await service.negotiate(spec);
      if (n.passthrough) found.add(format);
    }
  }
  // AudioTrack trial results classify the encoded sink capability; this does
  // not claim the physical Android route is HDMI/eARC. PCM layout is handled
  // independently by Kodi KnownChannels in the Android plan overrides.
  return AudioCapabilityModel(
    link: audioTrack && found.isNotEmpty ? AudioLink.hdmiEarc : link,
    deviceFormats: found,
  );
}
