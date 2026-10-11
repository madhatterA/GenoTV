import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _PassthroughChannel implements PlatformChannel {
  _PassthroughChannel(this.handler);

  final FutureOr<Object?> Function(String, Object?) handler;
  final _events = StreamController<Object?>.broadcast();
  final calls = <Map<String, Object?>>[];

  void emit(Object event) => _events.add(event);

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    if (method == PlatformMethods.audioNegotiate && arguments is Map) {
      calls.add(arguments.map((key, value) => MapEntry('$key', value)));
    }
    return handler(method, arguments);
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

AudioStreamSpec _spec(String codec) => AudioStreamSpec(
      codec: codec,
      channels: 6,
      sampleRate: 48000,
      bitDepth: 24,
      requestedPassthrough: true,
    );

void main() {
  test('supported format is granted without a fallback reason', () async {
    final channel = _PassthroughChannel(
      (_, _) => {
        'passthrough': true,
        'deviceId': 'hdmi-1',
      },
    );
    final result = await AudioOutputServiceImpl(channel: channel).negotiate(
          _spec('ac3'),
        );
    expect(result.passthrough, isTrue);
    expect(result.fallbackReason, isNull);
    expect(result.deviceId, 'hdmi-1');
    await channel.dispose();
  });

  test('unsupported format carries a specific fallback reason', () async {
    final channel = _PassthroughChannel(
      (_, _) => {
        'passthrough': false,
        'fallbackReason': 'sink does not report EAC3 support',
        'deviceId': 'speaker',
      },
    );
    final result = await AudioOutputServiceImpl(channel: channel).negotiate(
          _spec('eac3'),
        );
    expect(result.passthrough, isFalse);
    expect(result.fallbackReason, 'sink does not report EAC3 support');
    expect(result.fallbackReason, isNot('unsupported'));
    await channel.dispose();
  });

  test('iOS-style unsupported response is preserved', () async {
    final channel = _PassthroughChannel(
      (_, _) => {
        'passthrough': false,
        'fallbackReason': 'platform does not support bitstream output',
        'deviceId': 'unknown',
      },
    );
    final result = await AudioOutputServiceImpl(channel: channel).negotiate(
          _spec('truehd'),
        );
    expect(result.passthrough, isFalse);
    expect(result.fallbackReason, contains('platform does not support'));
    await channel.dispose();
  });

  test('a route change makes an in-flight result stale', () async {
    final gate = Completer<Object?>();
    final channel = _PassthroughChannel((_, _) => gate.future);
    final service = AudioOutputServiceImpl(channel: channel);
    final pending = service.negotiate(_spec('ac3'));
    channel.emit({'event': 'audioRouteChanged'});
    await Future<void>.delayed(Duration.zero);
    gate.complete({
      'passthrough': true,
      'deviceId': 'old-hdmi',
    });
    final result = await pending;
    expect(result.passthrough, isTrue);
    expect(result.fallbackReason, 'audio route changed during negotiation');
    service.dispose();
    await channel.dispose();
  });

  test('each requested codec reaches the native query distinctly', () async {
    final channel = _PassthroughChannel((_, arguments) {
      final codec = (arguments as Map)['codec'] as String;
      return {
        'passthrough': false,
        'fallbackReason': 'sink does not report $codec support',
        'deviceId': 'default',
      };
    });
    final service = AudioOutputServiceImpl(channel: channel);
    for (final codec in ['ac3', 'eac3', 'eac3-joc', 'dts', 'dts-hd', 'truehd']) {
      final result = await service.negotiate(_spec(codec));
      expect(result.fallbackReason, contains(codec));
    }
    expect(channel.calls.map((call) => call['codec']), [
      'ac3',
      'eac3',
      'eac3-joc',
      'dts',
      'dts-hd',
      'truehd',
    ]);
    service.dispose();
    await channel.dispose();
  });

  test('negotiations are recorded with format, result, reason and device', () async {
    final channel = _PassthroughChannel(
      (_, _) => {
        'passthrough': false,
        'fallbackReason': 'MacBook Pro Speakers (speaker) lists no eac3 physical format; output is PCM only',
        'deviceId': '83',
      },
    );
    final service = AudioOutputServiceImpl(channel: channel);
    await service.negotiate(_spec('eac3'));
    expect(service.negotiationLog.single, contains('eac3'));
    expect(service.negotiationLog.single, contains('passthrough=false'));
    expect(service.negotiationLog.single, contains('physical format'));
    expect(service.negotiationLog.single, contains('device=83'));
    service.dispose();
    await channel.dispose();
  });

  test('a downgrade without a reason cannot be constructed', () {
    expect(
      () => AudioNegotiation(
        passthrough: false,
        requestedPassthrough: true,
        deviceId: 'x',
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
