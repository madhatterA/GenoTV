import 'package:flutter/foundation.dart';

import '../playback/track.dart';
import 'audio_plan.dart';

/// Coarse output category; [unknown] when the platform gives no reliable signal.
enum AudioDeviceKind { speaker, headphones, hdmi, bluetooth, usb, unknown }

/// One audio output device.
class AudioDevice {
  AudioDevice({
    required this.id,
    required this.name,
    this.kind = AudioDeviceKind.unknown,
    this.isCurrent = false,
    List<int> supportedSampleRates = const [],
  }) : supportedSampleRates = List.unmodifiable(supportedSampleRates);

  final String id;
  final String name;
  final AudioDeviceKind kind;

  /// True for the output the OS is currently routing to.
  final bool isCurrent;

  /// Supported nominal sample rates in Hz. Empty means unknown, not unsupported.
  /// Optimized output uses Best Match when this capability is unknown.
  final List<int> supportedSampleRates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AudioDevice &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.isCurrent == isCurrent &&
          listEquals(other.supportedSampleRates, supportedSampleRates));

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    isCurrent,
    Object.hashAll(supportedSampleRates),
  );
}

/// The stream to be played — only what negotiation needs, nothing more.
/// [requestedPassthrough] lives here (not on [AudioNegotiation]) so the
/// silent-downgrade invariant on [AudioNegotiation] is actually checkable.
class AudioStreamSpec {
  const AudioStreamSpec({
    required this.codec,
    required this.channels,
    required this.sampleRate,
    required this.bitDepth,
    required this.requestedPassthrough,
  });

  final String codec;
  final int channels;
  final int sampleRate;
  final int bitDepth;
  final bool requestedPassthrough;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AudioStreamSpec &&
          other.codec == codec &&
          other.channels == channels &&
          other.sampleRate == sampleRate &&
          other.bitDepth == bitDepth &&
          other.requestedPassthrough == requestedPassthrough);

  @override
  int get hashCode =>
      Object.hash(codec, channels, sampleRate, bitDepth, requestedPassthrough);
}

/// The outcome of negotiating an [AudioStreamSpec] against a device.
///
/// A silent passthrough downgrade is impossible to represent: whenever the
/// spec requested passthrough and [passthrough] came back false,
/// [fallbackReason] MUST be non-null (constructor-enforced) — modelling
/// passthrough as a bare bool loses the reason, so it is a bool plus a
/// reason, always.
class AudioNegotiation {
  AudioNegotiation({
    required this.passthrough,
    required bool requestedPassthrough,
    this.fallbackReason,
    required this.deviceId,
  }) : assert(
          !(requestedPassthrough && !passthrough) || fallbackReason != null,
          'fallbackReason must be non-null when passthrough was requested and not granted',
        );

  /// `false` means the stream is decoded locally.
  final bool passthrough;

  /// Non-null whenever the request was downgraded.
  final String? fallbackReason;
  final String deviceId;
}

abstract interface class AudioOutputService {
  Future<List<AudioDevice>> devices();
  Future<AudioNegotiation> negotiate(AudioStreamSpec spec);

  /// Fallback-chain step for [track] on [model]. [channels] is the source
  /// channel count when the caller knows it. [decoders] are the codec names the
  /// engine can decode (mpv `decoder-list`); null means unknown, so nothing is
  /// declared unplayable.
  AudioPlan plan(Track track, AudioCapabilityModel model, {int? channels, Set<String>? decoders});
}
