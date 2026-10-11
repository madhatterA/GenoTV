import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _FakeChannel implements PlatformChannel {
  _FakeChannel(this.handler);

  final FutureOr<Object?> Function(String method) handler;
  Object? lastArguments;
  final _events = StreamController<Object?>.broadcast();

  @override
  Future<Object?> invoke(String method, [Object? arguments]) {
    lastArguments = arguments;
    return Future<Object?>.value(handler(method));
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  test('full payload produces a complete report', () async {
    final service = PlatformCapabilitiesService(
      channel: _FakeChannel(
        (_) => {
          'hardwareDecode': true,
          'decoders': ['h264'],
          'hdrOutput': true,
          'hdrFormats': ['hdr10'],
          'displayModeSwitching': false,
          'audioPassthrough': true,
          'passthroughFormats': ['eac3'],
          'diagnostics': {'api': '36'},
        },
      ),
    );
    final report = await service.probe();
    expect(report.hardwareDecode, isTrue);
    expect(report.decoders, ['h264']);
    expect(report.hdrOutput, isTrue);
    expect(report.hdrFormats, ['hdr10']);
    expect(report.audioPassthrough, isTrue);
    expect(report.passthroughFormats, ['eac3']);
    expect(report.diagnostics['api'], '36');
    await service.dispose();
  });

  test(
    'missing fields are omitted with diagnostics, never optimistic',
    () async {
      final service = PlatformCapabilitiesService(
        channel: _FakeChannel((_) => {'diagnostics': <String, String>{}}),
      );
      final report = await service.probe();
      expect(report.hardwareDecode, isFalse);
      expect(report.decoders, isEmpty);
      expect(report.hdrOutput, isFalse);
      expect(report.hdrFormats, isEmpty);
      expect(report.diagnostics['hardwareDecode'], contains('omitted'));
      expect(report.diagnostics['displayModeSwitching'], contains('omitted'));
      expect(report.diagnostics['audioPassthrough'], contains('omitted'));
      await service.dispose();
    },
  );

  test('failed probe is not cached and surfaces a typed failure', () async {
    var calls = 0;
    final service = PlatformCapabilitiesService(
      channel: _FakeChannel((_) {
        calls++;
        if (calls == 1) throw StateError('probe failed');
        return {
          'hardwareDecode': false,
          'decoders': <String>[],
          'hdrOutput': false,
          'hdrFormats': <String>[],
          'displayModeSwitching': false,
          'audioPassthrough': false,
          'passthroughFormats': <String>[],
        };
      }),
    );
    await expectLater(service.probe(), throwsA(isA<PlatformFailure>()));
    final report = await service.probe();
    expect(report.hdrOutput, isFalse);
    expect(calls, 2);
    await service.dispose();
  });

  test('successful probe is cached', () async {
    var calls = 0;
    final service = PlatformCapabilitiesService(
      channel: _FakeChannel((_) {
        calls++;
        return {
          'hardwareDecode': false,
          'decoders': <String>[],
          'hdrOutput': false,
          'hdrFormats': <String>[],
          'displayModeSwitching': false,
          'audioPassthrough': false,
          'passthroughFormats': <String>[],
        };
      }),
    );
    final first = await service.probe();
    expect(identical(first, await service.probe()), isTrue);
    expect(calls, 1);
    await service.dispose();
  });

  test('HDR output with no formats is rejected by the contract', () async {
    final service = PlatformCapabilitiesService(
      channel: _FakeChannel(
        (_) => {
          'hardwareDecode': false,
          'decoders': <String>[],
          'hdrOutput': true,
          'hdrFormats': <String>[],
          'displayModeSwitching': false,
          'audioPassthrough': false,
          'passthroughFormats': <String>[],
        },
      ),
    );
    final report = await service.probe();
    expect(report.hdrOutput, isFalse);
    expect(report.hdrFormats, isEmpty);
    expect(report.diagnostics['hdrOutput'], contains('no HDR formats'));
    await service.dispose();
  });

  test(
    'empty decoder list reports an explicit unsupported diagnostic',
    () async {
      final service = PlatformCapabilitiesService(
        channel: _FakeChannel(
          (_) => {
            'hardwareDecode': false,
            'decoders': <String>[],
            'hdrOutput': false,
            'hdrFormats': <String>[],
            'displayModeSwitching': false,
            'audioPassthrough': false,
            'passthroughFormats': <String>[],
          },
        ),
      );
      final report = await service.probe();
      expect(
        report.diagnostics['hardwareDecode'],
        contains('no hardware decoders'),
      );
      await service.dispose();
    },
  );

  test(
    'changing the configured Windows passthrough device re-probes its formats',
    () async {
      var id = 'wasapi/hdmi';
      var calls = 0;
      late _FakeChannel channel;
      channel = _FakeChannel((_) {
        calls++;
        final arguments = channel.lastArguments as Map;
        return {
          'audioPassthrough': true,
          'passthroughFormats':
              arguments['passthroughDeviceId'] == 'wasapi/hdmi'
              ? ['ac3', 'eac3', 'trueHd']
              : ['ac3'],
          'diagnostics': {'os': 'windows'},
        };
      });
      final service = PlatformCapabilitiesService(
        channel: channel,
        passthroughDeviceId: () => id,
      );
      expect((await service.probe()).passthroughFormats, [
        'ac3',
        'eac3',
        'trueHd',
      ]);
      expect((await service.probe()).passthroughFormats, [
        'ac3',
        'eac3',
        'trueHd',
      ]);
      expect(calls, 1);
      id = 'wasapi/spdif';
      expect((await service.probe()).passthroughFormats, ['ac3']);
      expect(calls, 2);
      await service.dispose();
      await channel.dispose();
    },
  );
}
