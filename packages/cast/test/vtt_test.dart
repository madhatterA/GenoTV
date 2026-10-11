import 'dart:convert';
import 'dart:io';

import 'package:cast/src/core/media_proxy.dart';
import 'package:cast/src/core/subtitle_converter.dart';
import 'package:cast/src/subtitles/subtitle_decoder.dart';
import 'package:test/test.dart';

const _persian = 'سلام دنیا، حالت چطوره؟';

String _srt({String nl = '\n'}) => [
  '1',
  '00:00:01,000 --> 00:00:04,500',
  _persian,
  '',
  '2',
  '01:02:03,004 --> 12:00:00,999',
  '42',
  'Second line',
  '',
].join(nl);

final _cue = RegExp(
  r'^\d{2,}:\d{2}:\d{2}\.\d{3} --> \d{2,}:\d{2}:\d{2}\.\d{3}$',
);

void _expectValidVtt(String vtt) {
  final lines = vtt.split('\n');
  expect(lines.first, 'WEBVTT');
  expect(lines[1], '');
  expect(vtt, isNot(contains('\r')));
  final cues = lines.where((l) => l.contains('-->')).toList();
  expect(cues, hasLength(2));
  for (final c in cues) {
    expect(c, matches(_cue));
  }
  expect(cues[0], '00:00:01.000 --> 00:00:04.500');
  expect(cues[1], '01:02:03.004 --> 12:00:00.999');
}

void main() {
  group('srtToVtt', () {
    test('LF, Persian text and >1 h timestamps', () {
      final vtt = SubtitleConverter.srtToVtt(_srt());
      _expectValidVtt(vtt);
      expect(vtt, contains(_persian));
    });

    test('CRLF line endings', () {
      _expectValidVtt(SubtitleConverter.srtToVtt(_srt(nl: '\r\n')));
    });

    test('BOM is dropped and the file is still detected as SRT', () {
      final withBom = '﻿${_srt()}';
      expect(SubtitleConverter.isSrt(withBom), isTrue);
      final vtt = SubtitleConverter.srtToVtt(withBom);
      _expectValidVtt(vtt);
      expect(vtt, isNot(contains('﻿')));
    });

    test('a cue whose text is a bare number is kept', () {
      expect(SubtitleConverter.srtToVtt(_srt()), contains('\n42\n'));
    });
  });

  group('decodeSubtitleBytes', () {
    test('UTF-8 with BOM', () {
      expect(
        decodeSubtitleBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(_persian)]),
        _persian,
      );
    });

    test('Windows-1256 Persian', () {
      // "سلام" in cp1256: س=D3 ل=E1 ا=C7 م=E3
      expect(
        decodeSubtitleBytes([0xD3, 0xE1, 0xC7, 0xE3, 0x20, 0x41]),
        'سلام A',
      );
      // Persian-specific letters: پ=81 چ=8D ژ=8E گ=90 ک=98 ی=ED
      expect(
        decodeSubtitleBytes([0x81, 0x8D, 0x8E, 0x90, 0x98, 0xED]),
        'پچژگکي',
      );
    });
  });

  group('served by the proxy', () {
    late MediaProxy proxy;
    late Directory dir;
    setUp(() async {
      proxy = MediaProxy();
      await proxy.start();
      dir = Directory.systemTemp.createTempSync('vtt_test');
    });
    tearDown(() async {
      await proxy.stop();
      dir.deleteSync(recursive: true);
    });

    Future<(HttpClientResponse, String)> fetch(File f) async {
      final url = proxy.registerSubtitle('file://${f.path}');
      final c = HttpClient();
      try {
        final res = await (await c.getUrl(Uri.parse(url))).close();
        return (res, await res.transform(utf8.decoder).join());
      } finally {
        c.close(force: true);
      }
    }

    test('UTF-8 CRLF BOM SRT comes out as text/vtt utf-8', () async {
      final f = File(
        '${dir.path}/a.srt',
      )..writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(_srt(nl: '\r\n'))]);
      final (res, body) = await fetch(f);
      expect(res.headers.contentType!.mimeType, 'text/vtt');
      expect(res.headers.contentType!.charset, 'utf-8');
      _expectValidVtt(body);
      expect(body, contains(_persian));
    });

    test('Windows-1256 SRT is converted to UTF-8 VTT', () async {
      final cp = [0xD3, 0xE1, 0xC7, 0xE3]; // سلام
      final srt = '1\n00:00:01,000 --> 00:00:02,000\n';
      final f = File('${dir.path}/b.srt')
        ..writeAsBytesSync([...latin1.encode(srt), ...cp, 0x0A]);
      final (res, body) = await fetch(f);
      expect(res.headers.contentType!.mimeType, 'text/vtt');
      expect(body, contains('00:00:01.000 --> 00:00:02.000\nسلام'));
    });
  });
}
