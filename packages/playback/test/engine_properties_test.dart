import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/surface/surface_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || path.isEmpty) {
      fail('PLAYBACK_LIBMPV must point at the bundled libmpv');
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
  });
  test('stats properties are readable from the real engine', () async {
    final dir = await Directory.systemTemp.createTemp('stats-props-');
    final srt = File('${dir.path}/s.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:02,000\nhello\n');
    final clip = File('${dir.path}/clip.mkv');
    final made = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=320x180:rate=24:duration=3',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000:duration=3',
      '-i',
      srt.path,
      '-map',
      '0:v',
      '-map',
      '1:a',
      '-map',
      '2:0',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-c:s',
      'srt',
      '-metadata:s:s:0',
      'language=eng',
      '-t',
      '6',
      '-y',
      clip.path,
    ]);
    expect(made.exitCode, 0, reason: made.stderr.toString());
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    await (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless'),
        texture: () async {},
        logger: MemoryLogger(),
        onError: (error, stack) => fail('surface error: $error'),
      ),
    );
    try {
      expect(controller, isA<EngineProperties>());
      await controller.open(clip.uri);
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final values = await controller.readProperties(playerStatsProperties);
      // Every property the overlay reads must exist in the bundled mpv 0.36
      // for a normal file; the reason is the list of those that did not.
      // video-bitrate is only reported when the file declares or mpv can
      // measure one (this generated clip does neither): shown as "—".
      final missing = playerStatsProperties
          .where((name) => name != 'video-bitrate')
          .where((name) => !values.containsKey(name))
          .toList();
      expect(missing, isEmpty, reason: 'mpv returned no value for $missing');
      expect(values['file-format'], 'mkv');
      expect(values['video-codec'], startsWith('h264'));
      expect(values['video-params/w'], '320');
      expect(values['video-params/pixelformat'], 'yuv420p');
      expect(values['current-tracks/sub/lang'], 'eng');
      expect(values['mpv-version'], startsWith('mpv 0.36'));
      expect(double.parse(values['container-fps']!), closeTo(24, 0.01));
      expect(int.parse(values['cache-speed']!), greaterThanOrEqualTo(0));
    } finally {
      await controller.dispose();
      await dir.delete(recursive: true);
    }
  });
}
