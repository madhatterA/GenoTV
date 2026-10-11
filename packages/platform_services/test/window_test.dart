import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

import 'dart:async';

final class _WindowChannel implements PlatformChannel {
  _WindowChannel(this.reply);

  final Object? Function() reply;
  final calls = <(String, Object?)>[];

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add((method, arguments));
    return reply();
  }

  @override
  Stream<Object?> get events => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'fullscreen requests wait for the preceding native completion',
    () async {
      final firstReply = Completer<Object?>();
      var replies = 0;
      final channel = _WindowChannel(
        () => ++replies == 1 ? firstReply.future : {'supported': true},
      );
      final service = WindowService(channel: channel);
      final enter = service.setFullscreen(true);
      final exit = service.setFullscreen(false);
      await Future<void>.delayed(Duration.zero);
      expect(channel.calls, hasLength(1));
      firstReply.complete({'supported': true});
      await Future.wait([enter, exit]);
      expect(channel.calls.map((c) => (c.$2 as Map)['enabled']), [true, false]);
    },
  );

  test('a failed fullscreen request does not block the next request', () async {
    var replies = 0;
    final channel = _WindowChannel(
      () => ++replies == 1
          ? throw PlatformException(code: 'platform.unsupported')
          : {'supported': true},
    );
    final service = WindowService(channel: channel);
    final enter = service.setFullscreen(true);
    final exit = service.setFullscreen(false);
    await expectLater(enter, throwsA(isA<PlatformFailure>()));
    await exit;
    expect(channel.calls, hasLength(2));
  });
  test('setFullscreen sends window.fullscreen with the flag', () async {
    final channel = _WindowChannel(() => {'supported': true});
    final service = WindowService(channel: channel);
    await service.setFullscreen(true);
    await service.setFullscreen(false);
    expect(channel.calls.map((c) => c.$1), everyElement('window.fullscreen'));
    expect(channel.calls.map((c) => (c.$2 as Map)['enabled']), [true, false]);
  });

  test('an unsupported answer is a typed failure', () async {
    final service = WindowService(
      channel: _WindowChannel(
        () => {'supported': false, 'reason': 'the app has no window'},
      ),
    );
    await expectLater(
      service.setFullscreen(true),
      throwsA(isA<PlatformFailure>()),
    );
  });

  test('a native error is mapped to a typed failure', () async {
    final service = WindowService(
      channel: _WindowChannel(
        () => throw PlatformException(code: 'platform.unsupported'),
      ),
    );
    await expectLater(
      service.setFullscreen(true),
      throwsA(isA<PlatformFailure>()),
    );
  });

  test('the plugin channel carries window.fullscreen to the plugin', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(PlatformMethods.channelName);
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          seen = call;
          return {'supported': true, 'fullscreen': true};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await WindowService(channel: MethodPlatformChannel()).setFullscreen(true);
    expect(seen?.method, 'window.fullscreen');
    expect(seen?.arguments, {'enabled': true});
  });
}
