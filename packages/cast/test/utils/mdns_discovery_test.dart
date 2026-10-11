import 'dart:io';

import 'package:cast/src/core/cast_device.dart';
import 'package:cast/src/utils/mdns_discovery.dart';
import 'package:test/test.dart';

void main() {
  group('MdnsServiceInfo', () {
    group('Chromecast TXT records', () {
      test('parses friendly name from fn', () {
        final info = MdnsServiceInfo(
          name: 'Chromecast-abc123._googlecast._tcp.local',
          host: '192.168.1.100',
          port: 8009,
          txtRecords: {
            'fn': 'Living Room TV',
            'md': 'Chromecast',
            'id': 'abc-123',
          },
        );

        expect(info.friendlyName, 'Living Room TV');
      });

      test('parses device id from id', () {
        final info = MdnsServiceInfo(
          name: 'Chromecast-abc123._googlecast._tcp.local',
          host: '192.168.1.100',
          port: 8009,
          txtRecords: {
            'fn': 'Living Room TV',
            'md': 'Chromecast',
            'id': 'abc-123',
          },
        );

        expect(info.deviceId, 'abc-123');
      });

      test('parses model from md', () {
        final info = MdnsServiceInfo(
          name: 'Chromecast-abc123._googlecast._tcp.local',
          host: '192.168.1.100',
          port: 8009,
          txtRecords: {
            'fn': 'Living Room TV',
            'md': 'Chromecast Ultra',
            'id': 'abc-123',
          },
        );

        expect(info.model, 'Chromecast Ultra');
      });
    });

    group('toChromecastDevice', () {
      test('creates correct CastDevice with chromecast protocol', () {
        final info = MdnsServiceInfo(
          name: 'Chromecast-abc._googlecast._tcp.local',
          host: '192.168.1.100',
          port: 8009,
          txtRecords: {
            'fn': 'Living Room TV',
            'md': 'Chromecast',
            'id': 'abc-123',
          },
        );

        final device = info.toChromecastDevice();
        expect(device.id, 'abc-123');
        expect(device.name, 'Living Room TV');
        expect(device.protocol, CastProtocol.chromecast);
        expect(device.address, InternetAddress('192.168.1.100'));
        expect(device.port, 8009);
        expect(device.metadata['md'], 'Chromecast');
      });
    });
  });

  group('MdnsDiscovery', () {
    test('has correct chromecast service type', () {
      expect(MdnsDiscovery.chromecastServiceType, '_googlecast._tcp.local');
    });

    test('discover returns a Stream (does not throw on creation)', () {
      // Verifies that MdnsDiscovery.discover produces a valid Stream.
      // Actual device discovery requires a network so we only check the type.
      final stream = MdnsDiscovery.discover('_test._tcp.local');
      expect(stream, isA<Stream<MdnsServiceInfo>>());
    });
  });
}
