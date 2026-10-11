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
import 'package:ui/src/player/stats/stats_popover.dart';
import 'package:video_player/playback_session.dart';
import 'package:video_player/ui_bindings.dart';

/// The player's info panel (the "Downloaded" row) must follow the transport
/// while the title plays: the real app wiring (ComposedPlayerRoute ->
/// PlayerStatsSource -> StatsPopover) over a real transport handle.
const _mib = 1024 * 1024;
const _media = MediaItem(id: 'm', title: 'M', kind: MediaKind.movie);
final _samples = StringBuffer();

double _percent(String text) =>
    double.parse(RegExp(r'\(([\d.]+)%\)').firstMatch(text)!.group(1)!);

Future<void> _record(
  WidgetTester tester,
  String name,
  StreamHandle handle, [
  _MpvStandIn? player,
  PlaybackSession? session,
]) async {
  final panel = find.byKey(const ValueKey('stats-popover-Downloaded'));
  final seen = <double>[];
  for (var i = 0; i < 4; i++) {
    // The test body runs in the real zone: the panel's 1 s poll is a real
    // timer. Wait for the panel to show progress beyond the previous sample
    // instead of sleeping a fixed time: the poll and the download both slip
    // under CPU load, so a fixed interval sometimes sees the same value twice.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      if (panel.evaluate().isNotEmpty) {
        final shown = _percent(tester.widget<Text>(panel).data!);
        if (seen.isEmpty || shown > seen.last) {
          seen.add(shown);
          break;
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        final popovers = find.byType(StatsPopover).evaluate();
        final controllers = popovers.map(
          (e) => (e.widget as StatsPopover).controller,
        );
        throw StateError(
          'Downloaded row did not advance past ${seen.isEmpty ? "start" : seen.last}%; '
          'row=${panel.evaluate().length}; popovers=${popovers.length}; '
          'snapshots=${controllers.map((c) => "transport=${c.snapshot.transport}, error=${c.error}, polling=${c.isPolling}").join("; ")}; '
          'samples=$seen; played=${player?.read}; '
          'session failure=${session?.snapshot.failure}; '
          'playback=${session?.snapshot.playback}',
        );
      }
    }
    _samples.writeln(
      '$name sample ${i + 1}: panel=${seen.last}% played=${(player?.read ?? 0) ~/ _mib} MiB',
    );
  }
  // Stop playing and let the transport settle, then compare like for like.
  await player?.stop();
  await Future<void>.delayed(const Duration(seconds: 3));
  final stats = await (handle as TransportStatsProvider).readStats();
  // Settle: one more poll, then compare with the transport's own figure.
  await Future<void>.delayed(const Duration(milliseconds: 1300));
  await tester.pump();
  final finalPanel = _percent(tester.widget<Text>(panel).data!);
  final transport = stats!.downloadedBytes * 100 / stats.totalBytes!;
  _samples.writeln(
    '$name final: panel=$finalPanel% transport=${transport.toStringAsFixed(2)}%',
  );
  for (var i = 1; i < seen.length; i++) {
    expect(seen[i], greaterThan(seen[i - 1]), reason: '$name samples $seen');
  }
  expect(
    (finalPanel - transport).abs(),
    lessThanOrEqualTo(1.0),
    reason: '$name: panel vs the transport\'s own progress',
  );
}

Future<void> _openPanel(
  WidgetTester tester,
  StreamSource streams,
  SourceSpec spec,
  TransportOptions options,
  void Function(PlaybackSession) onSession,
) async {
  // Real transport I/O must start outside the test's fake-async zone.
  final handle = await streams.open(spec, options: options);
  streams = _PreOpened(handle);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: ComposedPlayerRoute(
        route: PlayerRoute(_media, spec),
        createSession: (m, s) {
          final session = PlaybackSession(
            media: m,
            source: s,
            streamSource: streams,
            controllerFactory: () =>
                FakePlaybackController()
                  ..setDuration(const Duration(minutes: 90)),
          );
          onSession(session);
          return session;
        },
        createVideoSurface: () => FakeVideoSurface(),
        logger: MemoryLogger(),
        setSystemUiMode: (_) async {},
      ),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    if (find.byKey(const ValueKey('player-box-stats')).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.tap(find.byKey(const ValueKey('player-box-stats')));
  await tester.pump(const Duration(milliseconds: 300));
  final popover = tester.widget<StatsPopover>(find.byType(StatsPopover));
  final controller = popover.controller;
  // Rendering the panel does not await its asynchronous first transport read.
  if (controller.snapshot.transport == null) {
    final ready = Completer<void>();
    void onStats() {
      if (ready.isCompleted) return;
      if (controller.error case final error?) {
        ready.completeError(error);
      } else if (controller.snapshot.transport != null) {
        ready.complete();
      }
    }

    controller.addListener(onStats);
    onStats();
    try {
      await ready.future;
    } finally {
      controller.removeListener(onStats);
    }
  }
  await tester.pump();
  expect(
    find.byKey(const ValueKey('stats-popover-Downloaded')),
    findsOneWidget,
  );
}

/// Plays the title like mpv would: one open-ended read consumed at a steady
/// rate, so the play head (and the cache window) moves slowly.
class _MpvStandIn {
  _MpvStandIn(this.uri, this.bytesPerSecond);
  final Uri uri;
  final int bytesPerSecond;
  final HttpClient _client = HttpClient();
  int read = 0;
  StreamSubscription<List<int>>? _data;

  Future<void> start() async {
    final req = await _client.getUrl(uri);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final resp = await req.close();
    final data = _data = resp.listen(null, onError: (Object _) {});
    data.onData((chunk) {
      read += chunk.length;
      data.pause(
        Future<void>.delayed(
          Duration(microseconds: chunk.length * 1000000 ~/ bytesPerSecond),
        ),
      );
    });
  }

  Future<void> stop() async {
    await _data?.cancel();
    _client.close(force: true);
  }
}

/// Hands the session a handle that was already opened in the real zone.
class _PreOpened implements StreamSource {
  _PreOpened(this.handle);
  final StreamHandle handle;
  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async => handle;
  @override
  Future<int> clearCache() async => 0;
}

void main() {
  final appDir = Directory.current;
  late Directory samplesDir;
  setUpAll(() async {
    samplesDir = await Directory.systemTemp.createTemp('progress-samples-');
    HttpOverrides.global = null;
    // The native transport libraries are found relative to packages/transport.
    Directory.current = '../packages/transport';
  });
  tearDownAll(() async {
    Directory.current = appDir;
    try {
      await File('${samplesDir.path}/progress_samples.txt')
          .writeAsString(_samples.toString());
    } finally {
      await samplesDir.delete(recursive: true);
    }
  });

  testWidgets('download row waits for the first asynchronous stats snapshot', (
    tester,
  ) async {
    final firstRead = Completer<TransportStats>();
    final controller = PlayerStatsController(
      PlayerStatsSource(
        kind: SourceKind.httpUrl,
        readTransport: () => firstRead.future,
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Scaffold(
          body: StatsPopover(controller: controller, onAdvanced: () {}),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('stats-popover-Downloaded'));
    expect(find.byType(StatsPopover), findsOneWidget);
    expect(row, findsNothing);
    firstRead.complete(
      const TransportStats(
        downloadBytesPerSecond: 1,
        downloadedBytes: 1,
        totalBytes: 10,
      ),
    );
    await tester.pump();
    expect(row, findsOneWidget);
    expect(tester.widget<Text>(row).data, contains('(10%)'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTTP: info panel download % follows the transport', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const size = 96 * _mib;
      final upstream = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
      final chunk = List<int>.filled(_mib, 7);
      final sub = upstream.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        if (request.method == 'HEAD') {
          request.response.headers
            ..set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..contentLength = size;
          await request.response.close();
          return;
        }
        var start = 0, end = size - 1;
        if (range != null) {
          final parts = range.substring(6).split('-');
          start = int.parse(parts.first);
          end = parts.last.isEmpty ? size - 1 : int.parse(parts.last);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/$size',
          );
        }
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = end - start + 1;
        try {
          var sent = 0;
          final len = end - start + 1;
          while (sent < len) {
            final n = (len - sent) > chunk.length ? chunk.length : len - sent;
            request.response.add(chunk.sublist(0, n));
            sent += n;
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          await request.response.close();
        } catch (_) {}
      });
      final cache = (await Directory.systemTemp.createTemp('progress-http-'));
      final streams = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
      PlaybackSession? session;
      _MpvStandIn? player;
      try {
        await _openPanel(
          tester,
          streams,
          SourceSpec(
            kind: SourceKind.httpUrl,
            uri: Uri.parse('http://127.0.0.1:${upstream.port}/m.bin'),
          ),
          const TransportOptions(cacheLimitBytes: 16 * _mib),
          (s) => session = s,
        );
        player = _MpvStandIn(session!.handle!.playbackUri, 4 * _mib);
        await player.start();
        await _record(tester, 'http', session!.handle!, player, session);
      } finally {
        await player?.stop();
        await session?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await streams.dispose();
        await sub.cancel();
        await upstream.close(force: true);
        await cache.delete(recursive: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('torrent: info panel download % follows the transport', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A seeder limited to 2 MiB/s: the download takes about 30 s.
      final work = await Directory.systemTemp.createTemp('progress-bt-');
      final media = File('${work.path}/seed/clip.bin')
        ..createSync(recursive: true);
      final raf = media.openSync(mode: FileMode.write);
      final block = List<int>.generate(_mib, (i) => i % 251);
      for (var i = 0; i < 64; i++) {
        raf.writeFromSync(block);
      }
      raf.closeSync();
      final process = await Process.start('python3', <String>[
        'test/harness/torrent_seeder.py',
        media.path,
        '${2 * _mib}',
      ], workingDirectory: '.');
      final ready = Completer<String>();
      final out = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) {
            if (l.startsWith('magnet=') && !ready.isCompleted) {
              ready.complete(l.substring(7));
            }
          });
      final err = process.stderr.listen((_) {});
      try {
        final magnet = await ready.future.timeout(const Duration(seconds: 30));
        final cache = await Directory.systemTemp.createTemp('progress-bt-c-');
        final streams = StreamSourceImpl(
          logger: MemoryLogger(),
          cacheDir: cache,
        );
        PlaybackSession? session;
        _MpvStandIn? player;
        try {
          await _openPanel(
            tester,
            streams,
            SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(magnet)),
            const TransportOptions(cacheLimitBytes: 12 * _mib),
            (s) => session = s,
          );
          player = _MpvStandIn(session!.handle!.playbackUri, 2 * _mib);
          await player.start();
          await _record(tester, 'torrent', session!.handle!, player, session);
        } finally {
          await player?.stop();
          await session?.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await streams.dispose();
          await cache.delete(recursive: true);
        }
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await out.cancel();
        await err.cancel();
        await work.delete(recursive: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
