import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

import 'package:video_player/platform_policy.dart';

void main() {
  test('starts in order and stops in reverse lease order', () async {
    final harness = _PolicyHarness(enableOptional: true);

    await harness.policy.start(
      controller: harness.controller,
      contentFps: 24,
      audioSpec: _audioSpec,
    );
    expect(harness.order, <String>['probe', 'display', 'audio', 'keepAwake']);
    expect(harness.diagnostics.snapshot['displayMode'], 'leased');
    expect(harness.diagnostics.snapshot['passthrough'], 'granted');

    await harness.policy.stop();
    expect(harness.order, <String>[
      'probe',
      'display',
      'audio',
      'keepAwake',
      'releaseKeepAwake',
      'releaseDisplay',
      'clearMedia',
    ]);
    await harness.policy.stop();
    expect(harness.order, hasLength(7));
    await harness.dispose();
  });

  test(
    'failure at each acquisition step cleans up already-acquired leases',
    () async {
      for (final failure in <String>['display', 'audio', 'keepAwake']) {
        final harness = _PolicyHarness(failure: failure, enableOptional: true);

        await expectLater(
          harness.policy.start(
            controller: harness.controller,
            contentFps: 24,
            audioSpec: _audioSpec,
          ),
          throwsA(isA<StateError>()),
        );
        expect(harness.order, contains('clearMedia'));
        if (failure != 'display') {
          expect(harness.order, contains('releaseDisplay'));
        }
        expect(harness.order, isNot(contains('releaseKeepAwake')));
        await harness.dispose();
      }
    },
  );

  test(
    'interruption and media commands control the active controller',
    () async {
      final harness = _PolicyHarness();
      await harness.policy.start(controller: harness.controller);
      harness.controller.setPlaying(true);

      harness.events.add(
        const PlatformEvent(
          PlatformEventType.audioInterruptionBegan,
          <String, Object?>{'lossKind': 'transient', 'shouldResume': true},
        ),
      );
      await pumpEventQueue();
      expect(harness.controller.pauseCalls, 1);
      harness.events.add(
        const PlatformEvent(
          PlatformEventType.audioInterruptionEnded,
          <String, Object?>{'shouldResume': true},
        ),
      );
      await pumpEventQueue();
      expect(harness.controller.playCalls, 1);

      harness.mediaCommands.add(
        const MediaSessionCommand(
          MediaSessionCommandType.seekTo,
          position: Duration(seconds: 4),
        ),
      );
      await pumpEventQueue();
      expect(harness.controller.seekCalls, <Duration>[
        const Duration(seconds: 4),
      ]);
      await harness.policy.stop();
      harness.events.add(
        const PlatformEvent(PlatformEventType.appBackgrounded, {}),
      );
      await pumpEventQueue();
      expect(harness.controller.pauseCalls, 1);
      await harness.dispose();
    },
  );

  test(
    'policy switches default off without requesting optional capabilities',
    () async {
      final harness = _PolicyHarness();
      await harness.policy.start(
        controller: harness.controller,
        contentFps: 24,
        audioSpec: _audioSpec,
      );
      expect(harness.displayCalls, 0);
      expect(harness.audioCalls, 0);
      expect(harness.diagnostics.snapshot['displayMode'], 'disabled');
      expect(harness.diagnostics.snapshot['passthrough'], 'disabled');
      await harness.dispose();
    },
  );

  test(
    'start is rejected while active and can be used again after stop',
    () async {
      final harness = _PolicyHarness();
      await harness.policy.start(controller: harness.controller);
      await expectLater(
        harness.policy.start(controller: harness.controller),
        throwsA(isA<StateError>()),
      );
      await harness.policy.stop();
      await harness.policy.start(controller: harness.controller);
      await harness.policy.stop();
      await harness.dispose();
    },
  );
}

final _audioSpec = AudioStreamSpec(
  codec: 'aac',
  channels: 2,
  sampleRate: 48000,
  bitDepth: 16,
  requestedPassthrough: true,
);

final class _PolicyHarness {
  _PolicyHarness({this.failure, this.enableOptional = false}) {
    final report = CapabilityReport(
      hardwareDecode: true,
      decoders: const ['h264'],
      hdrOutput: false,
      hdrFormats: const [],
      displayModeSwitching: true,
      audioPassthrough: true,
      passthroughFormats: const ['aac'],
      diagnostics: const {},
    );
    capabilities = _Capabilities(report, order, failure == 'probe');
    display = _Display(order, failure == 'display');
    audio = _Audio(order, failure == 'audio');
    events = StreamController<PlatformEvent>.broadcast();
    mediaCommands = StreamController<MediaSessionCommand>.broadcast();
    controller = _Controller();
    diagnostics = DiagnosticsCollector(os: 'test', appVersion: 'test');
    policy = PlatformPolicy(
      capabilities: capabilities,
      displayModes: display,
      audio: audio,
      events: events.stream,
      mediaCommands: mediaCommands.stream,
      acquireKeepAwake: () async {
        order.add('keepAwake');
        if (failure == 'keepAwake') throw StateError('keep awake');
        return () async => order.add('releaseKeepAwake');
      },
      clearMediaSession: () async => order.add('clearMedia'),
      diagnostics: diagnostics,
      displayModeMatchingEnabled: enableOptional,
      passthroughEnabled: enableOptional,
    );
  }

  final String? failure;
  final bool enableOptional;
  final order = <String>[];
  late final _Capabilities capabilities;
  late final _Display display;
  late final _Audio audio;
  late final StreamController<PlatformEvent> events;
  late final StreamController<MediaSessionCommand> mediaCommands;
  late final _Controller controller;
  late final DiagnosticsCollector diagnostics;
  late final PlatformPolicy policy;

  int get displayCalls => display.calls;
  int get audioCalls => audio.calls;

  Future<void> dispose() async {
    await policy.stop();
    await events.close();
    await mediaCommands.close();
    await controller.dispose();
  }
}

final class _Capabilities implements PlatformCapabilities {
  _Capabilities(this.report, this.order, this.fail);
  final CapabilityReport report;
  final List<String> order;
  final bool fail;

  @override
  Future<CapabilityReport> probe() async {
    order.add('probe');
    if (fail) throw StateError('probe');
    return report;
  }
}

final class _Display implements DisplayModeService {
  _Display(this.order, this.fail);
  final List<String> order;
  final bool fail;
  int calls = 0;

  @override
  Future<List<DisplayMode>> availableModes() async => const [];

  @override
  Future<DisplayModeLease?> matchFor({
    required double contentFps,
    int? width,
    int? height,
  }) async {
    calls++;
    order.add('display');
    if (fail) throw StateError('display');
    return _Lease(order);
  }
}

final class _Audio implements AudioOutputService {
  _Audio(this.order, this.fail);
  final List<String> order;
  final bool fail;
  int calls = 0;

  @override
  Future<List<AudioDevice>> devices() async => const [];

  @override
  AudioPlan plan(
    Track track,
    AudioCapabilityModel model, {
    int? channels,
    Set<String>? decoders,
  }) => throw UnimplementedError();

  @override
  Future<AudioNegotiation> negotiate(AudioStreamSpec spec) async {
    calls++;
    order.add('audio');
    if (fail) throw StateError('audio');
    return AudioNegotiation(
      passthrough: true,
      requestedPassthrough: spec.requestedPassthrough,
      deviceId: 'test',
    );
  }
}

final class _Lease implements DisplayModeLease {
  _Lease(this.order);
  final List<String> order;
  bool released = false;

  @override
  Future<void> release() async {
    if (released) return;
    released = true;
    order.add('releaseDisplay');
  }
}

final class _Controller implements PlaybackController {
  final _states = StreamController<PlaybackState>.broadcast();
  final _events = StreamController<PlaybackEvent>.broadcast();
  PlaybackState _state = PlaybackState.initial();
  int playCalls = 0;
  int pauseCalls = 0;
  final seekCalls = <Duration>[];

  void setPlaying(bool value) {
    _state = _state.copyWith(isPlaying: value);
    _states.add(_state);
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get state => _states.stream;

  @override
  Stream<MediaInfo> get mediaInfo => const Stream<MediaInfo>.empty();

  @override
  Stream<PlaybackEvent> get events => _events.stream;

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {}

  @override
  Future<void> play() async {
    playCalls++;
    setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    setPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async => seekCalls.add(position);

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  final recordedSubtitleDelays = <Duration>[];
  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    recordedSubtitleDelays.add(delay);
  }

  final recordedAudioDelays = <Duration>[];
  @override
  Future<void> setAudioDelay(Duration delay) async {
    recordedAudioDelays.add(delay);
  }

  final recordedSubtitleScales = <double>[];
  @override
  Future<void> setSubtitleScale(double scale) async {
    recordedSubtitleScales.add(scale);
  }

  final recordedSubtitlePositions = <int>[];
  @override
  Future<void> setSubtitlePosition(int percent) async {
    recordedSubtitlePositions.add(percent);
  }

  final recordedAspectRatios = <String?>[];
  @override
  Future<void> setAspectRatio(String? ratio) async {
    recordedAspectRatios.add(ratio);
  }

  final recordedAudioOutput = <AudioPlan>[];
  @override
  Future<void> setAudioOutput(AudioPlan plan) async {
    recordedAudioOutput.add(plan);
  }

  final recordedFillScreen = <bool>[];
  @override
  Future<void> setEngineOptions(Map<String, String> options) async {}

  @override
  Future<Map<String, String>> applyUserOptions(
    Map<String, String> options,
  ) async => const {};

  @override
  Stream<Map<String, String>> get diagnostics => const Stream.empty();

  @override
  Future<void> setFillScreen(bool enabled) async {
    recordedFillScreen.add(enabled);
  }

  @override
  Future<void> selectTrack(TrackSelection selection) async {}

  @override
  Future<void> addExternalSubtitle(Uri uri, {String? title}) async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _events.close();
  }
}
