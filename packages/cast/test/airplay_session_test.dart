import 'dart:async';

import 'package:cast/dart_cast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cast/airplay');
  final calls = <MethodCall>[];
  late StreamController<dynamic> events;
  late AirPlaySession session;

  setUp(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          return null;
        });
    events = StreamController<dynamic>.broadcast();
    session = AirPlaySession(channel: channel, events: events.stream);
    await session.connect();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await events.close();
  });

  Future<void> emit(Map<String, Object?> s) async {
    events.add(s);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'loadMedia prepares the native player with the proxy URL and start',
    () async {
      await session.loadMedia(
        const CastMedia(
          url: 'http://192.168.1.2:9/s.mp4',
          type: CastMediaType.mp4,
          startPosition: Duration(seconds: 7),
        ),
      );
      expect(calls.single.method, 'prepare');
      expect(calls.single.arguments, {
        'url': 'http://192.168.1.2:9/s.mp4',
        'startMs': 7000,
      });
    },
  );

  test('controls map to native calls', () async {
    await session.play();
    await session.pause();
    await session.seek(const Duration(seconds: 3));
    await session.stop();
    expect(calls.map((c) => c.method), ['play', 'pause', 'seek', 'stop']);
    expect(calls[2].arguments, {'positionMs': 3000});
  });

  test(
    'snapshots map to state, position, duration and route changes',
    () async {
      final route = <bool>[];
      session.externalPlaybackStream.listen(route.add);
      await emit({
        'state': 'paused',
        'external': false,
        'positionMs': 0,
        'durationMs': 9000,
      });
      expect(session.state, SessionState.paused);
      await emit({
        'state': 'playing',
        'external': true,
        'positionMs': 1500,
        'durationMs': 9000,
      });
      expect(session.state, SessionState.playing);
      expect(session.position, const Duration(milliseconds: 1500));
      expect(session.duration, const Duration(seconds: 9));
      await emit({
        'state': 'buffering',
        'external': true,
        'positionMs': 1500,
        'durationMs': 9000,
      });
      expect(session.state, SessionState.buffering);
      await emit({
        'state': 'paused',
        'external': false,
        'positionMs': 2000,
        'durationMs': 9000,
      });
      expect(route, [true, false]);
      expect(session.externalActive, isFalse);
    },
  );

  test('disconnect stops the native player', () async {
    await session.disconnect();
    expect(calls.last.method, 'stop');
    expect(session.state, SessionState.disconnected);
  });
}
