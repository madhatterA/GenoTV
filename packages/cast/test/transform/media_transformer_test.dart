import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cast/dart_cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = File('../../test_media/transform-audio.mkv').absolute;
  final streaming = File('../../test_media/transform-streaming.mkv').absolute;
  final subtitles = File('../../test_media/remux-subtitles.srt').absolute;
  final owner = File(
    '${Platform.environment['HOME']}/Downloads/movies/'
    'Weapons_2025_10bit_DV_HDR_2160p_x265_BluRay_UHD_Dolby_Atmos_PaHe_30NAMA.mkv',
  );
  final evidence = Directory('../../evidence/part-05/ch01-p03');
  late Remuxer native;
  late MediaProxy proxy;
  late HttpClient client;
  late List<RemuxStream> streamingStreams;
  final results = <CastTransformResult>[];

  setUpAll(() async {
    for (final input in [fixture, streaming, subtitles, owner]) {
      expect(
        input.existsSync(),
        isTrue,
        reason: 'Required input ${input.path} is missing',
      );
    }
    final arch = Abi.current().toString().endsWith('arm64') ? 'arm64' : 'x86_64';
    final library = File('native/ffmpeg/macos-$arch/lib/libcast_remux.dylib').absolute;
    expect(library.existsSync(), isTrue, reason: 'Run tool/build_remux.sh');
    native = Remuxer(libraryPath: library.path);
    streamingStreams = await native.probe(streaming.path);
    await evidence.create(recursive: true);
  });
  setUp(() async {
    proxy = MediaProxy();
    await proxy.start(bindAddress: '127.0.0.1');
    client = HttpClient();
  });
  tearDown(() async {
    for (final result in results) {
      await result.dispose();
    }
    results.clear();
    await proxy.stop();
    client.close(force: true);
    expect(native.liveJobs, 0);
  });

  MediaSource slowSource() => MediaSource(
    length: streaming.lengthSync(),
    contentType: 'video/x-matroska',
    read: (start, end) async* {
      // Small, real source chunks leave deterministic network backpressure
      // beyond FFmpeg's two-second probe, without a long clip or repeat loop.
      final handle = await streaming.open();
      try {
        await handle.setPosition(start);
        var position = start;
        while (position < end) {
          final bytes = await handle.read((end - position).clamp(0, 2048));
          if (bytes.isEmpty) throw StateError('Unexpected source EOF');
          position += bytes.length;
          yield bytes;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } finally {
        await handle.close();
      }
    },
  );

  Future<CastTransformResult> remux(
    CastCompatibility compatibility,
    CastMedia media, {
    List<RemuxStream>? streams,
    bool embed = false,
    AudioCapability? audio,
    Duration duration = const Duration(seconds: 6),
  }) async {
    final result = await CastRemuxMediaTransformer(
      compatibility: compatibility,
      audioCapability: audio ?? AudioCapability.known({'aac'}),
      embedSubtitles: embed,
      remuxer: native,
      streams: streams,
      maxDuration: duration,
    ).transform(media, proxy);
    results.add(result);
    return result;
  }

  Future<Map<String, dynamic>> probe(String name, String url) async {
    final arguments = [
      '-v',
      'error',
      '-read_intervals',
      '%+2',
      '-show_streams',
      '-show_format',
      '-of',
      'json',
      url,
    ];
    final process = await Process.run(
      'ffprobe',
      arguments,
    ).timeout(const Duration(seconds: 5));
    await File('${evidence.path}/$name.ffprobe.json')
        .writeAsString('${process.stdout}');
    await File('${evidence.path}/$name.command.txt').writeAsString(
      'ffprobe ${arguments.join(' ')}\n${process.stderr}\nexit=${process.exitCode}\n',
    );
    expect(process.exitCode, 0, reason: '${process.stderr}');
    return jsonDecode('${process.stdout}') as Map<String, dynamic>;
  }

  test('fragmented MP4 serves bytes before remux completion; completed ranges are exact', () async {
    final result = await remux(
      CastCompatibility.remuxToMp4,
      CastMedia.source(
        slowSource(),
        type: CastMediaType.mkv,
        fileExtension: '.mkv',
      ),
      streams: streamingStreams,
    );
    var completed = false;
    final done = result.done.then((value) {
      completed = true;
      return value;
    });
    final response = await (await client.getUrl(Uri.parse(result.proxyUrl)))
        .close();
    final iterator = StreamIterator(response);
    expect(await iterator.moveNext(), isTrue);
    expect(
      completed,
      isFalse,
      reason: 'First bytes must arrive while native copying is active',
    );
    final bytes = <int>[...iterator.current];
    while (await iterator.moveNext()) {
      bytes.addAll(iterator.current);
    }
    await iterator.cancel();
    expect(await done, RemuxOutcome.completed);
    final atoms = latin1.decode(bytes);
    expect(atoms, contains('moof'));
    expect(atoms.indexOf('moov'), lessThan(atoms.indexOf('mdat')));
    final facts = await probe('progressive_mp4', result.proxyUrl);
    expect((facts['streams'] as List).map((s) => s['codec_name']), [
      'h264',
      'aac',
    ]);
    expect(result.droppedAudioStreams, [1]);
    final rangeRequest = await client.getUrl(Uri.parse(result.proxyUrl));
    rangeRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-15');
    final range = await rangeRequest.close();
    expect(range.statusCode, HttpStatus.partialContent);
    expect(
      range.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 0-15/${bytes.length}',
    );
    expect(
      await range.fold<List<int>>([], (all, next) => all..addAll(next)),
      bytes.take(16),
    );
    final badRequest = await client.getUrl(Uri.parse(result.proxyUrl));
    badRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=999999999-');
    final bad = await badRequest.close();
    expect(bad.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    await bad.drain<void>();
    await File('${evidence.path}/progressive_mp4.txt').writeAsString(
      'First response chunk before remux completion: PASS\nmoov before mdat; moof present: PASS\n'
      'Unsupported AC3 track dropped, AAC retained: PASS\nExact range206 and invalid416: PASS\n',
    );
  });

  test('HLS playlist and finalized segments serve through proxy before job completion', () async {
    final result = await remux(
      CastCompatibility.remuxToHls,
      CastMedia.source(
        slowSource(),
        type: CastMediaType.mkv,
        fileExtension: '.mkv',
      ),
      streams: streamingStreams,
    );
    var completed = false;
    final done = result.done.then((value) {
      completed = true;
      return value;
    });
    final response = await (await client.getUrl(Uri.parse(result.proxyUrl)))
        .close();
    final playlist = await utf8.decoder.bind(response).join();
    expect(completed, isFalse);
    expect(playlist, contains('#EXTM3U'));
    expect(playlist, isNot(contains('.tmp')));
    final segment = playlist
        .split('\n')
        .firstWhere((line) => line.endsWith('.ts'));
    final segmentResponse = await (await client.getUrl(
      Uri.parse(result.proxyUrl).resolve(segment),
    )).close();
    expect(segmentResponse.statusCode, HttpStatus.ok);
    final bytes = await segmentResponse.fold<List<int>>(
      [],
      (all, next) => all..addAll(next),
    );
    expect(bytes.first, 0x47);
    expect(await done, RemuxOutcome.completed);
    final facts = await probe('hls', result.proxyUrl);
    expect((facts['streams'] as List).map((s) => s['codec_name']), [
      'h264',
      'aac',
    ]);
    final forbidden = await (await client.getUrl(
      Uri.parse(result.proxyUrl).resolve('unlisted.txt'),
    )).close();
    expect(forbidden.statusCode, HttpStatus.notFound);
    await forbidden.drain<void>();
    await File('${evidence.path}/hls.txt').writeAsString(
      'Playlist served before remux completion: PASS\nFinalized TS segment sync byte0x47: PASS\n'
      'ffprobe served HLS H264/AAC: PASS\nUnlisted asset404: PASS\n',
    );
  });

  test(
    'owner HEVC DV Atmos two-second fragmented MP4 served over loopback',
    () async {
      final result = await remux(
        CastCompatibility.remuxToMp4,
        CastMedia.file(filePath: owner.path, type: CastMediaType.mkv),
        audio: AudioCapability.known({'eac3'}),
        duration: const Duration(seconds: 2),
      );
      expect(await result.done, RemuxOutcome.completed);
      final facts = await probe('owner_mp4', result.proxyUrl);
      final streams = facts['streams'] as List;
      expect(streams.map((s) => s['codec_name']), ['hevc', 'eac3']);
      expect(
        '${streams.first['side_data_list']}',
        contains('DOVI configuration record'),
      );
      await File('${evidence.path}/owner_mp4.txt').writeAsString(
        'Owner input exists; two-second HEVC/EAC3 stream copy: PASS\n'
        'Served ffprobe Dolby Vision configuration record: PASS\n',
      );
    },
  );

  test('DLNA unknown audio keeps all tracks and MKV embeds real SRT', () async {
    final result = await remux(
      CastCompatibility.direct,
      CastMedia.file(
        filePath: fixture.path,
        type: CastMediaType.mkv,
        subtitles: [
          CastSubtitle(
            url: subtitles.path,
            label: 'English',
            language: 'en',
            format: 'srt',
          ),
        ],
      ),
      embed: true,
      audio: const AudioCapability.unknown(),
      duration: const Duration(seconds: 2),
    );
    expect(await result.done, RemuxOutcome.completed);
    expect(result.audioSupportUnknown, isTrue);
    expect(result.droppedAudioStreams, isEmpty);
    final facts = await probe('dlna_mkv_srt', result.proxyUrl);
    expect((facts['streams'] as List).map((s) => s['codec_name']), [
      'h264',
      'ac3',
      'aac',
      'subrip',
    ]);
    final args = [
      '-v',
      'error',
      '-i',
      result.proxyUrl,
      '-map',
      '0:s:0',
      '-f',
      'srt',
      '-',
    ];
    final process = await Process.run(
      'ffmpeg',
      args,
    ).timeout(const Duration(seconds: 5));
    expect(process.exitCode, 0, reason: '${process.stderr}');
    expect('${process.stdout}', contains('remux subtitle proof'));
    await File('${evidence.path}/dlna_srt_extract.txt').writeAsString(
      'ffmpeg ${args.join(' ')}\n${process.stdout}\n${process.stderr}\nexit=${process.exitCode}\n'
      'audioSupport=unknown; droppedAudioStreams=[]\n',
    );
  });

  test(
    'missing input gives typed failure and completed dispose removes routes',
    () async {
      await expectLater(
        remux(
          CastCompatibility.remuxToMp4,
          CastMedia.file(
            filePath: '${fixture.path}.missing',
            type: CastMediaType.mkv,
          ),
        ),
        throwsA(isA<CastTransformFailure>()),
      );
      final direct = await remux(
        CastCompatibility.direct,
        CastMedia.file(filePath: fixture.path, type: CastMediaType.mkv),
        audio: const AudioCapability.unknown(),
      );
      expect(direct.task, isNull);
      expect(direct.audioSupportUnknown, isTrue);
      await direct.dispose();
      final response = await (await client.getUrl(Uri.parse(direct.proxyUrl)))
          .close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    },
  );
}
