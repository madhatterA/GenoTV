// Measurement harness for Part 02 ch03 p00 (not part of the suite: no _test suffix).
// Run: MODE=http|torrent|restart MEDIA=<file> CACHE=<dir> OUT=<csv> [MAGNET=<uri>] \
//   flutter test test/harness/cache_investigation.dart
import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

final _env = Platform.environment;
final _rows = <String>[];
var _peak = 0;

Future<int> _rssKb() async {
  final out = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
  return int.parse((out.stdout as String).trim());
}

Future<List<String>> _sizes(Directory dir) async {
  final alloc = await Process.run('du', ['-sk', dir.path]);
  var apparent = 0;
  final entries = <String>[];
  if (await dir.exists()) {
    await for (final e in dir.list(recursive: true)) {
      if (e is File) {
        final n = await e.length();
        apparent += n;
        entries.add('${e.path.substring(dir.path.length)}:$n');
      }
    }
  }
  final allocKb = (alloc.stdout as String).split('\t').first;
  return [allocKb, '$apparent', entries.join(' | ')];
}

Future<void> _row(String mode, String label, int bytes, Directory cache) async {
  final rss = await _rssKb();
  if (rss > _peak) _peak = rss;
  final s = await _sizes(cache);
  _rows.add('$mode,$label,$bytes,$_peak,$rss,${s[0]},${s[1]},"${s[2]}"');
}

void main() {
  final mode = _env['MODE']!;
  final cache = Directory(_env['CACHE']!);
  final media = File(_env['MEDIA']!);
  tearDownAll(() async {
    final out = File(_env['OUT']!);
    await out.writeAsString(
      'mode,checkpoint,bytes_read,peak_rss_kb,rss_kb,disk_alloc_kb,disk_apparent_bytes,files\n${_rows.join('\n')}\n',
      mode: FileMode.append,
    );
  });

  test('cache investigation: $mode', () async {
    final sampler = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final r = await _rssKb();
      if (r > _peak) _peak = r;
    });
    addTearDown(sampler.cancel);
    if (mode == 'restart') {
      await _row(mode, 'restart-before-start', 0, cache);
      final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
      await source.dispose();
      await _row(mode, 'restart-after-start-dispose', 0, cache);
      return;
    }
    cache.createSync(recursive: true);
    final total = await media.length();
    HttpServer? origin;
    late final SourceSpec spec;
    if (mode == 'http') {
      origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((req) async {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers.value('range') ?? '');
        final start = m == null ? 0 : int.parse(m[1]!);
        final end = m == null || m[2]!.isEmpty ? total - 1 : int.parse(m[2]!);
        req.response.headers.set('accept-ranges', 'bytes');
        if (m != null) {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set('content-range', 'bytes $start-$end/$total');
        }
        req.response.contentLength = end - start + 1;
        if (req.method != 'HEAD') {
          try {
            await req.response.addStream(media.openRead(start, end + 1));
          } on Object {
            // client closed mid-range (seek); nothing to report
          }
        }
        await req.response.close().catchError((Object _) => req.response);
      });
      spec = SourceSpec(kind: SourceKind.httpUrl, uri: Uri.parse('http://127.0.0.1:${origin.port}/media.mkv'));
    } else {
      spec = SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(_env['MAGNET']!));
    }
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache);
    await _row(mode, 'baseline', 0, cache);
    final handle = await source.open(spec).timeout(const Duration(seconds: 60));
    await _row(mode, 'opened', 0, cache);
    final client = HttpClient();
    final req = await client.getUrl(handle.playbackUri);
    final res = await req.close();
    var read = 0;
    final marks = {0.25: '25%', 0.5: '50%', 1.0: '100%'};
    final pending = marks.keys.toList();
    await for (final chunk in res) {
      read += chunk.length;
      if (pending.isNotEmpty && read >= total * pending.first) {
        await _row(mode, marks[pending.removeAt(0)]!, read, cache);
      }
    }
    expect(read, total);
    await _row(mode, 'stream-end', read, cache);
    client.close(force: true);
    await handle.dispose();
    await _row(mode, 'after-handle-close', read, cache);
    await source.dispose();
    await _row(mode, 'after-source-dispose', read, cache);
    await origin?.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
