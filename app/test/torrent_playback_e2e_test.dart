import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';
import 'package:ui/ui.dart';
import 'package:video_player/playback_session.dart';
import 'package:video_player/ui_bindings.dart';

/// A real libtorrent session fed by the repo's local torrent fixture (one
/// 32 MiB file, a seeding peer on loopback). Torrents stopped playing after
/// the round-2 UI work (a hint that matches no file in the torrent threw and
/// the player stayed black); these tests keep the whole path honest.
class _Fixture {
  late final Process process;
  late final String magnet;
  final _lines = <String>[];
  late final StreamSubscription<String> _out;
  late final StreamSubscription<String> _err;

  Future<void> start() async {
    process = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: '../packages/transport');
    final ready = Completer<void>();
    _out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _lines.add(line);
          if (line.startsWith('magnet=')) {
            magnet = line.substring('magnet='.length);
            if (!ready.isCompleted) ready.complete();
          }
        });
    _err = process.stderr.transform(utf8.decoder).listen(_lines.add);
    await ready.future.timeout(const Duration(seconds: 30));
  }

  Future<void> stop() async {
    await _out.cancel();
    await _err.cancel();
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -9;
      },
    );
  }
}

class _OpenRecorder extends FakePlaybackController {
  Uri? opened;

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {
    opened = uri;
    await super.open(
      uri,
      headers: headers,
      startAt: startAt,
      engineOptions: engineOptions,
    );
  }
}

/// A source whose open fails the way the real torrent path does for a file
/// hint that matches nothing (see the previous test).
class _FailingSource implements StreamSource {
  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async => throw const TransportFailure.torrentFileNotFound(
    cause: 'fileHint matched no file in the torrent',
  );

  @override
  Future<int> clearCache() async => 0;
}

Future<List<int>> _range(Uri uri, int start, int end) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    return await response.fold<List<int>>(<int>[], (all, c) => all..addAll(c));
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _Fixture fixture;
  late Directory cache;
  late StreamSourceImpl streams;
  late MemoryLogger log;
  const media = MediaItem(
    id: 'tmdb:movie:1',
    title: 'T',
    kind: MediaKind.movie,
  );

  setUpAll(() {
    // flutter_test answers every HttpClient request with 400 unless lifted.
    HttpOverrides.global = null;
  });
  setUp(() async {
    fixture = _Fixture();
    await fixture.start();
    cache = await Directory.systemTemp.createTemp('torrent-app-e2e-');
    log = MemoryLogger();
    streams = StreamSourceImpl(logger: log, cacheDir: cache);
  });
  tearDown(() async {
    await streams.dispose();
    await cache.delete(recursive: true);
    await fixture.stop();
  });

  // The spec a torrent search result produces: multi-line label with release
  // group and seeders.
  SourceSpec spec({String? fileHint}) => SourceSpec(
    kind: SourceKind.torrentMagnet,
    uri: Uri.parse(fixture.magnet),
    fileHint: fileHint,
    label: 'Fixture.2020.1080p.x265-YIFY\n1.0 GB\nRelease group: YIFY\nSeeders: 12',
    quality: '1080p',
  );

  test(
    'picking a torrent result starts libtorrent and reaches playback',
    () async {
      final controller = _OpenRecorder();
      final session = PlaybackSession(
        media: media,
        source: spec(),
        streamSource: streams,
        controllerFactory: () => controller,
      );
      await session.start().timeout(const Duration(seconds: 60));
      expect(controller.opened, isNotNull);
      expect(controller.opened, session.handle!.playbackUri);
      final bytes = await _range(controller.opened!, 0, 4095);
      expect(bytes, orderedEquals(List<int>.generate(4096, (i) => i % 251)));
      // The stats popover reads the live libtorrent counters of this handle.
      final stats = await (session.handle! as TransportStatsProvider)
          .readStats();
      expect(stats.torrent!.infoHash, hasLength(40));
      await session.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the torrent lives for the whole session: stats polling and new range '
      'requests keep succeeding, and it closes only on session end', () async {
    final controller = _OpenRecorder();
    final session = PlaybackSession(
      media: media,
      source: spec(),
      streamSource: streams,
      controllerFactory: () => controller,
    );
    await session.start().timeout(const Duration(seconds: 60));
    final handle = session.handle!;
    final uri = handle.playbackUri;
    for (var i = 0; i < 30; i++) {
      // The stats popover polls once a second; mpv opens a fresh range
      // request (a seek) every few seconds.
      await (handle as TransportStatsProvider).readStats();
      if (i % 3 == 0) {
        final at = (i * 977 * 1024) % (30 * 1024 * 1024);
        final bytes = await _range(uri, at, at + 4095);
        expect(
          bytes,
          orderedEquals(List<int>.generate(4096, (k) => (at + k) % 251)),
          reason: 'range at $at, second $i',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await session.dispose();
    expect(
      () => (handle as TransportStatsProvider).readStats(),
      throwsStateError,
      reason: 'closed after the session ended',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'ending the session while mpv is mid-response is quiet, not an error',
    () async {
      final session = PlaybackSession(
        media: media,
        source: spec(),
        streamSource: streams,
        controllerFactory: _OpenRecorder.new,
      );
      await session.start().timeout(const Duration(seconds: 60));
      final client = HttpClient();
      final request = await client.getUrl(session.handle!.playbackUri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final response = await request.close();
      final sub = response.listen((_) {}, onError: (Object _) {});
      await Future<void>.delayed(const Duration(seconds: 2));
      sub.pause();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await session.dispose();
      sub.resume();
      await Future<void>.delayed(const Duration(seconds: 1));
      client.close(force: true);
      expect(
        log.records.where((r) => r.level == LogLevel.error),
        isEmpty,
        reason: 'a normal teardown must not log transport errors',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a torrent whose file hint matches nothing fails with a typed error',
    () async {
      final session = PlaybackSession(
        media: media,
        source: spec(fileHint: 'Some.Other.Name.mkv'),
        streamSource: streams,
        controllerFactory: _OpenRecorder.new,
      );
      await expectLater(
        session.start().timeout(const Duration(seconds: 60)),
        throwsA(isA<TransportFailure>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('a torrent start failure is shown to the viewer, not black', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ComposedPlayerRoute(
          route: PlayerRoute(media, spec(fileHint: 'Some.Other.Name.mkv')),
          createSession: (m, s) => PlaybackSession(
            media: m,
            source: s,
            streamSource: _FailingSource(),
            controllerFactory: _OpenRecorder.new,
          ),
          createVideoSurface: () => const FakeVideoSurface(),
          logger: MemoryLogger(),
          setSystemUiMode: (_) async {},
        ),
      ),
    );
    // Timers created under the test clock only fire when it is pumped, so
    // advance real time and the test clock together.
    for (var i = 0; i < 600 && find.byType(ErrorView).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
