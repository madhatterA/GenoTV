import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _MediaChannel implements PlatformChannel {
  final _events = StreamController<Object?>.broadcast();
  final calls = <String>[];
  final payloads = <Map<String, Object?>>[];

  void emit(Object event) => _events.add(event);

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    if (arguments is Map) {
      payloads.add(arguments.map((key, value) => MapEntry('$key', value)));
    }
    return const <String, Object?>{'supported': true};
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  test('publishes now-playing info and throttles position updates', () async {
    final channel = _MediaChannel();
    var now = DateTime(2026, 1, 1);
    final service = MediaSessionService(channel: channel, now: () => now);
    const info = MediaSessionInfo(
      title: 'Track',
      subtitle: 'Episode',
      duration: Duration(minutes: 2),
      position: Duration(seconds: 3),
      playing: true,
    );
    await service.updateNowPlaying(info);
    now = now.add(const Duration(milliseconds: 500));
    await service.updateNowPlaying(info);
    expect(channel.calls, [PlatformMethods.mediaSessionUpdate]);
    now = now.add(const Duration(milliseconds: 500));
    await service.updateNowPlaying(info);
    expect(channel.calls, [
      PlatformMethods.mediaSessionUpdate,
      PlatformMethods.mediaSessionUpdate,
    ]);
    expect(channel.payloads.first['title'], 'Track');
    expect(channel.payloads.first['durationSeconds'], 120.0);
    await service.dispose();
    await channel.dispose();
  });

  test(
    'state and metadata changes are not throttled, and clear resets it',
    () async {
      final channel = _MediaChannel();
      var now = DateTime(2026, 1, 1);
      final service = MediaSessionService(channel: channel, now: () => now);
      const playing = MediaSessionInfo(
        title: 'T',
        position: Duration.zero,
        playing: true,
      );
      const paused = MediaSessionInfo(title: 'T', position: Duration.zero);
      await service.updateNowPlaying(playing);
      now = now.add(const Duration(milliseconds: 100));
      await service.updateNowPlaying(paused);
      expect(channel.payloads.last['playing'], false);
      now = now.add(const Duration(milliseconds: 100));
      await service.updateNowPlaying(
        const MediaSessionInfo(
          title: 'T',
          position: Duration.zero,
          artworkBytes: [1, 2],
        ),
      );
      expect(channel.payloads.last['artworkBytes'], isA<Uint8List>());
      await service.clear();
      await service.updateNowPlaying(paused);
      expect(channel.calls, [
        PlatformMethods.mediaSessionUpdate,
        PlatformMethods.mediaSessionUpdate,
        PlatformMethods.mediaSessionUpdate,
        PlatformMethods.mediaSessionClear,
        PlatformMethods.mediaSessionUpdate,
      ]);
      await service.dispose();
      await channel.dispose();
    },
  );

  test('maps each system command and seek position', () async {
    final channel = _MediaChannel();
    final service = MediaSessionService(channel: channel);
    final commands = <MediaSessionCommand>[];
    final subscription = service.commands.listen(commands.add);
    for (final command in [
      'play',
      'pause',
      'togglePlay',
      'skipForward',
      'skipBackward',
      'stop',
      'unknown',
    ]) {
      channel.emit({'event': 'mediaCommand', 'command': command});
    }
    channel.emit({
      'event': 'mediaCommand',
      'command': 'seekTo',
      'positionSeconds': 12.5,
    });
    await Future<void>.delayed(Duration.zero);
    expect(commands.map((command) => command.type), [
      MediaSessionCommandType.play,
      MediaSessionCommandType.pause,
      MediaSessionCommandType.togglePlay,
      MediaSessionCommandType.skipForward,
      MediaSessionCommandType.skipBackward,
      MediaSessionCommandType.stop,
      MediaSessionCommandType.unknown,
      MediaSessionCommandType.seekTo,
    ]);
    expect(
      commands.last.position,
      const Duration(seconds: 12, milliseconds: 500),
    );
    await subscription.cancel();
    await service.dispose();
    await channel.dispose();
  });

  test('dispose clears the session and drops later commands', () async {
    final channel = _MediaChannel();
    final service = MediaSessionService(channel: channel);
    var commands = 0;
    final subscription = service.commands.listen((_) => commands++);
    await service.dispose();
    channel.emit({'event': 'mediaCommand', 'command': 'play'});
    await Future<void>.delayed(Duration.zero);
    expect(commands, 0);
    expect(channel.calls, [PlatformMethods.mediaSessionClear]);
    await subscription.cancel();
    await channel.dispose();
  });
}
