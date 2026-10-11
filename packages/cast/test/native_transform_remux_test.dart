import 'dart:ffi';
import 'dart:io';

import 'package:cast/src/remux/remuxer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Remuxer remuxer;
  late Directory work;
  final fixture = File('../../test_media/remux-small.mkv').absolute.path;
  setUpAll(() {
    final arch = Abi.current().toString().endsWith('arm64')
        ? 'arm64'
        : 'x86_64';
    final library = File('native/ffmpeg/macos-$arch/lib/libcast_remux.dylib');
    expect(library.existsSync(), isTrue);
    expect(File(fixture).existsSync(), isTrue);
    remuxer = Remuxer(libraryPath: library.absolute.path);
  });
  setUp(
    () => work = Directory.systemTemp.createTempSync('cast-native-transform-'),
  );
  tearDown(() {
    expect(remuxer.liveJobs, 0);
    work.deleteSync(recursive: true);
  });

  test('native probe returns immutable stream codec metadata', () async {
    final streams = await remuxer.probe(fixture);
    expect(streams.first.index, 0);
    expect(streams.first.type, 'video');
    expect(streams.first.codec, 'h264');
    expect(streams.where((stream) => stream.type == 'audio'), hasLength(2));
    expect(() => streams.clear(), throwsUnsupportedError);
    await expectLater(
      remuxer.probe('$fixture.missing'),
      throwsA(isA<RemuxException>()),
    );
  });

  test('owner probe distinguishes attached cover art from movie streams', () async {
    final input =
        '${Platform.environment['HOME']}/Downloads/movies/'
        'Weapons_2025_10bit_DV_HDR_2160p_x265_BluRay_UHD_Dolby_Atmos_PaHe_30NAMA.mkv';
    expect(File(input).existsSync(), isTrue);
    final streams = await remuxer.probe(input);
    expect(
      streams.where(
        (stream) => stream.codec == 'hevc' && !stream.attachedPicture,
      ),
      isNotEmpty,
    );
    expect(
      streams.where(
        (stream) => stream.codec == 'eac3' && !stream.attachedPicture,
      ),
      isNotEmpty,
    );
    expect(
      streams.where(
        (stream) => stream.codec == 'mjpeg' && stream.attachedPicture,
      ),
      isNotEmpty,
    );
  });

  test('HLS never overwrites or removes a pre-existing directory', () async {
    final directory = Directory('${work.path}/hls')..createSync();
    final sentinel = File('${directory.path}/keep.txt')
      ..writeAsStringSync('preserve');
    final task = remuxer.start(
      input: fixture,
      output: '${directory.path}/stream.m3u8',
      format: 'hls',
      keepStreams: [0, 2],
    );
    await expectLater(task.done, throwsA(isA<RemuxException>()));
    expect(sentinel.readAsStringSync(), 'preserve');
    expect(directory.listSync(), hasLength(1));
  });

  test('HLS header failure removes its newly owned directory', () async {
    final directory = Directory('${work.path}/hls');
    final task = remuxer.start(
      input: fixture,
      output: '${directory.path}/stream.m3u8',
      format: 'hls',
      keepStreams: [0, 2],
      subtitleInputs: [
        File('../../test_media/remux-subtitles.srt').absolute.path,
      ],
    );
    await expectLater(task.done, throwsA(isA<RemuxException>()));
    expect(directory.existsSync(), isFalse);
    expect(work.existsSync(), isTrue);
  });

  test('cancelled HLS preserves the caller directory', () async {
    final directory = Directory('${work.path}/hls');
    final sentinel = File('${work.path}/keep.txt')
      ..writeAsStringSync('preserve');
    final task = remuxer.start(
      input: fixture,
      output: '${directory.path}/stream.m3u8',
      format: 'hls',
      keepStreams: [0, 2],
    );
    task.cancel();
    expect(await task.done, RemuxOutcome.cancelled);
    expect(directory.existsSync(), isFalse);
    expect(sentinel.readAsStringSync(), 'preserve');
  });
}
