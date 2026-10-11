import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioDevice supported sample rates', () {
    test('omitted rates mean unknown', () {
      final device = AudioDevice(id: 'speaker', name: 'Speaker');
      expect(device.supportedSampleRates, isEmpty);
      expect(device.kind, AudioDeviceKind.unknown);
      expect(device.isCurrent, isFalse);
    });

    test('rates are an immutable snapshot', () {
      final rates = <int>[44100, 48000];
      final device = AudioDevice(
        id: 'speaker',
        name: 'Speaker',
        supportedSampleRates: rates,
      );
      rates.add(96000);
      expect(device.supportedSampleRates, [44100, 48000]);
      expect(
        () => device.supportedSampleRates.add(96000),
        throwsUnsupportedError,
      );
      expect(
        () => device.supportedSampleRates[0] = 96000,
        throwsUnsupportedError,
      );
    });

    test('rate contents participate in value equality and hashing', () {
      final a = AudioDevice(
        id: 'speaker',
        name: 'Speaker',
        supportedSampleRates: [44100, 48000],
      );
      final b = AudioDevice(
        id: 'speaker',
        name: 'Speaker',
        supportedSampleRates: [44100, 48000],
      );
      final different = AudioDevice(
        id: 'speaker',
        name: 'Speaker',
        supportedSampleRates: [48000],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
      expect(a, isNot(AudioDevice(id: 'speaker', name: 'Speaker')));
      expect({a, b, different}, hasLength(2));
    });

    test('fake enumeration preserves known and unknown capabilities', () async {
      final known = AudioDevice(
        id: 'usb',
        name: 'USB',
        supportedSampleRates: [48000, 96000],
      );
      final unknown = AudioDevice(id: 'speaker', name: 'Speaker');
      final service = FakeAudioOutputService(devices: [known, unknown]);
      final devices = await service.devices();
      expect(devices.first.supportedSampleRates, [48000, 96000]);
      expect(devices.last.supportedSampleRates, isEmpty);
    });
  });

  group('AudioNegotiation', () {
    test('a downgraded negotiation cannot be constructed without a fallbackReason', () {
      expect(
        () => AudioNegotiation(
          passthrough: false,
          requestedPassthrough: true,
          deviceId: 'device-1',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a downgrade with a fallbackReason constructs fine', () {
      final negotiation = AudioNegotiation(
        passthrough: false,
        requestedPassthrough: true,
        fallbackReason: 'device does not support TrueHD',
        deviceId: 'device-1',
      );
      expect(negotiation.fallbackReason, isNotNull);
    });

    test('granted passthrough needs no fallbackReason', () {
      final negotiation = AudioNegotiation(
        passthrough: true,
        requestedPassthrough: true,
        deviceId: 'device-1',
      );
      expect(negotiation.fallbackReason, isNull);
    });
  });

  group('CapabilityReport', () {
    test('hdrOutput: true with empty hdrFormats is rejected', () {
      expect(
        () => CapabilityReport(
          hardwareDecode: true,
          decoders: const ['h264'],
          hdrOutput: true,
          hdrFormats: const [],
          displayModeSwitching: false,
          audioPassthrough: false,
          passthroughFormats: const [],
          diagnostics: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('hdrOutput: true with a non-empty hdrFormats constructs fine', () {
      final report = CapabilityReport(
        hardwareDecode: true,
        decoders: const ['h264'],
        hdrOutput: true,
        hdrFormats: const ['hdr10'],
        displayModeSwitching: false,
        audioPassthrough: false,
        passthroughFormats: const [],
        diagnostics: const {},
      );
      expect(report.hdrFormats, isNotEmpty);
    });

    test('collections are immutable snapshots', () {
      final decoders = <String>['h264'];
      final report = CapabilityReport(
        hardwareDecode: true,
        decoders: decoders,
        hdrOutput: false,
        hdrFormats: const <String>[],
        displayModeSwitching: false,
        audioPassthrough: false,
        passthroughFormats: const <String>[],
        diagnostics: const <String, String>{'backend': 'test'},
      );

      decoders.add('vp9');
      expect(report.decoders, <String>['h264']);
      expect(() => report.decoders.add('av1'), throwsA(isA<UnsupportedError>()));
    });
  });

  group('DisplayMode', () {
    test('equality lets "is this the current mode" comparisons work', () {
      const a = DisplayMode(width: 3840, height: 2160, refreshHz: 23.976, isCurrent: true);
      const b = DisplayMode(width: 3840, height: 2160, refreshHz: 23.976, isCurrent: true);
      const c = DisplayMode(width: 3840, height: 2160, refreshHz: 24.0, isCurrent: false);

      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
