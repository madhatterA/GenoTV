import 'dart:async';
import 'dart:io';

import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/surface/surface_output.dart';
import 'package:transport/transport.dart';
import 'package:video_player/play_link.dart';
import 'package:video_player/playback_session.dart';

/// "Insert link…" on Play: the typed link plays as the title, so progress,
/// resume and Continue Watching belong to the title. Real mpv, local HTTP clip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late HttpServer server;
  late StreamSourceImpl source;
  late LinkResolver resolver;
  late String url;

  setUpAll(() async {
    final libmpv = Platform.environment['PLAYBACK_LIBMPV'];
    if (libmpv == null || !File(libmpv).existsSync()) {
      throw StateError('PLAYBACK_LIBMPV must name the repo-built mpv library');
    }
    HttpOverrides.global = null; // flutter_test answers every request 400
    mk.MediaKit.ensureInitialized(libmpv: libmpv);
    dir = await Directory.systemTemp.createTemp('insert-link-');
    final clip = '${dir.path}/clip.mkv';
    final r = await Process.run('ffmpeg', [
      '-v', 'error', '-y', '-f', 'lavfi', //
      '-i', 'testsrc=size=64x64:rate=24:duration=20', '-c:v', 'mpeg4', clip,
    ]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final file = File(clip);
      final total = file.lengthSync();
      var start = 0;
      var end = total - 1;
      final range = RegExp(r'bytes=(\d*)-(\d*)')
          .firstMatch(request.headers.value('range') ?? '');
      final response = request.response;
      if (range != null) {
        if (range[1]!.isNotEmpty) start = int.parse(range[1]!);
        if (range[2]!.isNotEmpty) {
          end = int.parse(range[2]!).clamp(0, total - 1);
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set('Content-Range', 'bytes $start-$end/$total');
      }
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.contentType = ContentType.binary;
      response.contentLength = end - start + 1;
      if (request.method != 'HEAD') {
        await response.addStream(file.openRead(start, end + 1));
      }
      await response.close();
    });
    url = 'http://127.0.0.1:${server.port}/clip.mkv';
    source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: Directory('${dir.path}/cache'),
    );
    resolver = LinkResolver(torrentDir: Directory('${dir.path}/torrents'));
  });
  tearDownAll(() async {
    await source.dispose();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<void> until(
    bool Function() done,
    String what, [
    Object? Function()? detail,
  ]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue, reason: '$what ${detail?.call()}');
  }

  for (final media in const [
    MediaItem(
      id: 'tmdb:movie:27205',
      title: 'Inception',
      kind: MediaKind.movie,
    ),
    MediaItem(
      id: 'tmdb:episode:1396:1:1',
      title: 'Pilot',
      kind: MediaKind.episode,
      subtitle: 'S01E01',
    ),
  ]) {
    test(
      '${media.kind.name}: link plays as the title, 40 % is saved to it',
      () async {
        final recents = RecentLinks(MemorySettingsStore());
        final progress = FakeProgressRepository();
        final logger = MemoryLogger();

        // What the Insert-link dialog's handler does in the app.
        final prepared = await prepareLink(
          url,
          resolver: resolver,
          recents: recents,
          logger: logger,
          title: media.title,
        );
        expect(recents.entries.single.link, url);
        expect(recents.entries.single.label, media.title);

        final session = PlaybackSession(
          media: media,
          source: prepared.spec,
          streamSource: source,
          progress: progress,
          controllerFactory: () {
            final player = mk.Player(
              configuration: const mk.PlayerConfiguration(vo: 'null'),
            );
            // Headless: without a video output mpv needs vid=auto to run.
            unawaited(
              (player.platform as mk.NativePlayer).setProperty('vid', 'auto'),
            );
            return MediaKitPlaybackController(
              logger: logger,
              player: player,
              output: SurfaceOutput(
                attach: () async => throw UnsupportedError('headless'),
                texture: () async {},
                logger: logger,
                onError: (e, s) => fail('surface error: $e'),
              ),
            );
          },
        );
        await session.start().timeout(const Duration(seconds: 30));
        final controller = session.controller!;
        await until(
          () => controller.currentState.duration > Duration.zero,
          'duration known',
        );
        final duration = controller.currentState.duration;
        await controller.seek(duration * 0.4);
        await controller.pause();
        await until(
          () =>
              (controller.currentState.position.inMilliseconds /
                          duration.inMilliseconds -
                      0.4)
                  .abs() <
              0.03,
          'position near 40 %',
          () => '${controller.currentState.position} of $duration',
        );
        await session.dispose();

        final saved = await progress.get(media.id);
        expect(saved, isNotNull, reason: 'progress is keyed by the title');
        final fraction =
            saved!.position.inMilliseconds / saved.duration.inMilliseconds;
        expect(fraction, closeTo(0.4, 0.03));
        expect(saved.completed, isFalse);
        final continueWatching = await progress.continueWatching();
        expect(continueWatching.map((p) => p.mediaId), [media.id]);
        expect(
          (await progress.get('link:$url')),
          isNull,
          reason: 'nothing is saved against the link',
        );
      },
    );
  }
}
