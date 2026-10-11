import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _AudioChannel implements PlatformChannel {
  _AudioChannel(this.payload);

  final Object? payload;
  Object? negotiationArguments;
  final _events = StreamController<Object?>.broadcast();

  void emit(Object event) => _events.add(event);

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    if (method == PlatformMethods.audioDevices) return payload;
    if (method == PlatformMethods.audioNegotiate) {
      negotiationArguments = arguments;
    }
    return const <String, Object?>{};
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  test(
    'explicit negotiation device wins over global selected output',
    () async {
      final channel = _AudioChannel({'supported': true, 'devices': []});
      final service = AudioOutputServiceImpl(
        channel: channel,
        outputDeviceId: () => 'coreaudio/pcm',
      );
      await service.negotiate(
        const AudioStreamSpec(
          codec: 'ac3',
          channels: 6,
          sampleRate: 48000,
          bitDepth: 16,
          requestedPassthrough: true,
        ),
        deviceId: 'coreaudio/passthrough',
      );
      expect(
        (channel.negotiationArguments as Map)['deviceId'],
        'coreaudio/passthrough',
      );
      service.dispose();
      await channel.dispose();
    },
  );
  testSupportedSampleRates();
  testIosSessionChannels();
  test(
    'negotiation targets the selected device callback, defaulting to Auto',
    () async {
      final channel = _AudioChannel({});
      var selected = 'coreaudio/hdmi';
      final service = AudioOutputServiceImpl(
        channel: channel,
        outputDeviceId: () => selected,
      );
      const spec = AudioStreamSpec(
        codec: 'ac3',
        channels: 6,
        sampleRate: 48000,
        bitDepth: 16,
        requestedPassthrough: true,
      );
      await service.negotiate(spec);
      expect((channel.negotiationArguments as Map)['deviceId'], selected);
      selected = 'coreaudio/speakers';
      await service.negotiate(spec);
      expect((channel.negotiationArguments as Map)['deviceId'], selected);
      service.dispose();
      final auto = AudioOutputServiceImpl(channel: channel);
      await auto.negotiate(spec);
      expect((channel.negotiationArguments as Map)['deviceId'], 'auto');
      auto.dispose();
      await channel.dispose();
    },
  );
  test('maps built-in headphones kind', () async {
    final channel = _AudioChannel({
      'supported': true,
      'devices': [
        {
          'id': '1',
          'name': 'Headphones',
          'kind': 'headphones',
          'isCurrent': true,
        },
      ],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    final d = (await service.devices()).single;
    expect(d.kind, AudioDeviceKind.headphones);
    expect(d.isCurrent, isTrue);
    service.dispose();
    await channel.dispose();
  });

  test('exactly one of three devices is current', () async {
    final channel = _AudioChannel({
      'supported': true,
      'devices': [
        {'id': 'a', 'name': 'A', 'kind': 'bluetooth', 'isCurrent': false},
        {'id': 'b', 'name': 'B', 'kind': 'usb', 'isCurrent': true},
        {'id': 'c', 'name': 'C', 'kind': 'speaker', 'isCurrent': false},
      ],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    final devices = await service.devices();
    expect(devices.where((d) => d.isCurrent).map((d) => d.id), ['b']);
    service.dispose();
    await channel.dispose();
  });

  test('enumerates all valid output devices', () async {
    final channel = _AudioChannel({
      'supported': true,
      'devices': [
        {'id': 'speaker', 'name': 'Built-in speaker', 'isCurrent': true},
        {
          'id': 'headphones',
          'name': 'Headphones',
          'kind': 'headphones',
          'isCurrent': false,
        },
        {'id': 'hdmi', 'name': 'HDMI', 'kind': 'hdmi', 'isCurrent': false},
      ],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    expect(await service.devices(), [
      AudioDevice(id: 'speaker', name: 'Built-in speaker', isCurrent: true),
      AudioDevice(
        id: 'headphones',
        name: 'Headphones',
        kind: AudioDeviceKind.headphones,
      ),
      AudioDevice(id: 'hdmi', name: 'HDMI', kind: AudioDeviceKind.hdmi),
    ]);
    service.dispose();
    await channel.dispose();
  });

  test('maps an unknown native kind to unknown, not a guess', () async {
    final channel = _AudioChannel({
      'supported': true,
      'devices': [
        {'id': 'mystery', 'name': 'Unclassified output', 'kind': 'future-type'},
      ],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    final devices = await service.devices();
    expect(devices.single.kind, AudioDeviceKind.unknown);
    expect(devices.single.isCurrent, isFalse);
    service.dispose();
    await channel.dispose();
  });

  test('route events reach listeners and increment route generation', () async {
    final channel = _AudioChannel({'supported': true, 'devices': []});
    var callbacks = 0;
    final service = AudioOutputServiceImpl(
      channel: channel,
      onRouteChanged: () => callbacks++,
    );
    channel.emit({'event': 'audioRouteChanged'});
    await Future<void>.delayed(Duration.zero);
    expect(callbacks, 1);
    expect(service.routeGeneration, 1);
    service.dispose();
    channel.emit({'event': 'routeChanged'});
    await Future<void>.delayed(Duration.zero);
    expect(callbacks, 1);
    await channel.dispose();
  });

  test(
    'unsupported enumeration returns an empty list and diagnostic',
    () async {
      final channel = _AudioChannel({
        'supported': false,
        'devices': <Object?>[],
        'reason': 'platform.unsupported: audio devices',
      });
      final service = AudioOutputServiceImpl(channel: channel);
      expect(await service.devices(), isEmpty);
      expect(service.diagnostic, contains('platform.unsupported'));
      service.dispose();
      await channel.dispose();
    },
  );

  test('malformed enumeration does not throw', () async {
    final channel = _AudioChannel({
      'supported': true,
      'devices': ['bad'],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    expect(await service.devices(), isEmpty);
    expect(service.diagnostic, isNull);
    service.dispose();
    await channel.dispose();
  });
}

void testSupportedSampleRates() {
  test(
    'native sample rates become an immutable validated device snapshot',
    () async {
      final channel = _AudioChannel({
        'supported': true,
        'devices': [
          {
            'id': 'coreaudio/device-uid',
            'name': 'DAC',
            'supportedSampleRates': [
              44100,
              48000,
              96000,
              48000,
              0,
              -1,
              'bad',
              44100.5,
            ],
          },
        ],
        'diagnostic':
            'Core Audio output sample rates unavailable for another device',
      });
      final service = AudioOutputServiceImpl(channel: channel);
      final device = (await service.devices()).single;
      expect(device.id, 'coreaudio/device-uid');
      expect(
        service.diagnostic,
        'Core Audio output sample rates unavailable for another device',
      );
      expect(device.supportedSampleRates, [44100, 48000, 96000]);
      expect(
        () => device.supportedSampleRates.add(192000),
        throwsUnsupportedError,
      );
      service.dispose();
      await channel.dispose();
    },
  );

  test('missing or malformed native sample rates stay unknown', () async {
    final channel = _AudioChannel({
      'supported': true,
      'devices': [
        {'id': 'a', 'name': 'Missing'},
        {'id': 'b', 'name': 'Malformed', 'supportedSampleRates': '48000'},
      ],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    expect(
      (await service.devices()).every(
        (device) => device.supportedSampleRates.isEmpty,
      ),
      isTrue,
    );
    service.dispose();
    await channel.dispose();
  });
}

void testIosSessionChannels() {
  test('iOS session channel maximum is read and refreshed on route change', () async {
    final channel = _AudioChannel({
      'supported': true,
      'os': 'ios',
      'maxOutputChannels': 2,
      'devices': [],
    });
    final service = AudioOutputServiceImpl(channel: channel);
    expect(service.maxOutputChannels, isNull);
    await service.devices();
    expect(service.maxOutputChannels, 2);
    channel.emit({'event': 'audioRouteChanged', 'maxOutputChannels': 8});
    await Future<void>.delayed(Duration.zero);
    expect(service.maxOutputChannels, 8);
    expect(service.usesAudioTrack, isFalse);
    service.dispose();
    await channel.dispose();
  });
}
