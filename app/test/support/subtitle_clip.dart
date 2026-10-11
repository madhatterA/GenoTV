import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
// The existing headless real-engine harness.
// ignore: implementation_imports
import 'package:playback/src/controller/media_kit_playback_controller.dart';
// ignore: implementation_imports
import 'package:playback/src/surface/surface_output.dart';

const persianText = 'سلام جهان';

Future<(Directory, File, File)> subtitleClip() async {
  mk.MediaKit.ensureInitialized(
    libmpv: Platform.environment['PLAYBACK_LIBMPV'],
  );
  final dir = await Directory.systemTemp.createTemp('subtitle-rules-');
  final sub = File('${dir.path}/text.srt');
  await sub.writeAsString(
    '1\n00:00:00,000 --> 00:00:02,000\nExample subtitle\n',
  );
  final cp = File('${dir.path}/persian.srt');
  await cp.writeAsBytes([
    ...utf8.encode('1\n00:00:00,000 --> 00:00:02,000\n'),
    0xd3,
    0xe1,
    0xc7,
    0xe3,
    0x20,
    0xcc,
    0xe5,
    0xc7,
    0xe4,
    10,
  ]);
  final clip = File('${dir.path}/tracks.mkv');
  final r = await Process.run('ffmpeg', [
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=size=64x64:rate=24:duration=2',
    '-f',
    'lavfi',
    '-i',
    'anullsrc=r=48000:cl=7.1',
    '-i',
    'test/support/atmos.thd',
    '-i',
    sub.path,
    '-map',
    '0:v',
    '-map',
    '1:a',
    '-map',
    '2:a',
    '-map',
    '1:a',
    '-map',
    '1:a',
    for (var i = 0; i < 5; i++) ...['-map', '3:s'],
    '-c:v',
    'mpeg4',
    '-c:a:0',
    'ac3',
    '-ac:a:0',
    '2',
    '-c:a:1',
    'copy',
    '-c:a:2',
    'aac',
    '-ac:a:2',
    '6',
    '-c:a:3',
    'aac',
    '-ac:a:3',
    '2',
    '-c:s',
    'srt',
    '-metadata:s:a:0',
    'language=eng',
    '-metadata:s:a:1',
    'language=eng',
    '-metadata:s:a:1',
    'title=Atmos',
    '-metadata:s:a:2',
    'language=fra',
    '-metadata:s:a:3',
    'language=jpn',
    '-disposition:a:0',
    'default',
    '-disposition:a:1',
    '0',
    '-disposition:a:2',
    '0',
    '-disposition:a:3',
    'original',
    '-metadata:s:s:1',
    'title=English SDH',
    for (var i = 0; i < 5; i++) ...[
      '-metadata:s:s:$i',
      'language=${['eng', 'eng', 'eng', 'fra', 'jpn'][i]}',
      '-disposition:s:$i',
      ['default', 'hearing_impaired', 'forced', '0', '0'][i],
    ],
    '-t',
    '2',
    '-y',
    clip.path,
  ]);
  expect(r.exitCode, 0, reason: r.stderr.toString());
  return (dir, clip, cp);
}

(MediaKitPlaybackController, mk.NativePlayer) subtitleEngine({Uri? resolve}) {
  final p = mk.Player(
    configuration: const mk.PlayerConfiguration(vo: 'null', libass: true),
  );
  return (
    MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: p,
      resolveUri: resolve == null ? null : (_) => resolve,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless'),
        texture: () async {},
        logger: MemoryLogger(),
        onError: (e, s) => fail('surface error: $e'),
      ),
    ),
    p.platform as mk.NativePlayer,
  );
}
