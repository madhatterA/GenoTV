// Proof harness for Part 02 ch03 p00b (not part of the suite: no _test suffix).
// Run: MODE=http|torrent MEDIA=<a> MEDIA_B=<b> CACHE=<dir> OUT=<csv> [LIMIT=<bytes>]
//   [MAGNET=<a magnet> MAGNET_B=<b magnet>] [RATE=<reader bytes/s>] \
//   flutter test test/harness/cache_limit_proof.dart
// A is the large stream (read whole, then seek back); B is a smaller stream
// that is read and closed first, so it is the least recently used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:contracts/fakes/fake_repositories.dart';
import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

final _env = Platform.environment;
const _mib = 1024 * 1024;

void main() {
  final mode = _env['MODE']!;
  final mediaA = File(_env['MEDIA']!);
  final mediaB = File(_env['MEDIA_B']!);
  final cache = Directory(_env['CACHE']!);
  final out = File(_env['OUT']!);
  final limit = int.parse(_env['LIMIT'] ?? '${512 * _mib}');
  final readerRate = int.parse(_env['RATE'] ?? '${60 * _mib}');
  const slack = 64 * _mib;
  final fs = FsNative();
  final rows = <String>[];
  final results = <String>[];

  test('cache limit proof: $mode', () async {
    cache.createSync(recursive: true);
    final totalA = mediaA.lengthSync();
    final clock = Stopwatch()..start();
    var readerPos = 0;
    var maxAlloc = 0;
    var sampling = false;

    int allocated() {
      var sum = 0;
      for (final e in cache.listSync(recursive: true)) {
        if (e is File) sum += fs.allocatedBytes(e.path);
      }
      return sum;
    }

    final sampler = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) async {
      if (sampling) return;
      sampling = true;
      final alloc = allocated();
      final du = await Process.run('du', ['-sk', cache.path]);
      var apparent = 0;
      for (final e in cache.listSync(recursive: true)) {
        if (e is File) apparent += e.lengthSync();
      }
      maxAlloc = math.max(
        maxAlloc,
        math.max(
          alloc,
          int.parse((du.stdout as String).split('\t').first) * 1024,
        ),
      );
      rows.add(
        '$mode,${clock.elapsedMilliseconds},$readerPos,$alloc,'
        '${(du.stdout as String).split('\t').first},$apparent',
      );
      sampling = false;
    });
    addTearDown(() {
      sampler.cancel();
      out.writeAsStringSync('${rows.join('\n')}\n', mode: FileMode.append);
      for (final line in results) {
        // ignore: avoid_print
        print('RESULT $mode $line');
      }
    });

    HttpServer? origin;
    SourceSpec specFor(String name, String? magnet) => mode == 'http'
        ? SourceSpec(
            kind: SourceKind.httpUrl,
            uri: Uri.parse('http://127.0.0.1:${origin!.port}/$name'),
          )
        : SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(magnet!));
    if (mode == 'http') {
      origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((req) async {
        final media = req.uri.path == '/b.bin' ? mediaB : mediaA;
        final total = media.lengthSync();
        final m = RegExp(r'bytes=(\d+)-(\d*)')
            .firstMatch(req.headers.value('range') ?? '');
        final start = m == null ? 0 : int.parse(m[1]!);
        final end = m == null || m[2]!.isEmpty ? total - 1 : int.parse(m[2]!);
        req.response.headers.set('accept-ranges', 'bytes');
        if (m != null) {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set('content-range', 'bytes $start-$end/$total');
        }
        req.response.contentLength = end - start + 1;
        if (req.method != 'HEAD') {
          // ~200 MB/s: a loopback origin with no cap is far faster than any link.
          final sw = Stopwatch()..start();
          var sent = 0;
          try {
            await for (final chunk in media.openRead(start, end + 1)) {
              req.response.add(chunk);
              sent += chunk.length;
              final due = sent * 1000 ~/ (200 * _mib);
              if (due > sw.elapsedMilliseconds) {
                await Future<void>.delayed(
                  Duration(milliseconds: due - sw.elapsedMilliseconds),
                );
              }
            }
          } on Object {
            // client closed mid-range (seek)
          }
        }
        await req.response.close().catchError((Object _) => req.response);
      });
      addTearDown(() => origin!.close(force: true));
    }

    final state = FakeTransportStateRepository();
    final logger = MemoryLogger();
    addTearDown(() {
      for (final record in logger.records) {
        printOnFailure('${record.level} ${record.message} ${record.error}');
      }
    });
    final source = StreamSourceImpl(
      logger: logger,
      cacheDir: cache,
      state: state,
    );
    final options = TransportOptions(cacheLimitBytes: limit);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    // Reads [from, to] of [uri] in order, byte-exact against [media]; paced at
    // [readerRate] like a player. Returns the longest wait for a chunk.
    Future<int> read(
      Uri uri,
      File media,
      int from,
      int to, {
      bool pace = true,
    }) async {
      final raf = media.openSync();
      final req = await client.getUrl(uri);
      req.headers.set('range', 'bytes=$from-$to');
      final res = await req.close();
      expect(res.statusCode, HttpStatus.partialContent);
      final it = StreamIterator(res);
      var at = from;
      var maxWait = 0;
      Digest? actualDigest;
      Digest? expectedDigest;
      final actualHash = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback(
          (digests) => actualDigest = digests.single,
        ),
      );
      final expectedHash = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback(
          (digests) => expectedDigest = digests.single,
        ),
      );
      final pacer = Stopwatch()..start();
      while (true) {
        final t0 = clock.elapsedMilliseconds;
        final has = await it.moveNext().timeout(const Duration(seconds: 2));
        maxWait = math.max(maxWait, clock.elapsedMilliseconds - t0);
        if (!has) break;
        final chunk = it.current;
        final expected = Uint8List(chunk.length);
        raf.setPositionSync(at);
        raf.readIntoSync(expected);
        actualHash.add(chunk);
        expectedHash.add(expected);
        at += chunk.length;
        readerPos = at;
        if (pace) {
          final due = (at - from) * 1000 ~/ readerRate;
          if (due > pacer.elapsedMilliseconds) {
            await Future<void>.delayed(
              Duration(milliseconds: due - pacer.elapsedMilliseconds),
            );
          }
        }
      }
      raf.closeSync();
      actualHash.close();
      expectedHash.close();
      expect(at, to + 1, reason: 'stream ended early');
      expect(actualDigest, expectedDigest, reason: 'byte-exact SHA-256');
      results.add(
        'SHA-256 [$from,$to]: $actualDigest = source $expectedDigest',
      );
      return maxWait;
    }

    // Stream B: read whole, close. It is now a closed stream in the cache.
    final handleB = await source
        .open(specFor('b.bin', _env['MAGNET_B']), options: options)
        .timeout(const Duration(seconds: 90));
    await read(
      handleB.playbackUri,
      mediaB,
      0,
      mediaB.lengthSync() - 1,
      pace: false,
    );
    await handleB.dispose();
    final closedBefore = allocated();
    results.add(
      'B closed: ${closedBefore ~/ _mib} MiB on disk, ${(await state.all()).length} record(s)',
    );
    expect(closedBefore, greaterThan(0));

    // Stream A: whole sequential read.
    final handleA = await source
        .open(specFor('a.bin', _env['MAGNET']), options: options)
        .timeout(const Duration(seconds: 90));
    final maxWait = await read(handleA.playbackUri, mediaA, 0, totalA - 1);
    results.add(
      '(1) peak allocated ${maxAlloc ~/ _mib} MiB, limit ${limit ~/ _mib} MiB + 64 MiB slack',
    );
    expect(maxAlloc, lessThanOrEqualTo(limit + slack), reason: 'assertion 1');
    results.add('(2) full read byte-exact; longest wait for data $maxWait ms');
    expect(maxWait, lessThan(2000), reason: 'assertion 2 (stall)');

    // Seek back to 5 %: that range was evicted, so it holds no disk blocks.
    final seekAt = totalA ~/ 20;
    final fileA = cache
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere(
          (f) =>
              f.path.endsWith(mode == 'http' ? '.partial' : 'a.bin') &&
              f.path.contains(mode == 'http' ? '' : 'a.bin'),
        );
    final evictedBytes = fs.allocatedBytes(
      fileA.path,
      offset: seekAt,
      length: 20 * _mib,
    );
    results.add(
      '(3) allocated in [5 %, +20 MiB] before seek: $evictedBytes bytes',
    );
    expect(
      evictedBytes,
      lessThanOrEqualTo(mode == 'http' ? 0 : 16 * 1024),
      reason: 'assertion 3 range empty',
    );
    await handleA.seekHint(seekAt);
    await read(handleA.playbackUri, mediaA, seekAt, seekAt + 20 * _mib - 1);
    results.add('(3) seek-back 20 MiB at 5 % byte-exact');
    expect(
      maxAlloc,
      lessThanOrEqualTo(limit + slack),
      reason: 'limit after seek-back',
    );

    // LRU: B must be gone by now (A needed the room); Clear cache empties the rest.
    final bLeft = cache
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.contains('b.bin') ||
              (mode == 'http' &&
                  f.path != fileA.path &&
                  f.path.endsWith('.partial')),
        )
        .toList();
    results.add(
      '(4) closed stream B files left after A streamed: ${bLeft.length}',
    );
    expect(bLeft, isEmpty, reason: 'assertion 4 LRU');
    await handleA.dispose();
    final freed = await source.clearCache();
    final left = cache.listSync(recursive: true).whereType<File>().toList();
    results.add(
      '(4) Clear cache freed ${freed ~/ _mib} MiB; files left: ${left.length}; records left: ${(await state.all()).length}',
    );
    expect(left, isEmpty, reason: 'assertion 4 Clear cache');
    await source.dispose();
    sampler.cancel();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
