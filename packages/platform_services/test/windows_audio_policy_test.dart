import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _Channel implements PlatformChannel {
  final calls = <String, Object?>{};
  final _events = StreamController<Object?>.broadcast();
  Map<String, Object?> devicesPayload = {};
  bool accept = false;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls[method] = arguments;
    if (method == PlatformMethods.audioDevices) return devicesPayload;
    return {'passthrough': accept, 'deviceId': 'wasapi/b'};
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  test('Windows service probes the sink like Android and keeps channel/device facts', () async {
    final channel = _Channel()
      ..devicesPayload = {
        'supported': true,
        'os': 'windows',
        'maxOutputChannels': 6,
        'passthroughDeviceId': 'wasapi/b',
        'devices': [
          {
            'id': 'wasapi/a',
            'name': 'Speakers',
            'kind': 'speaker',
            'isCurrent': true,
          },
        ],
      };
    final service = AudioOutputServiceImpl(
      channel: channel,
      exclusiveAudio: () => true,
      passthroughDevice: () => 'wasapi/requested',
    );
    expect((await detectAudioCapability(service)).formats, isEmpty);
    expect(channel.calls[PlatformMethods.audioNegotiate], isNotNull);
    expect(service.maxOutputChannels, 6);
    expect(service.passthroughDeviceId, 'wasapi/b');
    expect(
      (channel.calls[PlatformMethods.audioDevices] as Map)['exclusive'],
      true,
    );
    expect(
      (channel.calls[PlatformMethods.audioDevices]
          as Map)['passthroughDeviceId'],
      'wasapi/requested',
    );
    await service.devices(passthroughDeviceId: 'wasapi/latched');
    expect(
      (channel.calls[PlatformMethods.audioDevices]
          as Map)['passthroughDeviceId'],
      'wasapi/latched',
    );
    channel.accept = true;
    final model = await detectAudioCapability(service);
    expect(model.formats, AudioFormat.values.toSet());
    expect(model.link, AudioLink.hdmiEarc);
    service.dispose();
    await channel.dispose();
  });

  test('Windows route change event bumps the generation', () async {
    final channel = _Channel();
    var changed = 0;
    final service = AudioOutputServiceImpl(
      channel: channel,
      onRouteChanged: () => changed++,
    );
    channel._events.add({'event': 'audioRouteChanged'});
    await Future<void>.delayed(Duration.zero);
    expect(changed, 1);
    expect(service.routeGeneration, 1);
    service.dispose();
    await channel.dispose();
  });
}
