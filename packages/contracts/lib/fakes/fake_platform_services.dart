import 'package:contracts/contracts.dart';

/// Controllable [PlatformCapabilities] fake. Returns the same report
/// instance until [setReport] replaces it — caching per process for free.
class FakePlatformCapabilities implements PlatformCapabilities {
  FakePlatformCapabilities({CapabilityReport? report}) : _report = report ?? _defaultReport();

  CapabilityReport _report;
  int probeCallCount = 0;

  static CapabilityReport _defaultReport() => CapabilityReport(
        hardwareDecode: true,
        decoders: const <String>['h264'],
        hdrOutput: false,
        hdrFormats: const <String>[],
        displayModeSwitching: false,
        audioPassthrough: false,
        passthroughFormats: const <String>[],
        diagnostics: const <String, String>{},
      );

  void setReport(CapabilityReport report) => _report = report;

  @override
  Future<CapabilityReport> probe() async {
    probeCallCount++;
    return _report;
  }
}

/// Records [release] calls so a test can assert the restore obligation was
/// honoured (`planning/CONTRACTS.md` §5 "the lease MUST restore the
/// previous mode on release()").
class FakeDisplayModeLease implements DisplayModeLease {
  int releaseCallCount = 0;
  bool get released => releaseCallCount > 0;

  @override
  Future<void> release() async {
    releaseCallCount++;
  }
}

/// Controllable [DisplayModeService] fake.
class FakeDisplayModeService implements DisplayModeService {
  FakeDisplayModeService({List<DisplayMode>? modes}) : _modes = modes ?? const <DisplayMode>[];

  List<DisplayMode> _modes;

  /// The lease handed out by the most recent [matchFor] call, if any.
  FakeDisplayModeLease? lastLease;

  void setModes(List<DisplayMode> modes) => _modes = modes;

  @override
  Future<List<DisplayMode>> availableModes() async => List.unmodifiable(_modes);

  @override
  Future<DisplayModeLease?> matchFor({required double contentFps, int? width, int? height}) async {
    if (_modes.isEmpty) return null;
    final lease = FakeDisplayModeLease();
    lastLease = lease;
    return lease;
  }
}

/// Controllable [AudioOutputService] fake. Grants passthrough unless told
/// to downgrade it, in which case it always populates [AudioNegotiation.
/// fallbackReason] — a silent downgrade is impossible to represent
/// regardless of what the fake is told to do.
class FakeAudioOutputService implements AudioOutputService {
  FakeAudioOutputService({List<AudioDevice>? devices})
      : _devices = devices ?? <AudioDevice>[AudioDevice(id: 'default', name: 'Default')];

  List<AudioDevice> _devices;

  /// Non-null forces every requested-passthrough negotiation to downgrade
  /// with this reason. Null (the default) grants what was requested.
  String? forcedFallbackReason;

  /// Non-null is returned by every [plan] call; null plans a plain bitstream.
  AudioPlan? forcedPlan;

  void setDevices(List<AudioDevice> devices) => _devices = devices;

  @override
  Future<List<AudioDevice>> devices() async => List.unmodifiable(_devices);

  @override
  Future<AudioNegotiation> negotiate(AudioStreamSpec spec) async {
    final downgrade = spec.requestedPassthrough && forcedFallbackReason != null;
    final granted = spec.requestedPassthrough && !downgrade;
    return AudioNegotiation(
      passthrough: granted,
      requestedPassthrough: spec.requestedPassthrough,
      fallbackReason: downgrade ? forcedFallbackReason : null,
      deviceId: _devices.isNotEmpty ? _devices.first.id : 'none',
    );
  }

  @override
  AudioPlan plan(Track track, AudioCapabilityModel model, {int? channels, Set<String>? decoders}) =>
      forcedPlan ??
      AudioPlan(
        step: AudioPlanStep.bitstream,
        outputCodec: track.codec ?? 'unknown',
        channels: channels ?? 2,
        audioSpdif: track.codec ?? '',
        audioChannels: 'auto-safe',
      );
}
