import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/controller/state_mapper.dart';
import 'package:playback/src/surface/surface_output.dart';

Future<File> _clip(Directory directory, String name, List<String> args) async {
  final clip = File('${directory.path}/$name');
  final result = await Process.run('ffmpeg', [
    '-v',
    'error',
    ...args,
    '-t',
    '2',
    '-y',
    clip.path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return clip;
}

Future<MediaInfo> _infoFor(File clip) async {
  final player = mk.Player(
    configuration: const mk.PlayerConfiguration(vo: 'null'),
  );
  // vo=null makes media_kit disable video; mpv decodes it with vid=auto.
  await (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
  final controller = MediaKitPlaybackController(
    logger: MemoryLogger(),
    player: player,
    output: SurfaceOutput(
      attach: () async => throw UnsupportedError('headless info test'),
      texture: () async {},
      logger: MemoryLogger(),
      onError: (error, stack) => fail('Unexpected surface error: $error'),
    ),
  );
  try {
    final received = <MediaInfo>[];
    controller.mediaInfo.listen(received.add);
    await controller.open(clip.uri);
    // Video parameters only exist once the engine has decoded a frame.
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await controller.pause();
    expect(controller.currentState.failure, isNull);
    expect(received, isNotEmpty);
    final late = await controller.mediaInfo.first.timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('a late listener got no replayed media info'),
    );
    expect(late, received.last, reason: 'late listener gets the latest info');
    return received.last;
  } finally {
    await controller.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
  });

  test('container name follows the file extension', () {
    const mp4 = 'mov,mp4,m4a,3gp,3g2,mj2';
    expect(pickContainerFormat(mp4, '/a/film.MP4'), 'mp4');
    expect(pickContainerFormat(mp4, '/a/clip.mov'), 'mov');
    expect(pickContainerFormat('matroska,webm', '/a/film.mkv'), 'mkv');
    expect(pickContainerFormat('matroska,webm', '/a/film.webm'), 'webm');
    expect(pickContainerFormat(mp4, '/a/stream'), 'mov');
    expect(pickContainerFormat('', '/a/x.mp4'), isNull);
  });

  test('H.264 + AAC stereo + subtitle clip reports its facts', () async {
    final directory = await Directory.systemTemp.createTemp('media-info-');
    try {
      final srt = File('${directory.path}/s.srt')
        ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nhello\n');
      final clip = await _clip(directory, 'sdr.mp4', [
        '-f',
        'lavfi',
        '-i',
        'color=size=64x64:rate=24',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=48000',
        '-i',
        srt.path,
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-ac',
        '2',
        '-c:s',
        'mov_text',
      ]);
      final info = await _infoFor(clip);
      expect(info.container, 'mp4');
      expect(info.fileSizeBytes, clip.lengthSync());
      expect(info.duration!.inMilliseconds, closeTo(2000, 100));
      expect(info.bitrate, greaterThan(0));
      expect(info.videoCodec, 'h264');
      expect((info.width, info.height), (64, 64));
      expect(info.frameRate, closeTo(24, 0.01));
      expect(info.bitDepth, 8);
      expect(info.colorTransfer, isNot('pq'));
      expect(info.audioCodec, 'aac');
      expect(info.audioChannels, 2);
      expect(info.audioChannelLayout, 'stereo');
      expect(info.audioSampleRate, 48000);
      expect(info.subtitleFormat, 'mov_text');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('HDR10 HEVC clip reports 10-bit PQ BT.2020 and omits audio', () async {
    final directory = await Directory.systemTemp.createTemp('media-info-');
    try {
      final clip = await _clip(directory, 'hdr.mp4', [
        '-f',
        'lavfi',
        '-i',
        'color=size=64x64:rate=24',
        '-c:v',
        'libx265',
        '-pix_fmt',
        'yuv420p10le',
        '-x265-params',
        'colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:log-level=error',
        '-tag:v',
        'hvc1',
      ]);
      final info = await _infoFor(clip);
      expect(info.videoCodec, 'hevc');
      expect(info.bitDepth, 10);
      expect(info.colorTransfer, 'pq');
      expect(info.colorPrimaries, 'bt.2020');
      expect(info.colorMatrix, 'bt.2020-ncl');
      expect(info.audioCodec, isNull);
      expect(info.subtitleFormat, isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
