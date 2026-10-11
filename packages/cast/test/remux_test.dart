import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cast/src/remux/remuxer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final arch = Abi.current().toString().endsWith('arm64') ? 'arm64' : 'x86_64';
  final library = File('native/ffmpeg/macos-$arch/lib/libcast_remux.dylib')
      .absolute
      .path;
  final fixture = File('../../test_media/remux-small.mkv').absolute.path;
  final ownerFixture =
      '${Platform.environment['HOME']}/Downloads/movies/'
      'Weapons_2025_10bit_DV_HDR_2160p_x265_BluRay_UHD_Dolby_Atmos_PaHe_30NAMA.mkv';
  late Directory work;
  late Remuxer remuxer;

  setUpAll(() {
    expect(
      File(library).existsSync(),
      isTrue,
      reason: 'Run packages/cast/tool/build_remux.sh',
    );
    expect(
      File(fixture).existsSync(),
      isTrue,
      reason: 'Run packages/cast/tool/create_remux_fixture.sh',
    );
    expect(
      File(ownerFixture).existsSync(),
      isTrue,
      reason: 'The owner-approved MKV is required, never skipped',
    );
    remuxer = Remuxer(libraryPath: library);
  });
  setUp(() => work = Directory.systemTemp.createTempSync('cast-remux-'));
  tearDown(() {
    expect(remuxer.liveJobs, 0);
    work.deleteSync(recursive: true);
  });

  test(
    'selected codecs and extradata survive MKV to MP4; dropped audio absent',
    () async {
      final output = '${work.path}/selected.mp4';
      final task = remuxer.start(
        input: fixture,
        output: output,
        format: 'mp4',
        keepStreams: [0, 2],
      );
      final events = <RemuxProgress>[];
      final subscription = task.progress.listen(events.add);
      expect(await task.done, RemuxOutcome.completed);
      await subscription.asFuture<void>();
      await subscription.cancel();
      final inputStreams = await probe(fixture);
      final outputStreams = await probe(output);
      saveProbe('small', inputStreams, outputStreams);
      expect(outputStreams, [inputStreams[0], inputStreams[2]]);
      expect(events, isNotEmpty);
      expect(events.last.packets, greaterThan(0));
      await assertPacketTimes(output);
      await assertPacketPayloads(fixture, output, [0, 2], 'small');
      saveProbe('small', inputStreams, outputStreams);
    },
  );

  test(
    'owner HEVC DV and Atmos codec parameters survive a two-second copy',
    () async {
      final output = '${work.path}/owner.mp4';
      expect(
        await remuxer
            .start(
              input: ownerFixture,
              output: output,
              format: 'mp4',
              keepStreams: [0, 1],
              maxDuration: const Duration(seconds: 2),
            )
            .done,
        RemuxOutcome.completed,
      );
      final inputStreams = await probe(ownerFixture);
      final outputStreams = await probe(output);
      saveProbe('owner', inputStreams, outputStreams);
      expect(outputStreams, [inputStreams[0], inputStreams[1]]);
      await assertPacketTimes(output);
      await assertPacketPayloads(ownerFixture, output, [0, 1], 'owner');
      saveProbe('owner', inputStreams, outputStreams);
    },
  );

  test('external subtitle is copied into a compatible container', () async {
    final subtitles = File('../../test_media/remux-subtitles.srt')
        .absolute
        .path;
    expect(File(subtitles).existsSync(), isTrue);
    final output = '${work.path}/subtitles.mkv';
    expect(
      await remuxer
          .start(
            input: fixture,
            output: output,
            format: 'matroska',
            keepStreams: [0, 2],
            subtitleInputs: [subtitles],
          )
          .done,
      RemuxOutcome.completed,
    );
    final streams = await probe(output);
    expect(streams.length, 3);
    expect(streams.last, (await probe(subtitles)).single);
    final text = await run('ffmpeg', [
      '-v',
      'error',
      '-i',
      output,
      '-map',
      '0:s:0',
      '-f',
      'srt',
      '-',
    ]);
    expect(text, contains('remux subtitle proof'));
  });

  test('incompatible subtitle fails and removes partial output', () async {
    final output = '${work.path}/unsupported.mp4';
    final task = remuxer.start(
      input: fixture,
      output: output,
      format: 'mp4',
      keepStreams: [0],
      subtitleInputs: [
        File('../../test_media/remux-subtitles.srt').absolute.path,
      ],
    );
    await expectLater(task.done, throwsA(isA<RemuxException>()));
    expect(File(output).existsSync(), isFalse);
  });

  test('cancel during real copying leaves the main isolate responsive and releases files', () async {
    final output = '${work.path}/cancel.mp4';
    final task = remuxer.start(
      input: ownerFixture,
      output: output,
      format: 'mp4',
      keepStreams: [0, 1],
    );
    var ticks = 0;
    var packetsAtCancel = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final subscription = task.progress.listen((event) {
      if (event.packets > 0 && packetsAtCancel == 0) {
        packetsAtCancel = event.packets;
        task.cancel();
      }
    });
    try {
      expect(
        await task.done.timeout(const Duration(seconds: 5)),
        RemuxOutcome.cancelled,
      );
      expect(packetsAtCancel, greaterThan(0));
      expect(ticks, greaterThan(0));
      expect(File(output).existsSync(), isFalse);
      expect(remuxer.liveJobs, 0);
      final descriptors = await run('lsof', ['-p', '$pid', '-Fn']);
      expect(descriptors.split('\n'), isNot(contains('n$ownerFixture')));
      expect(descriptors.split('\n'), isNot(contains('n$output')));
      final handle = File(ownerFixture).openSync();
      handle.closeSync();
      expect(
        await remuxer
            .start(
              input: fixture,
              output: '${work.path}/after-cancel.mp4',
              format: 'mp4',
              keepStreams: [0, 2],
            )
            .done,
        RemuxOutcome.completed,
      );
      expect(remuxer.liveJobs, 0);
      task.cancel(); // Completion makes cancellation safe and idempotent.
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  });

  test('missing input and invalid stream index fail without leaking', () async {
    for (final (input, streams) in [
      ('$fixture.missing', [0]),
      (fixture, [99]),
    ]) {
      final output = '${work.path}/failure-${streams.single}.mp4';
      await expectLater(
        Future.sync(
          () => remuxer
              .start(
                input: input,
                output: output,
                format: 'mp4',
                keepStreams: streams,
              )
              .done,
        ),
        throwsA(isA<RemuxException>()),
      );
      expect(File(output).existsSync(), isFalse);
      expect(remuxer.liveJobs, 0);
    }
  });

  test('pre-existing output and same input are never overwritten', () async {
    final output = File('${work.path}/existing.mp4')
      ..writeAsStringSync('preserve');
    await expectLater(
      Future.sync(
        () => remuxer
            .start(
              input: fixture,
              output: output.path,
              format: 'mp4',
              keepStreams: [0],
            )
            .done,
      ),
      throwsA(isA<RemuxException>()),
    );
    expect(output.readAsStringSync(), 'preserve');
    expect(
      () => remuxer.start(
        input: fixture,
        output: fixture,
        format: 'mp4',
        keepStreams: [0],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'empty selection, duplicates, negative duration and NUL paths are rejected',
    () {
      for (final streams in [
        <int>[],
        [0, 0],
        [-1],
      ]) {
        expect(
          () => remuxer.start(
            input: fixture,
            output: '${work.path}/bad.mp4',
            format: 'mp4',
            keepStreams: streams,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
      expect(
        () => remuxer.start(
          input: fixture,
          output: '${work.path}/bad.mp4',
          format: 'mp4',
          keepStreams: [0],
          maxDuration: const Duration(seconds: -1),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => remuxer.start(
          input: '$fixture\u0000',
          output: '${work.path}/bad.mp4',
          format: 'mp4',
          keepStreams: [0],
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}

Future<String> run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  expect(
    result.exitCode,
    0,
    reason: '$executable ${args.join(' ')}\n${result.stderr}',
  );
  return '${result.stdout}';
}

Future<List<Map<String, dynamic>>> probe(String path) async {
  final json = jsonDecode(
    await run('ffprobe', [
      '-v',
      'error',
      '-read_intervals',
      '%+2',
      '-show_streams',
      '-show_data',
      '-show_data_hash',
      'sha256',
      '-show_entries',
      'stream=codec_name,profile,codec_type,width,height,pix_fmt,level,color_range,'
          'color_space,color_transfer,color_primaries,sample_rate,channels,channel_layout,'
          'bits_per_raw_sample,extradata,extradata_hash:stream_side_data:stream_tags=:stream_disposition=',
      '-of',
      'json',
      path,
    ]),
  ) as Map;
  return (json['streams'] as List).map((stream) {
    final parameters = Map<String, dynamic>.from(stream as Map);
    final extradata = parameters.remove('extradata') as String?;
    if (parameters['codec_name'] == 'hevc') {
      expect(extradata, isNotNull);
      parameters.remove('extradata_hash');
      parameters['hevc_configuration'] = hevcConfiguration(extradata!);
    }
    final sideData = parameters['side_data_list'] as List?;
    if (sideData != null) {
      final codecMetadata = sideData
          .where(
            (data) =>
                data['side_data_type'] == 'DOVI configuration record' ||
                data['side_data_type'] == 'Mastering display metadata' ||
                data['side_data_type'] == 'Content light level metadata',
          )
          .toList();
      if (codecMetadata.isEmpty) {
        parameters.remove('side_data_list');
      } else {
        parameters['side_data_list'] = codecMetadata;
      }
    }
    return parameters;
  }).toList();
}

Future<void> assertPacketTimes(String path) async {
  final json = jsonDecode(
    await run('ffprobe', [
      '-v',
      'error',
      '-show_packets',
      '-show_entries',
      'packet=stream_index,dts_time,pts_time',
      '-of',
      'json',
      path,
    ]),
  ) as Map;
  final previous = <int, double>{};
  for (final packet in json['packets'] as List) {
    final index = packet['stream_index'] as int;
    final dts = double.parse(packet['dts_time'] as String);
    expect(
      dts,
      greaterThanOrEqualTo(previous[index] ?? double.negativeInfinity),
    );
    previous[index] = dts;
  }
  expect(previous.length, 2);
}

void saveProbe(String label, Object input, Object output) {
  final evidence = Directory('../../evidence/part-05/ch01-p02');
  if (!evidence.existsSync()) {
    throw StateError('Missing assigned evidence directory');
  }
  File('${evidence.path}/ffprobe_in_out_$label.txt').writeAsStringSync(
    'ffprobe -v error -read_intervals %+2 -show_streams -show_data_hash sha256 '
    '-show_entries <codec parameters + side data> -of json <path>\n'
    'INPUT\n${const JsonEncoder.withIndent('  ').convert(input)}\n'
    'OUTPUT\n${const JsonEncoder.withIndent('  ').convert(output)}\nexit=0\n',
  );
}

Map<String, Object> hevcConfiguration(String dump) {
  final bytes = <int>[];
  for (final match in RegExp(
    r'^\s*[0-9a-f]{8}:\s+(.+?)\s{2,}',
    multiLine: true,
  ).allMatches(dump)) {
    final hex = match[1]!.replaceAll(' ', '');
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
  }
  expect(bytes.length, greaterThanOrEqualTo(23));
  expect(bytes[0], 1, reason: 'hvcC configurationVersion');
  var offset = 23;
  final units = <Map<String, Object>>[];
  for (var array = 0; array < bytes[22]; array++) {
    expect(offset + 3, lessThanOrEqualTo(bytes.length));
    final type = bytes[offset++] & 0x3f;
    final count = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    for (var unit = 0; unit < count; unit++) {
      expect(offset + 2, lessThanOrEqualTo(bytes.length));
      final size = (bytes[offset] << 8) | bytes[offset + 1];
      offset += 2;
      expect(offset + size, lessThanOrEqualTo(bytes.length));
      units.add({
        'type': type,
        'data': bytes
            .sublist(offset, offset + size)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      });
      offset += size;
    }
  }
  expect(offset, bytes.length);
  return {'nalLengthSize': (bytes[21] & 3) + 1, 'parameterSets': units};
}

Future<void> assertPacketPayloads(
  String input,
  String output,
  List<int> kept,
  String label,
) async {
  Future<List<dynamic>> packets(String path, {bool bounded = false}) async {
    final json = jsonDecode(
      await run('ffprobe', [
        '-v',
        'error',
        if (bounded) ...['-read_intervals', '%+3'],
        '-show_packets',
        '-show_data_hash',
        'sha256',
        '-show_entries',
        'packet=stream_index,data_hash',
        '-of',
        'json',
        path,
      ]),
    ) as Map;
    return json['packets'] as List;
  }

  final source = await packets(input, bounded: true);
  final result = await packets(output);
  final comparisons = <Map<String, Object>>[];
  for (var outputIndex = 0; outputIndex < kept.length; outputIndex++) {
    final sourceHashes = source
        .where((p) => p['stream_index'] == kept[outputIndex])
        .map((p) => p['data_hash'])
        .toList();
    final resultHashes = result
        .where((p) => p['stream_index'] == outputIndex)
        .map((p) => p['data_hash'])
        .toList();
    expect(resultHashes, isNotEmpty);
    expect(sourceHashes.length, greaterThanOrEqualTo(resultHashes.length));
    expect(resultHashes, sourceHashes.take(resultHashes.length).toList());
    comparisons.add({
      'inputStream': kept[outputIndex],
      'outputStream': outputIndex,
      'packets': resultHashes.length,
      'identicalSha256': resultHashes,
    });
  }
  File(
    '../../evidence/part-05/ch01-p02/packet_identity_$label.txt',
  ).writeAsStringSync(
    'ffprobe -v error [-read_intervals %+3 for input] '
    '-show_packets -show_data_hash sha256 -show_entries packet=stream_index,data_hash '
    '-of json <path>\n${const JsonEncoder.withIndent('  ').convert(comparisons)}\nexit=0\n',
  );
}
