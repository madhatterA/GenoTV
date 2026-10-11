import 'dart:io';

import 'package:cast/src/protocols/chromecast/capability.dart';
import 'package:cast/src/protocols/dlna/capability.dart';
import 'package:test/test.dart';

/// Set CHROMECAST_CAP_TABLE to a file path to write the result table.
void main() {
  CastCompatibility run(ChromecastModel m, String c, String v, String a) =>
      chromecastCompatibility(
        model: m,
        container: c,
        videoCodec: v,
        audioCodec: a,
      );

  test('H.264/AAC MP4 is direct on every model', () {
    for (final m in ChromecastModel.values) {
      expect(
        run(m, 'mp4', 'h264', 'aac'),
        CastCompatibility.direct,
        reason: '$m',
      );
    }
  });

  test('HEVC only where Google lists it', () {
    const hevc = {
      ChromecastModel.ultra,
      ChromecastModel.googleTv,
      ChromecastModel.googleTvStreamer,
    };
    for (final m in ChromecastModel.values) {
      expect(
        run(m, 'mp4', 'hevc', 'aac'),
        hevc.contains(m)
            ? CastCompatibility.direct
            : CastCompatibility.notCompatible,
        reason: '$m',
      );
    }
  });

  test('AV1 only on Google TV Streamer; VP9 not on gen1-3', () {
    expect(
      run(ChromecastModel.googleTvStreamer, 'mp4', 'av1', 'aac'),
      CastCompatibility.direct,
    );
    expect(
      run(ChromecastModel.googleTv, 'mp4', 'av1', 'aac'),
      CastCompatibility.notCompatible,
    );
    expect(
      run(ChromecastModel.gen3, 'webm', 'vp9', 'opus'),
      CastCompatibility.notCompatible,
    );
    expect(
      run(ChromecastModel.ultra, 'webm', 'vp9', 'opus'),
      CastCompatibility.direct,
    );
  });

  test('MKV H.264/AC3 is remuxed without transcoding', () {
    expect(
      run(ChromecastModel.googleTv, 'mkv', 'h264', 'ac3'),
      CastCompatibility.remuxToMp4,
    );
    expect(
      run(ChromecastModel.googleTv, 'matroska', 'avc1', 'ac3'),
      CastCompatibility.remuxToMp4,
    );
    expect(
      run(ChromecastModel.googleTv, 'mp4', 'h264', 'ac3'),
      CastCompatibility.direct,
    );
  });

  test('unknown Chromecast audio does not reject playable video', () {
    expect(
      run(ChromecastModel.ultra, 'mp4', 'h264', 'dts'),
      CastCompatibility.direct,
    );
    expect(
      run(ChromecastModel.ultra, 'mp4', 'h264', 'truehd'),
      CastCompatibility.direct,
    );
  });

  test('codec aliases normalise', () {
    expect(
      run(ChromecastModel.ultra, 'MP4', 'H.265', 'AC-3'),
      CastCompatibility.direct,
    );
  });

  test('writes the capability table', () {
    final rows = StringBuffer(
      '# Chromecast capability table\n\nSource: https://developers.google.com/cast/docs/media (accessed 2026-10-01). Audio h264+aac / container mp4 unless noted.\n\n'
      '| Model | h264 | hevc | vp9 | av1 | mkv h264/ac3 |\n| --- | --- | --- | --- | --- | --- |\n',
    );
    for (final m in ChromecastModel.values) {
      String r(String c, String v, String a) => run(m, c, v, a).name;
      rows.writeln(
        '| ${m.name} | ${r('mp4', 'h264', 'aac')} | ${r('mp4', 'hevc', 'aac')} | ${r('webm', 'vp9', 'opus')} | ${r('mp4', 'av1', 'aac')} | ${r('mkv', 'h264', 'ac3')} |',
      );
    }
    final p = Platform.environment['CHROMECAST_CAP_TABLE'];
    if (p != null) File(p).writeAsStringSync(rows.toString());
  });
}
