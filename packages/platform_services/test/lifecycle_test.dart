import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _LifecycleChannel implements PlatformChannel {
  final _events = StreamController<Object?>.broadcast();
  final calls = <String>[];

  void emit(Object event) => _events.add(event);

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    return const <String, Object?>{'supported': true};
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  test('keep-awake lease acquires, releases once, and is idempotent', () async {
    final channel = _LifecycleChannel();
    final service = PlaybackLifecycleService(channel: channel);
    final lease = await service.acquireKeepAwake();
    await lease.release();
    await lease.release();
    expect(channel.calls, [
      PlatformMethods.lifecycleKeepAwake,
      PlatformMethods.lifecycleReleaseAwake,
    ]);
    await service.dispose();
    await channel.dispose();
  });

  test('service teardown releases an unreleased lease', () async {
    final channel = _LifecycleChannel();
    final service = PlaybackLifecycleService(channel: channel);
    await service.acquireKeepAwake();
    await service.dispose();
    expect(channel.calls, [
      PlatformMethods.lifecycleKeepAwake,
      PlatformMethods.lifecycleReleaseAwake,
    ]);
    await channel.dispose();
  });

  test('interruption events preserve type, transient loss, and resume flag', () async {
    final channel = _LifecycleChannel();
    final service = PlaybackLifecycleService(channel: channel);
    final events = <PlatformEvent>[];
    final subscription = service.events.listen(events.add);
    channel.emit({'event': 'audioInterruptionBegan', 'lossKind': 'transient'});
    channel.emit({
      'event': 'audioInterruptionEnded',
      'shouldResume': true,
      'lossKind': 'transient',
    });
    channel.emit({'event': 'becameNoisy'});
    await Future<void>.delayed(Duration.zero);
    expect(events.map((event) => event.type), [
      PlatformEventType.audioInterruptionBegan,
      PlatformEventType.audioInterruptionEnded,
      PlatformEventType.becameNoisy,
    ]);
    expect(events[0].lossKind, 'transient');
    expect(events[1].shouldResume, isTrue);
    await subscription.cancel();
    await service.dispose();
    await channel.dispose();
  });

  test('disposed service drops subsequent events', () async {
    final channel = _LifecycleChannel();
    final service = PlaybackLifecycleService(channel: channel);
    var count = 0;
    final subscription = service.events.listen((_) => count++);
    await service.dispose();
    channel.emit({'event': 'appBackgrounded'});
    await Future<void>.delayed(Duration.zero);
    expect(count, 0);
    await subscription.cancel();
    await channel.dispose();
  });

  test('transient and permanent loss are distinct; backgrounding is alone', () async {
    final channel = _LifecycleChannel();
    final service = PlaybackLifecycleService(channel: channel);
    final events = <PlatformEvent>[];
    final subscription = service.events.listen(events.add);
    channel.emit({'event': 'audioInterruptionBegan', 'lossKind': 'transient'});
    channel.emit({'event': 'audioInterruptionBegan', 'lossKind': 'permanent'});
    channel.emit({'event': 'appBackgrounded'});
    await Future<void>.delayed(Duration.zero);
    expect(events[0].lossKind, isNot(events[1].lossKind));
    expect(events[2].type, PlatformEventType.appBackgrounded);
    expect(events, hasLength(3));
    await subscription.cancel();
    await service.dispose();
    await channel.dispose();
  });
}
