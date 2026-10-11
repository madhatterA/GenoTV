import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('minimal FFmpeg artifacts contain remux components, probe decoders, no encoders or filters', () {
    final abiArchitecture = Abi.current().toString().split('_').last;
    final architecture = switch (abiArchitecture) {
      'x64' => 'x86_64',
      'arm' => 'armeabi-v7a',
      'ia32' => 'x86',
      _ => abiArchitecture,
    };
    final platform = Platform.operatingSystem;
    final suffix = platform == 'ios' ? '-iphoneos' : '';
    final prefix = 'native/ffmpeg/$platform-$architecture$suffix';
    expect(
      Directory(prefix).existsSync(),
      isTrue,
      reason:
          'Missing FFmpeg artifacts at $prefix; '
          'run tool/build_ffmpeg.sh $platform $architecture',
    );
    final config = File('$prefix/share/ffmpeg/config_components.h')
        .readAsStringSync();
    for (final component in [
      'MATROSKA_DEMUXER',
      'MOV_DEMUXER',
      'MPEGTS_DEMUXER',
      'HLS_DEMUXER',
      'MATROSKA_MUXER',
      'MOV_MUXER',
      'MP4_MUXER',
      'MPEGTS_MUXER',
      'HLS_MUXER',
      'H264_PARSER',
      'HEVC_PARSER',
      'AAC_PARSER',
      'AC3_PARSER',
      'H264_DECODER',
      'HEVC_DECODER',
      'AAC_DECODER',
      'AC3_DECODER',
      'EAC3_DECODER',
      'SRT_DEMUXER',
      'WEBVTT_DEMUXER',
      'FILE_PROTOCOL',
      'PIPE_PROTOCOL',
    ]) {
      expect(config, contains('#define CONFIG_$component 1'));
    }
    expect(
      RegExp(r'#define CONFIG_\w+_(ENCODER|FILTER) 1').allMatches(config),
      isEmpty,
    );
    final lib = Directory('$prefix/lib');
    final archives = lib
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.a'))
        .toList();
    expect(archives.map((file) => file.uri.pathSegments.last).toSet(), {
      'libavformat.a',
      'libavcodec.a',
      'libavutil.a',
    });
    for (final file in archives) {
      expect(file.lengthSync(), greaterThan(0));
      final result = Process.runSync('nm', [file.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        RegExp(r'\b_?ff_\w+_encoder\b').allMatches('${result.stdout}'),
        isEmpty,
        reason: file.path,
      );
    }
    final symbols = Process.runSync('nm', ['$prefix/lib/libavformat.a']);
    expect(symbols.exitCode, 0, reason: '${symbols.stderr}');
    final definedSymbols = RegExp(r'\b[DRST]\s+_?ff_(\w+)\b')
        .allMatches('${symbols.stdout}')
        .map((match) => match.group(1));
    for (final name in [
      'matroska_demuxer',
      'mov_demuxer',
      'mpegts_demuxer',
      'hls_demuxer',
      'matroska_muxer',
      'mov_muxer',
      'mp4_muxer',
      'mpegts_muxer',
      'hls_muxer',
    ]) {
      expect(definedSymbols, contains(name));
    }
  });
}
