import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/surface/surface_output.dart';
import 'package:transport/transport.dart';
import 'package:video_player/play_link.dart';

/// Serves [root] with Range support (what aria2 and the probe need).
Future<HttpServer> _serve(Directory root) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final file = File('${root.path}${request.uri.path}');
    final response = request.response;
    if (!file.existsSync()) {
      response.statusCode = 404;
      return response.close();
    }
    final total = file.lengthSync();
    var start = 0;
    var end = total - 1;
    final range = RegExp(r'bytes=(\d*)-(\d*)')
        .firstMatch(request.headers.value('range') ?? '');
    if (range != null) {
      if (range[1]!.isNotEmpty) start = int.parse(range[1]!);
      if (range[2]!.isNotEmpty) end = int.parse(range[2]!).clamp(0, total - 1);
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('Content-Range', 'bytes $start-$end/$total');
    }
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.contentType = request.uri.path.endsWith('.torrent')
        ? ContentType('application', 'x-bittorrent')
        : request.uri.path.endsWith('.m3u8')
        ? ContentType('application', 'vnd.apple.mpegurl')
        : ContentType.binary;
    response.contentLength = end - start + 1;
    if (request.method != 'HEAD') {
      await response.addStream(file.openRead(start, end + 1));
    }
    await response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Directory web;
  late HttpServer server;
  late StreamSourceImpl source;
  late LinkResolver resolver;
  late String base;
  late String appDir;
  final transportLogger = MemoryLogger();
  final seederErrors = <String>[];

  Future<void> ffmpeg(List<String> args) async {
    final r = await Process.run('ffmpeg', ['-v', 'error', '-y', ...args]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
  }

  setUpAll(() async {
    final libmpv = Platform.environment['PLAYBACK_LIBMPV'];
    if (libmpv == null || !File(libmpv).existsSync()) {
      throw StateError('PLAYBACK_LIBMPV must name the repo-built mpv library');
    }
    HttpOverrides.global = null; // flutter_test answers every request 400
    // The transport loader finds the libtorrent shim relative to the repo root.
    appDir = Directory.current.path;
    Directory.current = Directory.current.parent;
    mk.MediaKit.ensureInitialized(libmpv: libmpv);
    dir = await Directory.systemTemp.createTemp('play-link-playback-');
    web = Directory('${dir.path}/web')..createSync();
    const video = [
      '-f', 'lavfi', '-i', 'testsrc=size=64x64:rate=24:duration=6', //
      '-c:v', 'mpeg4',
    ];
    await ffmpeg([...video, '${web.path}/clip.mkv']);
    // Raw low-resolution video exceeds 4 MiB without expensive encoding.
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'testsrc=size=128x128:rate=24:duration=8',
      '-c:v',
      'rawvideo',
      '-pix_fmt',
      'yuv420p',
      '-threads',
      '1',
      '${web.path}/slow.mkv',
    ]);
    await ffmpeg([
      ...video,
      '-f', 'hls', '-hls_time', '1', '-hls_list_size', '0', //
      '-hls_segment_filename', '${web.path}/seg%d.ts', '${web.path}/live.m3u8',
    ]);
    server = await _serve(web);
    base = 'http://127.0.0.1:${server.port}';
    source = StreamSourceImpl(
      logger: transportLogger,
      cacheDir: Directory('${dir.path}/cache'),
    );
    resolver = LinkResolver(torrentDir: Directory('${dir.path}/torrents'));
  });
  tearDownAll(() async {
    await source.dispose();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  /// Resolves [input] and plays it in real mpv until `playback-time` > 0.
  Future<SourceKind> play(String input, {bool slow = false}) async {
    final spec = await resolver.resolve(input);
    final timeline = <String>[];
    final clock = Stopwatch()..start();
    StreamSubscription<Object?>? torrentSubscription;
    void watchTorrent() {
      torrentSubscription ??= source.nativeTorrentSession?.alerts.listen((
        event,
      ) {
        timeline.add(
          '${clock.elapsedMilliseconds}ms kind=${event.kind} '
          'piece=${event.piece} peers=${event.peers}: ${event.message}',
        );
      });
    }

    watchTorrent();
    final handle = await source
        .open(
          spec,
          options: TransportOptions(
            streamDownloadBytesPerSecond: slow ? 512 * 1024 : 0,
            maxHttpConnections: slow ? 1 : 0,
          ),
        )
        .timeout(const Duration(seconds: 40));
    watchTorrent();
    timeline.add('${clock.elapsedMilliseconds}ms source open');
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    await (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
    final engineLogs = <String>[];
    final logSubscription = player.stream.log.listen((event) {
      engineLogs.add('$event');
    });
    final logger = MemoryLogger();
    final controller = MediaKitPlaybackController(
      logger: logger,
      player: player,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless'),
        texture: () async {},
        logger: logger,
        onError: (e, s) => fail('surface error: $e'),
      ),
    );
    try {
      await controller.open(
        handle.playbackUri,
        engineOptions: slow ? const {'network-timeout': '5'} : const {},
      );
      await controller.play();
      final backend = player.platform as mk.NativePlayer;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var time = 0.0;
      while (time <= 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        time = double.tryParse(await backend.getProperty('playback-time')) ?? 0;
      }
      final stats = time <= 0 && handle is TransportStatsProvider
          ? await (handle as TransportStatsProvider).readStats()
          : null;
      expect(
        time,
        greaterThan(0),
        reason:
            'mpv playback-time for $input; failure=${controller.currentState.failure}\n'
            '${[...transportLogger.records, ...logger.records].map((r) => "${r.message}: ${r.error}; ${r.data}").join("\n")}\n'
            'transport: downloaded=${stats?.downloadedBytes}, '
            'rate=${stats?.downloadBytesPerSecond}, '
            'pieces=${stats?.torrent?.piecesHave}/${stats?.torrent?.piecesTotal}, '
            'peers=${stats?.torrent?.peers}, seeds=${stats?.torrent?.seeds}\n'
            'torrent timeline: ${timeline.join("\n")}\n'
            'engine logs: ${engineLogs.join("\n")}\n'
            'seeder stderr: ${seederErrors.join("\n")}',
      );
      if (slow) {
        final first = await (handle as TransportStatsProvider).readStats();
        expect(
          first.downloadedBytes,
          lessThan(4 * 1024 * 1024),
          reason: 'play starts before a full serving window downloads',
        );
        final startPosition = controller.currentState.position;
        await controller.state.firstWhere(
          (s) => s.position > startPosition + const Duration(seconds: 1),
        );
        // Finish reading the short fixture before closing its native download.
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(handle.playbackUri))
              .close();
          expect(
            await response.fold<int>(0, (sum, bytes) => sum + bytes.length),
            handle.totalBytes,
          );
        } catch (error) {
          final snapshot = await (handle as TransportStatsProvider).readStats();
          throw StateError(
            '$error\n'
            'transport downloaded=${snapshot.downloadedBytes} '
            'pieces=${snapshot.torrent?.piecesHave}/${snapshot.torrent?.piecesTotal}\n'
            '${transportLogger.records.map((r) => "${r.message}: ${r.error}").join("\n")}\n'
            'torrent timeline: ${timeline.join("\n")}\n'
            'engine logs: ${engineLogs.join("\n")}',
          );
        } finally {
          client.close(force: true);
        }
        final next = await (handle as TransportStatsProvider).readStats();
        expect(
          next.downloadedBytes,
          greaterThan(first.downloadedBytes),
          reason: 'transport keeps reading after playback starts',
        );
      }
      expect(controller.currentState.failure, isNull);
      return spec.kind;
    } finally {
      await torrentSubscription?.cancel();
      await logSubscription.cancel();
      await controller.dispose();
      await handle.dispose();
    }
  }

  test('direct http .mkv plays', () async {
    expect(await play('$base/clip.mkv'), SourceKind.httpUrl);
  });

  test('slow HTTP starts and keeps reading before 4 MiB downloads', () async {
    expect(await play('$base/slow.mkv', slow: true), SourceKind.httpUrl);
  });

  test(
    'slow torrent starts and keeps reading before 4 MiB downloads',
    () async {
      final seeder = await Process.start('python3', [
        '$appDir/test/support/link_seeder.py',
        '${web.path}/slow.mkv',
        '${web.path}/slow.torrent',
      ]);
      final seederErrorsSubscription = seeder.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(seederErrors.add);
      try {
        final line = await seeder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((l) => l.startsWith('magnet='));
        expect(
          await play(line.substring('magnet='.length), slow: true),
          SourceKind.torrentMagnet,
        );
      } finally {
        seeder.kill(ProcessSignal.sigkill);
        await seeder.exitCode;
        await seederErrorsSubscription.cancel();
      }
    },
  );

  test('HLS .m3u8 plays', () async {
    expect(await play('$base/live.m3u8'), SourceKind.hlsUrl);
  });

  group('torrent', () {
    late Process seeder;
    late String magnet;
    late StreamSubscription<String> seederErrorsSubscription;

    setUpAll(() async {
      seeder = await Process.start('python3', [
        '$appDir/test/support/link_seeder.py',
        '${web.path}/clip.mkv',
        '${web.path}/clip.torrent',
      ]);
      final line = Completer<String>();
      seeder.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) {
            if (l.startsWith('magnet=') && !line.isCompleted) line.complete(l);
          });
      seederErrorsSubscription = seeder.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(seederErrors.add);
      magnet = (await line.future.timeout(const Duration(seconds: 30)))
          .substring('magnet='.length);
    });
    tearDownAll(() async {
      seeder.kill(ProcessSignal.sigkill);
      await seeder.exitCode;
      await seederErrorsSubscription.cancel();
    });

    test('local .torrent file plays', () async {
      expect(await play('${web.path}/clip.torrent'), SourceKind.torrentFile);
    });

    test('torrent URL plays', () async {
      expect(await play('$base/clip.torrent'), SourceKind.torrentFile);
    });

    test('magnet plays', () async {
      expect(await play(magnet), SourceKind.torrentMagnet);
    });
  });
}
