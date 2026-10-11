import 'dart:async';

import 'package:contracts/contracts.dart';

import '../channel/platform_channel.dart';
import 'fallback_chain.dart';

final class AudioOutputServiceImpl implements AudioOutputService {
  AudioOutputServiceImpl({
    required this.channel,
    this.onRouteChanged,
    this.planOverrides,
    this.outputDeviceId,
    this.passthroughDevice,
    this.exclusiveAudio,
  }) {
    _eventsSubscription = channel.events.listen(_handleEvent);
  }

  final PlatformChannel channel;
  final void Function()? onRouteChanged;
  final AudioPlanOverrides Function()? planOverrides;
  final String Function()? outputDeviceId;
  final String Function()? passthroughDevice;

  /// Windows only: whether `audio.exclusiveMode` is on. Decides which PCM
  /// channel maximum the platform reports (exclusive probe vs mixer layout).
  final bool Function()? exclusiveAudio;
  late final StreamSubscription<Object?> _eventsSubscription;
  String? _diagnostic;
  final List<String> _negotiationLog = [];
  int _routeGeneration = 0;
  bool _disposed = false;

  String? get diagnostic => _diagnostic;

  /// One line per negotiation: requested format, result, reason, device.
  List<String> get negotiationLog => List.unmodifiable(_negotiationLog);

  AudioNegotiation _record(AudioStreamSpec spec, AudioNegotiation n) {
    _negotiationLog.add(
      '${spec.codec} ${spec.channels}ch ${spec.sampleRate}Hz -> '
      'passthrough=${n.passthrough} reason=${n.fallbackReason ?? '-'} device=${n.deviceId}',
    );
    return n;
  }

  int get routeGeneration => _routeGeneration;

  bool _usesAudioTrack = false;
  bool get usesAudioTrack => _usesAudioTrack;

  /// Android and Windows classify passthrough by probing the sink itself.
  bool _probesSink = false;
  bool get probesSink => _probesSink;

  /// Windows: the endpoint Kodi would open for passthrough (null when none).
  String? _passthroughDeviceId;
  String? get passthroughDeviceId => _passthroughDeviceId;

  /// iOS AVAudioSession `maximumOutputNumberOfChannels` of the current route;
  /// null until the platform reports it. Refreshed by every route change.
  int? _maxOutputChannels;
  int? get maxOutputChannels => _maxOutputChannels;

  @override
  Future<List<AudioDevice>> devices({String? passthroughDeviceId}) async {
    if (_disposed) return const [];
    try {
      final exclusive = exclusiveAudio;
      final raw = asMap(
        await channel.invoke(
          PlatformMethods.audioDevices,
          exclusive == null
              ? null
              : {
                  'exclusive': exclusive(),
                  'deviceId': outputDeviceId?.call() ?? 'auto',
                  'passthroughDeviceId':
                      passthroughDeviceId ??
                      passthroughDevice?.call() ??
                      'auto',
                },
        ),
      );
      _usesAudioTrack = raw['os'] == 'android';
      _probesSink = _usesAudioTrack || raw['os'] == 'windows';
      _passthroughDeviceId = stringValue(raw['passthroughDeviceId']);
      _maxOutputChannels = intValue(raw['maxOutputChannels']);
      final values = raw['devices'] is List ? raw['devices'] as List : const [];
      final result = values
          .map(_parseDevice)
          .whereType<AudioDevice>()
          .toList(growable: false);
      _diagnostic = result.isEmpty && raw['supported'] == false
          ? stringValue(raw['reason']) ?? 'platform.unsupported: audio devices'
          : stringValue(raw['diagnostic']);
      return result;
    } catch (error) {
      _diagnostic = 'platform.unsupported: audio device enumeration';
      return const [];
    }
  }

  @override
  AudioPlan plan(
    Track track,
    AudioCapabilityModel model, {
    int? channels,
    Set<String>? decoders,
  }) => planAudio(
    track,
    model,
    channels: channels,
    decoders: decoders,
    overrides: planOverrides?.call() ?? const AudioPlanOverrides(),
  );

  @override
  Future<AudioNegotiation> negotiate(
    AudioStreamSpec spec, {
    String? deviceId,
  }) async => _record(spec, await _negotiate(spec, deviceId: deviceId));

  Future<AudioNegotiation> _negotiate(
    AudioStreamSpec spec, {
    String? deviceId,
  }) async {
    if (_disposed) {
      return AudioNegotiation(
        passthrough: false,
        requestedPassthrough: spec.requestedPassthrough,
        fallbackReason: spec.requestedPassthrough
            ? 'audio service is disposed'
            : null,
        deviceId: 'unknown',
      );
    }
    final generation = _routeGeneration;
    try {
      final raw = asMap(
        await channel.invoke(PlatformMethods.audioNegotiate, {
          'deviceId': deviceId ?? outputDeviceId?.call() ?? 'auto',
          'codec': spec.codec,
          'channels': spec.channels,
          'sampleRate': spec.sampleRate,
          'bitDepth': spec.bitDepth,
          'requestedPassthrough': spec.requestedPassthrough,
        }),
      );
      final passthrough =
          boolValue(raw['passthrough']) && spec.requestedPassthrough;
      final reason =
          stringValue(raw['fallbackReason']) ??
          (spec.requestedPassthrough && !passthrough
              ? 'sink did not report ${spec.codec} support'
              : null);
      // A route event during the query makes the answer stale; make that visible.
      final staleReason = generation == _routeGeneration
          ? reason
          : 'audio route changed during negotiation';
      return AudioNegotiation(
        passthrough: passthrough,
        requestedPassthrough: spec.requestedPassthrough,
        fallbackReason: staleReason,
        deviceId: stringValue(raw['deviceId']) ?? 'unknown',
      );
    } catch (error) {
      return AudioNegotiation(
        passthrough: false,
        requestedPassthrough: spec.requestedPassthrough,
        fallbackReason: spec.requestedPassthrough
            ? 'audio negotiation failed: ${error.runtimeType}'
            : null,
        deviceId: 'unknown',
      );
    }
  }

  void _handleEvent(Object? event) {
    if (_disposed) return;
    final map = asMap(event);
    final name =
        stringValue(map['event']) ??
        stringValue(map['type']) ??
        stringValue(map['name']);
    if (name == 'audioRouteChanged' ||
        name == 'audio.route.changed' ||
        name == 'routeChanged') {
      _routeGeneration++;
      _maxOutputChannels = intValue(map['maxOutputChannels']);
      onRouteChanged?.call();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _eventsSubscription.cancel();
  }

  static AudioDevice? _parseDevice(Object? raw) {
    final map = asMap(raw);
    final id = stringValue(map['id']);
    final name = stringValue(map['name']);
    if (id == null || name == null) return null;
    final kind =
        AudioDeviceKind.values.asNameMap()[stringValue(map['kind'])] ??
        AudioDeviceKind.unknown;
    final rates = map['supportedSampleRates'];
    return AudioDevice(
      id: id,
      name: name,
      kind: kind,
      isCurrent: boolValue(map['isCurrent']),
      supportedSampleRates: rates is List
          ? rates.whereType<int>().where((rate) => rate > 0).toSet().toList()
          : const [],
    );
  }
}
