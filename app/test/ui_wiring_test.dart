import 'package:contracts/contracts.dart';

import 'dart:async';

import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:platform_services/platform_services.dart';

import 'package:video_player/fixture_provider.dart';
import 'package:video_player/playback_session.dart';
import 'package:video_player/ui_bindings.dart';

void main() {
  final source = SourceSpec(
    kind: SourceKind.httpUrl,
    uri: Uri.parse('https://example.invalid/fixture.mp4'),
  );

  testWidgets('remote media keys skip +30 s forward and -10 s back', (
    tester,
  ) async {
    const media = MediaItem(id: 'keys', title: 'Keys', kind: MediaKind.movie);
    final controller = FakePlaybackController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: _TestStreamSource(),
            controllerFactory: () => controller,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    controller.advanceTo(const Duration(seconds: 100));
    await tester.pump();
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    await press(LogicalKeyboardKey.mediaFastForward);
    await press(LogicalKeyboardKey.mediaTrackNext);
    await press(LogicalKeyboardKey.mediaRewind);
    await press(LogicalKeyboardKey.mediaTrackPrevious);
    expect(controller.recordedSeeks, const [
      Duration(seconds: 130),
      Duration(seconds: 160),
      Duration(seconds: 150),
      Duration(seconds: 140),
    ]);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('media session follows playback and route disposal', (
    tester,
  ) async {
    const media = MediaItem(
      id: 'session',
      title: 'Session movie',
      subtitle: 'Episode',
      kind: MediaKind.movie,
    );
    final channel = _MediaChannel();
    var now = DateTime(2026);
    final service = MediaSessionService(channel: channel, now: () => now);
    final controller = FakePlaybackController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: _TestStreamSource(),
            controllerFactory: () => controller,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
          mediaSession: service,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(channel.payloads.last['title'], 'Session movie');
    expect(channel.payloads.last['subtitle'], 'Episode');
    expect(channel.payloads.last['playing'], true);
    controller.setDuration(const Duration(seconds: 45));
    await tester.pump();
    expect(channel.payloads.last['durationSeconds'], 45.0);
    await controller.pause();
    await tester.pump();
    expect(channel.payloads.last['playing'], false);
    now = now.add(const Duration(seconds: 1));
    await controller.seek(const Duration(seconds: 12));
    await tester.pump();
    expect(channel.payloads.last['positionSeconds'], 12.0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(channel.calls.last, PlatformMethods.mediaSessionClear);
    final updates = channel.calls
        .where((call) => call == PlatformMethods.mediaSessionUpdate)
        .length;
    await tester.pump();
    expect(
      channel.calls.where((call) => call == PlatformMethods.mediaSessionUpdate),
      hasLength(updates),
    );
    await tester.runAsync(() async {
      await service.dispose();
      await channel.dispose();
    });
  });

  testWidgets('media session is cleared on a terminal playback failure', (
    tester,
  ) async {
    const media = MediaItem(
      id: 'session',
      title: 'Session movie',
      kind: MediaKind.movie,
    );
    final channel = _MediaChannel();
    final service = MediaSessionService(channel: channel);
    final controller = FakePlaybackController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: _TestStreamSource(),
            controllerFactory: () => controller,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
          mediaSession: service,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    controller.failWith(
      PlaybackFailure.engineCrashed(cause: StateError('terminal')),
    );
    await tester.pump();
    await tester.pump();
    expect(channel.calls.last, PlatformMethods.mediaSessionClear);
    expect(find.byType(ErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await service.dispose();
      await channel.dispose();
    });
  });

  testWidgets('typed fixture route reaches PlayerScreen with the real seam', (
    tester,
  ) async {
    final provider = FixtureProvider();
    const media = MediaItem(
      id: 'fixture-episode',
      title: 'Fixture Episode',
      kind: MediaKind.episode,
      subtitle: 'S01E01',
    );
    final stream = _TestStreamSource();
    final sessions = <PlaybackSession>[];
    MediaItem? resolvedMedia;
    SourceSpec? resolvedSource;
    var surfaceCreated = false;

    PlaybackSession sessionFactory(MediaItem media, SourceSpec selected) {
      resolvedMedia = media;
      resolvedSource = selected;
      final next = FakePlaybackController();
      final session = PlaybackSession(
        media: media,
        source: selected,
        streamSource: stream,
        controllerFactory: () => next,
      );
      sessions.add(session);
      return session;
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(
            media,
            source,
            markers: const <UiMarker>[
              UiMarker(
                id: 'intro',
                kind: UiMarkerKind.intro,
                start: Duration.zero,
                end: Duration(seconds: 12),
              ),
            ],
          ),
          createSession: sessionFactory,
          createVideoSurface: () {
            surfaceCreated = true;
            return const _StaticSurface();
          },
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(resolvedMedia?.id, 'fixture-episode');
    expect(resolvedSource, source);
    expect(sessions, hasLength(1));
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).markers,
      hasLength(1),
    );
    expect(surfaceCreated, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await provider.dispose();
  });

  testWidgets('player gets a stats source: provider, kind and live readers', (
    tester,
  ) async {
    const media = MediaItem(id: 'm', title: 'M', kind: MediaKind.movie);
    final stream = _TestStreamSource();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source, providerName: 'Fixture provider'),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: stream,
            controllerFactory: FakePlaybackController.new,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final stats = tester.widget<PlayerScreen>(find.byType(PlayerScreen)).stats!;
    expect(stats.providerName, 'Fixture provider');
    expect(stats.kind, SourceKind.httpUrl);
    expect(stats.uri, source.uri);
    expect(stats.hasTransferStats, isTrue);
    final read = await stats.readTransport!();
    expect(read.connections, 3);
    // A fake controller has no engine properties: nothing, not an error.
    expect(await stats.readEngine!(['file-format']), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('auto-play next rebinds the player to the new controller', (
    tester,
  ) async {
    const media = MediaItem(id: 'e1', title: 'E1', kind: MediaKind.episode);
    const next = MediaItem(id: 'e2', title: 'E2', kind: MediaKind.episode);
    final settings = AppSettings(MemorySettingsStore());
    await settings.values.write(settingById('playback.autoPlayNext'), true);
    final controllers = <FakePlaybackController>[];
    final surfaced = <PlaybackController>[];
    late PlaybackSession session;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) => session = PlaybackSession(
            media: m,
            source: s,
            streamSource: _TestStreamSource(),
            settings: settings,
            nextSource: (_, _) async => (media: next, source: source),
            controllerFactory: () {
              final controller = FakePlaybackController();
              controllers.add(controller);
              return controller;
            },
          ),
          createVideoSurface: () => _StaticSurface(onBuild: surfaced.add),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).controller,
      same(controllers.first),
    );

    controllers.first.emitEvent(PlaybackEnded());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();

    expect(controllers, hasLength(2));
    expect(session.media.id, 'e2');
    expect(surfaced.last, same(controllers.last));
    await expectLater(controllers.first.play(), throwsStateError);
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).controller,
      same(controllers.last),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('auto-play resolver failure surfaces in the route', (
    tester,
  ) async {
    const media = MediaItem(id: 'e1', title: 'E1', kind: MediaKind.episode);
    final controller = FakePlaybackController();
    final settings = AppSettings(MemorySettingsStore());
    await settings.values.write(settingById('playback.autoPlayNext'), true);
    final logger = MemoryLogger();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: _TestStreamSource(),
            settings: settings,
            logger: logger,
            nextSource: (_, _) async =>
                throw StateError('next episode unavailable'),
            controllerFactory: () => controller,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: logger,
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    controller.emitEvent(PlaybackEnded());
    await tester.runAsync(() => pumpEventQueue(times: 5));
    await tester.pump();
    expect(find.byType(ErrorView), findsOneWidget);
    expect(logger.records.any((record) => record.error != null), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final replaceSource in [false, true]) {
    test(
      replaceSource
          ? 'late next resolution cannot replace a manually switched source'
          : 'duplicate ended events resolve and open the next episode once',
      () async {
        const media = MediaItem(id: 'e1', title: 'E1', kind: MediaKind.episode);
        const next = MediaItem(id: 'e2', title: 'E2', kind: MediaKind.episode);
        final settings = AppSettings(MemorySettingsStore());
        await settings.values.write(settingById('playback.autoPlayNext'), true);
        final pending = Completer<NextEpisode?>();
        final resolving = Completer<void>();
        final controllers = <FakePlaybackController>[];
        var resolutions = 0;
        final session = PlaybackSession(
          media: media,
          source: source,
          streamSource: _TestStreamSource(),
          settings: settings,
          nextSource: (_, _) {
            resolutions++;
            if (!resolving.isCompleted) resolving.complete();
            return pending.future;
          },
          controllerFactory: () {
            final controller = FakePlaybackController();
            controllers.add(controller);
            return controller;
          },
        );
        addTearDown(session.dispose);
        await session.start();
        controllers.first.emitEvent(PlaybackEnded());
        await resolving.future;
        if (replaceSource) {
          await session.switchSource(
            SourceSpec(
              kind: SourceKind.httpUrl,
              uri: Uri.parse('https://example.invalid/manual.mp4'),
            ),
          );
        } else {
          controllers.first.emitEvent(PlaybackEnded());
          await pumpEventQueue(times: 5);
        }
        pending.complete((media: next, source: source));
        await pumpEventQueue(times: 10);
        expect(resolutions, 1);
        expect(controllers, hasLength(2));
        expect(session.controller, same(controllers.last));
        expect(session.media.id, replaceSource ? 'e1' : 'e2');
      },
    );
  }

  testWidgets('local fixture route opens once and forwards play', (
    tester,
  ) async {
    final provider = FixtureProvider();
    const media = MediaItem(
      id: 'fixture-movie',
      title: 'Fixture Movie',
      kind: MediaKind.movie,
    );
    final local = (await provider.resolve(media)).single;
    final stream = _TestStreamSource();
    final controller = _RecordingController();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, local),
          createSession: (_, _) => PlaybackSession(
            media: media,
            source: local,
            streamSource: stream,
            controllerFactory: () => controller,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.openedUris, hasLength(1));
    expect(controller.openedUris.single.isScheme('file'), isTrue);
    expect(
      controller.openedUris.single.toFilePath(),
      contains('Butterfly-209.mp4'),
    );
    controller.setDuration(const Duration(minutes: 90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey<String>('play-pause')));
    await tester.pump();
    expect(controller.playCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await provider.dispose();
  });

  testWidgets(
    'a session factory that throws renders a typed error, not a crash',
    (tester) async {
      const media = MediaItem(
        id: 'fixture-movie',
        title: 'Fixture Movie',
        kind: MediaKind.movie,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: ComposedPlayerRoute(
            route: PlayerRoute(media, source),
            createSession: (_, _) => throw StateError('must not start'),
            createVideoSurface: () => const _StaticSurface(),
            logger: MemoryLogger(),
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('Unable to continue'), findsOneWidget);
    },
  );

  testWidgets(
    'a typed transport failure keeps its code and its real cause is logged',
    (tester) async {
      const media = MediaItem(
        id: 'fixture-movie',
        title: 'Fixture Movie',
        kind: MediaKind.movie,
      );
      final logger = MemoryLogger();
      final cause = StateError('real cause');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: ComposedPlayerRoute(
            route: PlayerRoute(media, source),
            createSession: (_, _) =>
                throw TransportFailure.httpUnreachable(cause: cause),
            createVideoSurface: () => const _StaticSurface(),
            logger: logger,
            setSystemUiMode: (_) async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Show error code'));
      await tester.pump();

      expect(find.text('transport.http.unreachable'), findsOneWidget);
      expect(logger.records.single.error, isA<TransportFailure>());
    },
  );

  testWidgets('the opening screen covers the player until the first frame', (
    tester,
  ) async {
    const media = MediaItem(
      id: 'opening',
      title: 'Opening movie',
      kind: MediaKind.movie,
    );
    final controller = FakePlaybackController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: _TestStreamSource(),
            controllerFactory: () => controller,
          ),
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(StreamOpeningScreen), findsOneWidget);
    expect(find.text('Opening movie'), findsOneWidget);
    expect(find.byKey(const ValueKey('composed-player-screen')), findsOne);

    controller.setDuration(const Duration(minutes: 90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StreamOpeningScreen), findsNothing);
    expect(find.byKey(const ValueKey('composed-player-screen')), findsOne);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a failed opening offers Retry that starts a fresh session', (
    tester,
  ) async {
    const media = MediaItem(
      id: 'retry',
      title: 'Retry movie',
      kind: MediaKind.movie,
    );
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, source),
          createSession: (m, s) {
            attempts++;
            if (attempts == 1) {
              throw TransportFailure.httpUnreachable(cause: 'offline');
            }
            return PlaybackSession(
              media: m,
              source: s,
              streamSource: _TestStreamSource(),
              controllerFactory: FakePlaybackController.new,
            );
          },
          createVideoSurface: () => const _StaticSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.byKey(const ValueKey('composed-player-screen')), findsOne);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test('session source selection remains app-owned and disposable', () async {
    final stream = _TestStreamSource();
    final controllers = <FakePlaybackController>[];
    final session = PlaybackSession(
      media: const MediaItem(
        id: 'fixture-movie',
        title: 'Fixture Movie',
        kind: MediaKind.movie,
      ),
      source: source,
      streamSource: stream,
      controllerFactory: () {
        final controller = FakePlaybackController();
        controllers.add(controller);
        return controller;
      },
    );
    await session.start();
    await session.switchSource(
      SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('https://example.invalid/alternate.mp4'),
      ),
    );
    await session.dispose();
    for (final controller in controllers) {
      await expectLater(controller.play(), throwsStateError);
    }
  });
}

final class _TestStreamSource implements StreamSource {
  final Map<SourceSpec, _TestStreamHandle> _handles = {};

  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async => _handles.putIfAbsent(
    spec,
    () => _TestStreamHandle(spec.uri, spec.expectedBytes),
  );

  @override
  Future<int> clearCache() async => 0;
}

final class _RecordingController extends FakePlaybackController {
  final openedUris = <Uri>[];
  var playCalls = 0;

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {
    openedUris.add(uri);
    await super.open(
      uri,
      headers: headers,
      startAt: startAt,
      engineOptions: engineOptions,
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    await super.play();
  }
}

final class _StaticSurface extends FakeVideoSurface {
  const _StaticSurface({this.onBuild});

  final void Function(PlaybackController)? onBuild;

  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.contain,
    Color background = const Color(0xFF000000),
  }) {
    onBuild?.call(controller);
    return ColoredBox(color: background);
  }
}

final class _TestStreamHandle implements StreamHandle, TransportStatsProvider {
  _TestStreamHandle(this.playbackUri, this.totalBytes) {
    _status.add(
      SourceStatus(
        state: SourceState.resolving,
        available: RangeSet.empty(),
        totalBytes: totalBytes,
        bytesPerSecond: 0,
        peersOrConnections: 0,
      ),
    );
  }

  @override
  final int? totalBytes;

  @override
  final Uri playbackUri;
  final StreamController<SourceStatus> _status =
      StreamController<SourceStatus>.broadcast(sync: true);
  bool _disposed = false;

  @override
  Stream<SourceStatus> get status => _status.stream;

  @override
  Future<TransportStats> readStats() async => const TransportStats(
    downloadBytesPerSecond: 1,
    downloadedBytes: 1,
    connections: 3,
  );

  @override
  Future<void> seekHint(int byteOffset) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _status.close();
  }
}

final class _MediaChannel implements PlatformChannel {
  final _events = StreamController<Object?>.broadcast();
  final calls = <String>[];
  final payloads = <Map<String, Object?>>[];
  @override
  Stream<Object?> get events => _events.stream;
  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    if (arguments is Map) {
      payloads.add(arguments.map((k, v) => MapEntry('$k', v)));
    }
    return const <String, Object?>{'supported': true};
  }

  @override
  Future<void> dispose() => _events.close();
}
