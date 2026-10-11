import 'dart:async';
import 'dart:io';

import 'package:cast/dart_cast.dart';
import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:video_player/cast_bridge.dart';
import 'package:video_player/playback_session.dart';
import 'package:video_player/ui_bindings.dart';

// SYNTHETIC devices and sessions: no real cast device exists on this LAN.
class _Provider implements DeviceDiscoveryProvider {
  _Provider(this.protocol, this.devices);
  @override
  final CastProtocol protocol;
  final List<CastDevice> devices;
  @override
  Stream<List<CastDevice>> startDiscovery({
    Duration timeout = const Duration(seconds: 10),
  }) => Stream.value(devices);
  @override
  void stopDiscovery() {}
  @override
  void dispose() {}
}

class _Session extends CastSession {
  _Session(super.device);
  final calls = <String>[];
  CastMedia? loaded;
  Object? errorWhileLoading;
  @override
  Future<void> loadMedia(CastMedia media) async {
    loaded = media;
    stateMachine.transitionTo(SessionState.loading);
    final error = errorWhileLoading;
    if (error != null) {
      reportError(error);
      await Future<void>.delayed(Duration.zero);
    }
    stateMachine.transitionTo(SessionState.playing);
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration p) async => calls.add('seek:${p.inSeconds}');
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setSubtitle(CastSubtitle? s) async {}
  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    stateMachine.forceState(SessionState.disconnected);
  }
}

CastDevice _cc(String ip) => CastDevice(
  id: 'cc-$ip',
  name: 'Living Room',
  protocol: CastProtocol.chromecast,
  address: InternetAddress(ip),
  port: 8009,
  metadata: {'md': 'Chromecast'},
);
CastDevice _dlna(String ip) => CastDevice(
  id: 'dlna-$ip',
  name: 'BRAVIA',
  protocol: CastProtocol.dlna,
  address: InternetAddress(ip),
  port: 52323,
);

const _mp4 = MediaInfo(
  container: 'mov,mp4,m4a',
  videoCodec: 'h264',
  audioCodec: 'aac',
);
const _mkv = MediaInfo(
  container: 'matroska,webm',
  videoCodec: 'h264',
  audioCodec: 'ac3',
);

void main() {
  final url = Uri.parse('http://127.0.0.1:5555/stream');
  late FakePlaybackController local;
  late _Session session;

  CastBridge bridge({CastCompatibility dlna = CastCompatibility.direct}) {
    session = _Session(_cc('192.168.1.20'));
    return CastBridge(
      service: CastService(
        discoveryProviders: [
          _Provider(CastProtocol.chromecast, [_cc('192.168.1.20')]),
          _Provider(CastProtocol.dlna, [_dlna('192.168.1.20')]),
        ],
        sessionFactory: (d) => session,
      ),
      controller: local,
      url: url,
      title: 'Movie',
      logger: MemoryLogger(),
      dlnaCompatibility: (_, _) async => dlna,
    );
  }

  Future<List<CastTarget>> targets(CastBridge b) async {
    await b.startDiscovery();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return b.state.value.targets;
  }

  setUp(() => local = FakePlaybackController());

  test('dual-protocol TV is listed once; MP4 is playable', () async {
    final b = bridge();
    local.emitMediaInfo(_mp4);
    await Future<void>.delayed(Duration.zero);
    final t = await targets(b);
    expect(t, hasLength(1));
    expect(t.single.playable, isTrue);
    await b.dispose();
  });

  test('MKV: direct DLNA takes priority over Chromecast remux', () async {
    final b = bridge();
    local.emitMediaInfo(_mkv);
    await Future<void>.delayed(Duration.zero);
    final t = await targets(b);
    expect(t, hasLength(1));
    expect(t.single.playable, isTrue);
    await b.dispose();
  });

  test(
    'MKV is playable through Chromecast remux when DLNA rejects it',
    () async {
      final b = bridge(dlna: CastCompatibility.notCompatible);
      local.emitMediaInfo(_mkv);
      await Future<void>.delayed(Duration.zero);
      expect((await targets(b)).single.playable, isTrue);
      await b.dispose();
    },
  );

  test(
    'no media info yet: Checking, then re-evaluated when info arrives',
    () async {
      final b = bridge();
      final t = await targets(b);
      expect(t.single.checking, isTrue);
      expect(t.single.playable, isFalse);
      local.emitMediaInfo(_mp4);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.state.value.targets.single.checking, isFalse);
      expect(b.state.value.targets.single.playable, isTrue);
      await b.dispose();
    },
  );

  test('cast sends the local stream URL, pauses local; stop returns the TV position', () async {
    final b = bridge();
    local.emitMediaInfo(_mp4);
    await Future<void>.delayed(Duration.zero);
    final t = await targets(b);
    await local.play();
    await b.cast(t.single.id);
    expect(session.loaded!.url, url.toString());
    expect(local.currentState.isPlaying, isFalse);
    expect(b.state.value.castingTo, 'Living Room');
    session.updatePosition(const Duration(seconds: 90));
    await Future<void>.delayed(Duration.zero);
    expect(b.state.value.position, const Duration(seconds: 90));
    await b.stop();
    expect(session.calls, containsAllInOrder(['stop', 'disconnect']));
    expect(local.recordedSeeks.last, const Duration(seconds: 90));
    expect(b.state.value.castingTo, isNull);
    await b.dispose();
  });

  test(
    'transform failure during LOAD reaches UI before load completes',
    () async {
      final b = bridge();
      local.emitMediaInfo(_mp4);
      await Future<void>.delayed(Duration.zero);
      final t = await targets(b);
      session.errorWhileLoading = const CastTransformFailure();
      await b.cast(t.single.id);
      expect(b.state.value.error, 'Not compatible — pick another quality');
      session.updatePosition(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(b.state.value.error, 'Not compatible — pick another quality');
      await b.dispose();
    },
  );

  test('background transform failure reaches the cast UI', () async {
    final b = bridge();
    local.emitMediaInfo(_mp4);
    await Future<void>.delayed(Duration.zero);
    final t = await targets(b);
    await b.cast(t.single.id);
    session.reportError(const CastTransformFailure());
    await Future<void>.delayed(Duration.zero);
    expect(b.state.value.error, 'Not compatible — pick another quality');
    await b.dispose();
  });

  test(
    'connect failure surfaces a plain message and keeps local playback',
    () async {
      final b = CastBridge(
        service: CastService(
          discoveryProviders: [
            _Provider(CastProtocol.chromecast, [_cc('10.0.0.2')]),
          ],
          sessionFactory: (d) => throw StateError('refused'),
        ),
        controller: local,
        url: url,
        title: 'Movie',
        logger: MemoryLogger(),
      );
      local.emitMediaInfo(_mp4);
      await Future<void>.delayed(Duration.zero);
      final t = await targets(b);
      await b.cast(t.single.id);
      expect(b.state.value.error, "Couldn't cast to Living Room");
      expect(b.state.value.castingTo, isNull);
      await b.dispose();
    },
  );

  group('AirPlay', () {
    // SYNTHETIC native side: no Apple TV on this LAN.
    late AirPlaySession air;
    late StreamController<dynamic> events;
    late List<MethodCall> native;
    const channel = MethodChannel('cast/airplay');

    CastBridge airBridge() => CastBridge(
      service: CastService(
        discoveryProviders: [_Provider(CastProtocol.dlna, [])],
      ),
      controller: local,
      url: url,
      title: 'Movie',
      logger: MemoryLogger(),
      createAirPlay: () => air,
    );

    setUp(() async {
      native = [];
      events = StreamController<dynamic>.broadcast();
      air = AirPlaySession(channel: channel, events: events.stream);
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            native.add(c);
            return null;
          });
    });
    tearDown(() async {
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));
    Future<void> emit(String state, bool external, int ms) async {
      events.add({
        'state': state,
        'external': external,
        'positionMs': ms,
        'durationMs': 600000,
      });
      await settle();
    }

    test('MP4: AirPlay entry with the proxy URL prepared; MKV: entry shown unplayable', () async {
      final b = airBridge();
      local.emitMediaInfo(_mkv);
      await settle();
      await b.startDiscovery();
      await settle();
      expect(b.state.value.airPlayAvailable, isTrue);
      expect(b.state.value.airPlayPlayable, isFalse);
      expect(native, isEmpty);
      local.emitMediaInfo(_mp4);
      await settle();
      expect(b.state.value.airPlayAvailable, isTrue);
      expect(b.state.value.airPlayPlayable, isTrue);
      expect(native.single.method, 'prepare');
      expect((native.single.arguments as Map)['url'], url.toString());
      await b.dispose();
    });

    test('route taken: local pauses, TV starts at local position; route lost resumes local', () async {
      final b = airBridge();
      local.emitMediaInfo(_mp4);
      await settle();
      await local.play();
      await local.seek(const Duration(seconds: 42));
      await b.startDiscovery();
      await settle();
      await emit('paused', true, 0);
      expect(local.currentState.isPlaying, isFalse);
      expect(b.state.value.castingTo, 'AirPlay');
      expect(
        native.map((c) => c.method),
        containsAllInOrder(['prepare', 'seek', 'play']),
      );
      expect(
        (native.firstWhere((c) => c.method == 'seek').arguments
            as Map)['positionMs'],
        42000,
      );
      await emit('playing', true, 90000);
      expect(b.state.value.isPlaying, isTrue);
      await emit('paused', false, 91000);
      expect(b.state.value.castingTo, isNull);
      expect(local.recordedSeeks.last, const Duration(seconds: 91));
      expect(native.last.method, 'stop');
      await b.dispose();
    });

    test(
      'closing the picker without choosing releases the AirPlay player',
      () async {
        final b = airBridge();
        local.emitMediaInfo(_mp4);
        await settle();
        await b.startDiscovery();
        await settle();
        await b.stopDiscovery();
        expect(native.last.method, 'stop');
        expect(
          b.state.value.airPlayAvailable,
          isTrue,
          reason: 'state is stale until the picker reopens',
        );
        await b.dispose();
      },
    );
  });

  testWidgets('composed player route shows the cast button when wired', (
    tester,
  ) async {
    final source = SourceSpec(
      kind: SourceKind.httpUrl,
      uri: Uri.parse('https://example.invalid/a.mp4'),
    );
    const media = MediaItem(id: 'm', title: 'Movie', kind: MediaKind.movie);
    final ctl = FakePlaybackController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (_, _) => PlaybackSession(
            media: media,
            source: source,
            streamSource: _Streams(),
            controllerFactory: () => ctl,
          ),
          createVideoSurface: () => FakeVideoSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
          createCast: (s) => CastBridge(
            service: CastService(),
            controller: s.controller!,
            url: s.handle!.playbackUri,
            title: media.title,
            logger: MemoryLogger(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('cast-button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Streams implements StreamSource {
  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async => _Handle(spec.uri);

  @override
  Future<int> clearCache() async => 0;
}

final class _Handle implements StreamHandle {
  _Handle(this.playbackUri);
  @override
  final Uri playbackUri;
  @override
  int? get totalBytes => null;
  @override
  Stream<SourceStatus> get status => const Stream<SourceStatus>.empty();
  @override
  Future<void> seekHint(int byteOffset) async {}
  @override
  Future<void> dispose() async {}
}
