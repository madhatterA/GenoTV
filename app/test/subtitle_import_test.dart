import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/subtitle_import.dart';

/// Minimal zip writer: (name, bytes, deflate) entries.
Uint8List zip(List<(String, List<int>, bool)> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 255, v >> 8 & 255]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255]);
  for (final (name, data, deflate) in entries) {
    final packed = deflate ? ZLibEncoder(raw: true).convert(data) : data;
    final nameBytes = utf8.encode(name);
    final offset = out.length;
    u32(out, 0x04034b50);
    out.add(List.filled(4, 0));
    u16(out, deflate ? 8 : 0);
    out.add(List.filled(8, 0));
    u32(out, packed.length);
    u32(out, data.length);
    u16(out, nameBytes.length);
    u16(out, 0);
    out.add(nameBytes);
    out.add(packed);
    u32(central, 0x02014b50);
    central.add(List.filled(4, 0));
    u16(central, 0x800);
    u16(central, deflate ? 8 : 0);
    central.add(List.filled(8, 0));
    u32(central, packed.length);
    u32(central, data.length);
    u16(central, nameBytes.length);
    central.add(List.filled(12, 0));
    u32(central, offset);
    central.add(nameBytes);
  }
  final start = out.length;
  out.add(central.toBytes());
  u32(out, 0x06054b50);
  out.add(List.filled(4, 0));
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, central.length);
  u32(out, start);
  u16(out, 0);
  return out.toBytes();
}

const srt = '1\n00:00:01,000 --> 00:00:02,000\nHello\n';

void main() {
  test('reads stored and deflate subtitle entries, ignores the rest', () {
    final entries = readSubtitleZip(
      zip([
        ('a.srt', utf8.encode(srt), false),
        ('sub/b.VTT', utf8.encode('WEBVTT\n' * 50), true),
        ('readme.txt', utf8.encode('x'), true),
        ('dir/', const [], false),
      ]),
    );
    expect(entries.map((e) => e.name), ['a.srt', 'b.VTT']);
    expect(utf8.decode(entries[0].bytes), srt);
    expect(utf8.decode(entries[1].bytes), 'WEBVTT\n' * 50);
  });

  test('rejects traversal and absolute names', () {
    for (final name in [
      '../evil.srt',
      'a/../../evil.srt',
      '/etc/x.srt',
      'C:\\x.srt',
      '..\\x.srt',
    ]) {
      expect(
        () => readSubtitleZip(zip([(name, utf8.encode(srt), false)])),
        throwsA(isA<SubtitleImportException>()),
        reason: name,
      );
    }
  });

  test('errors: no subtitles, empty zip, not a zip', () {
    expect(
      () => readSubtitleZip(zip([('a.txt', utf8.encode('x'), false)])),
      throwsA(isA<SubtitleImportException>()),
    );
    expect(
      () => readSubtitleZip(zip([])),
      throwsA(isA<SubtitleImportException>()),
    );
    expect(
      () => readSubtitleZip(Uint8List.fromList(List.filled(100, 7))),
      throwsA(isA<SubtitleImportException>()),
    );
  });

  test('damaged deflate data is an error', () {
    final bad = zip([('a.srt', utf8.encode(srt * 20), true)]);
    for (var i = 40; i < 50; i++) {
      bad[i] = 0xFF;
    }
    expect(() => readSubtitleZip(bad), throwsA(isA<SubtitleImportException>()));
  });

  test('stageSubtitles decodes Windows-1256 and BOM to UTF-8 files', () async {
    final staged = await stageSubtitles([
      (
        name: 'fa.srt',
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('سلام')]),
      ),
      (
        name: 'old.srt',
        bytes: Uint8List.fromList([0xE3, 0xD1, 0xCD, 0xC8, 0xC7]),
      ),
    ]);
    expect(staged.map((s) => s.name), ['fa.srt', 'old.srt']);
    expect(File.fromUri(staged[0].uri).readAsStringSync(), 'سلام');
    expect(File.fromUri(staged[1].uri).readAsStringSync(), 'مرحبا');
  });

  test(
    'readSubtitleSource: plain file, zip file, unsupported, missing',
    () async {
      final dir = Directory.systemTemp.createTempSync('subtest_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/x.srt').writeAsStringSync(srt);
      File('${dir.path}/x.zip')
          .writeAsBytesSync(zip([('in.ass', utf8.encode('a'), true)]));
      File('${dir.path}/x.txt').writeAsStringSync('t');
      expect(
        (await readSubtitleSource('${dir.path}/x.srt')).single.name,
        'x.srt',
      );
      expect(
        (await readSubtitleSource('${dir.path}/x.zip')).single.name,
        'in.ass',
      );
      await expectLater(
        readSubtitleSource('${dir.path}/x.txt'),
        throwsA(isA<SubtitleImportException>()),
      );
      await expectLater(
        readSubtitleSource('${dir.path}/none.srt'),
        throwsA(isA<SubtitleImportException>()),
      );
    },
  );
}
