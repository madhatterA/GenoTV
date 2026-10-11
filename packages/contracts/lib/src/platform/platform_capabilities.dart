/// Probes what this device/OS/build can actually do for playback. Provided
/// by Part 05. Consumed by Part 07 (applied around playback) and Part 04
/// (shown in settings/diagnostics).
abstract interface class PlatformCapabilities {
  /// Cached per process after the first call. Safe to call from a build
  /// method — it does not hit the OS on every call.
  Future<CapabilityReport> probe();
}

/// What the device can do, as of the last [PlatformCapabilities.probe].
///
/// [hdrOutput] `true` does NOT mean the current content will reach the
/// display in HDR — it means the *output path can accept HDR right now*.
/// Whether a given piece of content gets there depends on the content, the
/// decode path and the sink, which are not this report's job to decide.
class CapabilityReport {
  CapabilityReport({
    required this.hardwareDecode,
    required List<String> decoders,
    required this.hdrOutput,
    required List<String> hdrFormats,
    required this.displayModeSwitching,
    required this.audioPassthrough,
    required List<String> passthroughFormats,
    required Map<String, String> diagnostics,
  }) : assert(
          !hdrOutput || hdrFormats.isNotEmpty,
          'hdrFormats must be non-empty when hdrOutput is true — "HDR yes, but no format" is meaningless',
        ),
        decoders = List<String>.unmodifiable(decoders),
        hdrFormats = List<String>.unmodifiable(hdrFormats),
        passthroughFormats = List<String>.unmodifiable(passthroughFormats),
        diagnostics = Map<String, String>.unmodifiable(diagnostics);

  final bool hardwareDecode;

  /// Engine-reported, not guessed.
  final List<String> decoders;

  /// See the class doc comment: the path can accept HDR right now, not a
  /// promise for the current content.
  final bool hdrOutput;

  /// e.g. `'hdr10'`, `'hdr10plus'`, `'dolbyvision'`. Non-empty whenever
  /// [hdrOutput] is true (constructor-enforced).
  final List<String> hdrFormats;
  final bool displayModeSwitching;
  final bool audioPassthrough;

  /// e.g. `'ac3'`, `'eac3'`, `'truehd'`, `'dts'`, `'dtshd'`.
  final List<String> passthroughFormats;

  /// Traces to `research/technical/PLATFORM_PLAYBACK.md`'s "Record selected
  /// backend, codec, pixel format, HDR metadata, audio device, and fallback
  /// reason for diagnostics", refined into the keys Part 05 populates where
  /// applicable:
  /// - `backend` — playback backend in use (research note: n/a, added for
  ///   completeness)
  /// - `hwdec` — hardware decode path (research note: "codec")
  /// - `pixelFormat` — research note: "pixel format"
  /// - `colorPrimaries`, `transferFunction`, `displayMode` — research note:
  ///   "HDR metadata", decomposed into the three values that actually
  ///   describe it
  /// - `audioDevice`, `audioFormat` — research note: "audio device"
  /// - `fallbackReason` — research note: "fallback reason"
  final Map<String, String> diagnostics;
}
