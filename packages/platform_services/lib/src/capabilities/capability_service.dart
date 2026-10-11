import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../channel/platform_channel.dart';
import '../channel/platform_dispatch.dart';

/// A capability probe backed by one channel call and a process-local cache.
final class PlatformCapabilitiesService implements PlatformCapabilities {
  PlatformCapabilitiesService({
    required this.channel,
    this.logger,
    this.passthroughDeviceId,
    this.outputDeviceId,
  }) {
    _eventsSubscription = channel.events.listen((event) {
      final name =
          stringValue(asMap(event)['event']) ??
          stringValue(asMap(event)['type']) ??
          stringValue(asMap(event)['name']);
      if (name == 'audioRouteChanged' ||
          name == 'audio.route.changed' ||
          name == 'routeChanged') {
        invalidate();
      }
    });
  }

  final PlatformChannel channel;
  final AppLogger? logger;
  final String Function()? passthroughDeviceId;
  final String Function()? outputDeviceId;
  (String?, String?)? _cachedAudioDevices;
  late final StreamSubscription<Object?> _eventsSubscription;
  CapabilityReport? _cached;

  Future<void> dispose() => _eventsSubscription.cancel();

  @override
  Future<CapabilityReport> probe() async {
    final device = passthroughDeviceId?.call();
    final output = outputDeviceId?.call();
    final key = (output, device);
    final cached = _cached;
    if (cached != null && key == _cachedAudioDevices) return cached;
    try {
      final report = _parse(
        await channel.invoke(
          PlatformMethods.probe,
          device == null && output == null
              ? null
              : {'passthroughDeviceId': device, 'outputDeviceId': output},
        ),
      );
      _cachedAudioDevices = key;
      _cached = report;
      return report;
    } catch (error, stack) {
      final failure = error is PlatformFailure
          ? error
          : PlatformFailure.probeFailed(cause: error, stack: stack);
      logger?.error(
        'Platform capability probe failed',
        error: failure,
        stack: stack,
      );
      throw failure;
    }
  }

  /// Route changes invalidate only the successful cache; the next call probes again.
  void invalidate() => _cached = null;

  CapabilityReport _parse(Object? raw) {
    final map = asMap(raw);
    final diagnostics = <String, String>{};
    final rawDiagnostics = map['diagnostics'];
    if (rawDiagnostics is Map) {
      rawDiagnostics.forEach((key, value) {
        if (value is String) diagnostics['$key'] = value;
      });
    }
    final hdrFormats = _strings(map['hdrFormats']);
    final hdrOutput = boolValue(map['hdrOutput']) && hdrFormats.isNotEmpty;
    if (boolValue(map['hdrOutput']) && !hdrOutput) {
      diagnostics.putIfAbsent(
        'hdrOutput',
        () => 'unknown: native probe returned no HDR formats',
      );
    }
    if (!map.containsKey('hardwareDecode')) {
      diagnostics.putIfAbsent(
        'hardwareDecode',
        () => 'unknown: field omitted by native probe',
      );
    }
    if (map.containsKey('decoders') && _strings(map['decoders']).isEmpty) {
      diagnostics.putIfAbsent(
        'hardwareDecode',
        () => 'unsupported: native probe reported no hardware decoders',
      );
    }
    if (!map.containsKey('displayModeSwitching')) {
      diagnostics.putIfAbsent(
        'displayModeSwitching',
        () => 'unknown: field omitted by native probe',
      );
    }
    if (!map.containsKey('audioPassthrough')) {
      diagnostics.putIfAbsent(
        'audioPassthrough',
        () => 'unknown: field omitted by native probe',
      );
    }
    return CapabilityReport(
      hardwareDecode: boolValue(map['hardwareDecode']),
      decoders: _strings(map['decoders']),
      hdrOutput: hdrOutput,
      hdrFormats: hdrFormats,
      displayModeSwitching: boolValue(map['displayModeSwitching']),
      audioPassthrough: boolValue(map['audioPassthrough']),
      passthroughFormats: _strings(map['passthroughFormats']),
      diagnostics: diagnostics,
    );
  }

  static List<String> _strings(Object? raw) => raw is List
      ? raw.whereType<String>().toList(growable: false)
      : const <String>[];
}

PlatformCapabilities createPlatformCapabilities({
  AppLogger? logger,
  PlatformChannel? channel,
}) => PlatformCapabilitiesService(
  channel: channel ?? PlatformDispatch.channel(),
  logger: logger,
);

final class CapabilityVersion {
  const CapabilityVersion({required this.os, required this.plugin});

  final String os;
  final String plugin;

  factory CapabilityVersion.fromMap(Object? raw) {
    final map = asMap(raw);
    return CapabilityVersion(
      os: stringValue(map['os']) ?? 'unknown',
      plugin: stringValue(map['plugin']) ?? 'unknown',
    );
  }
}
